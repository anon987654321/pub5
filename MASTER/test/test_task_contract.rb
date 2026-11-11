# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/fix/task_contract"
require_relative "../lib/fix/artifact_preservation"
require_relative "../lib/fix/transaction"

class TestTaskContract < Minitest::Test
  CONTRACT = Master::Fix::TaskContract

  def test_current_contract_is_nested_and_restored_after_exceptions
    first = CONTRACT.build(intent: "content_only", scope: ["one.txt"], preserve: [], proof: [])
    second = CONTRACT.build(intent: "content_only", scope: ["two.txt"], preserve: [], proof: [])

    assert_nil CONTRACT.current
    assert_raises(RuntimeError) do
      CONTRACT.with_current(first) do
        assert_equal first, CONTRACT.current
        CONTRACT.with_current(second) { assert_equal second, CONTRACT.current }
        assert_equal first, CONTRACT.current
        raise "leave the contract scope"
      end
    end
    assert_nil CONTRACT.current
  end

  def test_preservation_receipts_are_plan_bound_and_nested_scopes_are_restored
    first = CONTRACT.build(intent: "content_only", scope: ["page.html"], preserve: [], proof: [])
    second = CONTRACT.build(intent: "functional_change", scope: ["worker.rb"], preserve: [], proof: [])
    result = Master::Fix::ArtifactPreservation::Result.new("PASS", ["html_markup"], nil)

    CONTRACT.with_current(first) do
      CONTRACT.attach_plan!("a" * 64)
      row = CONTRACT.record_preservation!(
        path: File.join(Master::REPO_ROOT, "page.html"),
        format: "html",
        before: "<p>before</p>",
        after: "<p>after</p>",
        result:,
      )
      assert_equal "a" * 64, row.fetch("plan_digest")
      assert_match(/\A[0-9a-f]{64}\z/, row.fetch("before_sha256"))
      assert_equal "INCONCLUSIVE", CONTRACT.preservation_evidence.fetch("status")

      CONTRACT.with_current(second) do
        assert_equal "not_measured", CONTRACT.preservation_evidence.fetch("status")
        CONTRACT.attach_plan!("b" * 64)
        CONTRACT.record_preservation!(
          path: File.join(Master::REPO_ROOT, "worker.rb"),
          format: "rb",
          before: "x = 1",
          after: "x = 2",
          result: Master::Fix::ArtifactPreservation::Result.new("INCONCLUSIVE", [], "no Ruby source verifier"),
        )
        assert_equal "b" * 64, CONTRACT.preservation_evidence.fetch("plan_digest")
      end

      evidence = CONTRACT.preservation_evidence
      assert_equal "a" * 64, evidence.fetch("plan_digest")
      assert_equal ["page.html"], evidence.fetch("results").map { |entry| entry.fetch("path") }
    end

    assert_equal "not_measured", CONTRACT.preservation_evidence.fetch("status")
  end

  def test_preservation_receipts_must_stay_inside_the_active_task_scope
    contract = CONTRACT.build(intent: "content_only", scope: ["page.html"], preserve: [], proof: [])
    result = Master::Fix::ArtifactPreservation::Result.new("PASS", ["html_markup"], nil)

    CONTRACT.with_current(contract) do
      assert_raises(CONTRACT::Invalid) do
        CONTRACT.record_preservation!(
          path: File.join(Master::REPO_ROOT, "outside.html"),
          format: "html", before: "a", after: "b", result:
        )
      end
      assert_raises(CONTRACT::Invalid) do
        CONTRACT.record_preservation!(
          path: File.join(Dir.tmpdir, "outside-repository.html"),
          format: "html", before: "a", after: "b", result:
        )
      end
      assert_equal "not_measured", CONTRACT.preservation_evidence.fetch("status")
    end
  end

  def test_preservation_receipts_refuse_symlinked_paths
    Dir.mktmpdir("task-contract-link", Master::REPO_ROOT) do |root|
      Dir.mktmpdir("task-contract-outside") do |outside|
        relative = root.delete_prefix(Master::REPO_ROOT + File::SEPARATOR)
        File.write(File.join(outside, "outside.html"), "outside")
        File.symlink(File.join(outside, "outside.html"), File.join(root, "linked.html"))
        contract = CONTRACT.build(
          intent: "content_only", scope: ["#{relative}/**"], preserve: [], proof: []
        )
        result = Master::Fix::ArtifactPreservation::Result.new("PASS", ["html_markup"], nil)

        CONTRACT.with_current(contract) do
          error = assert_raises(CONTRACT::Invalid) do
            CONTRACT.record_preservation!(
              path: File.join(root, "linked.html"),
              format: "html", before: "a", after: "b", result:
            )
          end
          assert_match(/symlink/, error.message)
        end
      end
    end
  end

  def test_preservation_summary_does_not_pass_uncovered_required_dimensions
    contract = CONTRACT.build(intent: "content_only", scope: ["page.html"], preserve: [], proof: [])
    result = Master::Fix::ArtifactPreservation::Result.new(
      "PASS", ["rendered_visual_custody"], nil
    )

    CONTRACT.with_current(contract) do
      CONTRACT.attach_plan!("c" * 64)
      row = CONTRACT.record_preservation!(
        path: File.join(Master::REPO_ROOT, "page.html"),
        format: "html", before: "same", after: "same", result:,
        verifier: "visual_custody"
      )
      evidence = CONTRACT.preservation_evidence

      assert_equal %w[visual_identity layout], row.fetch("dimensions")
      assert_equal "INCONCLUSIVE", evidence.fetch("status")
      assert_includes evidence.fetch("missing_dimensions"), "accessibility"
      assert_equal "c" * 64, evidence.fetch("plan_digest")
    end
  end

  def test_attach_plan_rejects_unvalidated_digest_strings
    contract = CONTRACT.build(intent: "content_only", scope: ["page.html"], preserve: [], proof: [])

    CONTRACT.with_current(contract) do
      assert_raises(CONTRACT::Invalid) { CONTRACT.attach_plan!("not-a-digest") }
      refute CONTRACT.preservation_evidence.key?("plan_digest")
    end
  end

  def test_preservation_receipts_from_an_older_fix_plan_cannot_prove_the_new_generation
    contract = CONTRACT.build(intent: "content_only", scope: ["page.html"], preserve: [], proof: [])
    result = Master::Fix::ArtifactPreservation::Result.new("PASS", ["html_markup"], nil)

    CONTRACT.with_current(contract) do
      CONTRACT.attach_plan!("1" * 64)
      CONTRACT.record_preservation!(
        path: File.join(Master::REPO_ROOT, "page.html"),
        format: "html", before: "before", after: "after", result:
      )
      CONTRACT.attach_plan!("2" * 64)

      evidence = CONTRACT.preservation_evidence
      assert_equal "INCONCLUSIVE", evidence.fetch("status")
      assert_equal "2" * 64, evidence.fetch("plan_digest")
      assert_equal 1, evidence.fetch("plan_mismatch_count")
      assert_match(/different FixPlan/, evidence.fetch("reason"))
    end
  end

  def test_preservation_summary_requires_a_fix_plan_binding
    contract = CONTRACT.build(intent: "functional_change", scope: ["worker.rb"], preserve: [], proof: [])
    result = Master::Fix::ArtifactPreservation::Result.new(
      "PASS", ["rendered_visual_custody"], nil
    )

    CONTRACT.with_current(contract) do
      CONTRACT.record_preservation!(
        path: File.join(Master::REPO_ROOT, "worker.rb"),
        format: "html", before: "same", after: "same", result:,
        verifier: "visual_custody"
      )
      evidence = CONTRACT.preservation_evidence

      assert_equal "INCONCLUSIVE", evidence.fetch("status")
      assert_match(/not bound to a FixPlan/, evidence.fetch("reason"))
    end
  end

  def test_unregistered_preservation_verifier_cannot_claim_external_evidence
    contract = CONTRACT.build(intent: "content_only", scope: ["page.html"], preserve: [], proof: [])
    result = Master::Fix::ArtifactPreservation::Result.new("PASS", ["rendered_visual_custody"], nil)

    CONTRACT.with_current(contract) do
      error = assert_raises(CONTRACT::Invalid) do
        CONTRACT.record_preservation!(
          path: File.join(Master::REPO_ROOT, "page.html"),
          format: "html", before: "a", after: "a", result:,
          verifier: "model_says_pass"
        )
      end
      assert_match(/unregistered preservation verifier/, error.message)
      assert_equal "not_measured", CONTRACT.preservation_evidence.fetch("status")
    end
  end

  def test_preservation_evidence_overflow_is_inconclusive_without_dropping_old_rows
    contract = CONTRACT.build(intent: "content_only", scope: ["page.html"], preserve: [], proof: [])
    result = Master::Fix::ArtifactPreservation::Result.new("PASS", ["html_markup"], nil)

    CONTRACT.with_current(contract) do
      CONTRACT.attach_plan!("d" * 64)
      (CONTRACT::MAX_PRESERVATION_ROWS + 1).times do
        CONTRACT.record_preservation!(
          path: File.join(Master::REPO_ROOT, "page.html"),
          format: "html", before: "same", after: "same", result:
        )
      end

      evidence = CONTRACT.preservation_evidence
      assert_equal "INCONCLUSIVE", evidence.fetch("status")
      assert_equal CONTRACT::MAX_PRESERVATION_ROWS, evidence.fetch("result_count")
      assert_equal 1, evidence.fetch("overflow_count")
      assert_match(/exceeded the #{CONTRACT::MAX_PRESERVATION_ROWS}-row evidence limit/, evidence.fetch("reason"))
    end
  end

  def test_preservation_receipts_go_stale_when_the_artifact_changes_after_verification
    Dir.mktmpdir("task-contract-stale", Master::REPO_ROOT) do |root|
      relative = root.delete_prefix(Master::REPO_ROOT + File::SEPARATOR)
      path = File.join(root, "page.html")
      before = "<main>before</main>"
      after = "<main>after</main>"
      File.write(path, after)
      contract = CONTRACT.build(
        intent: "content_only", scope: ["#{relative}/page.html"], preserve: [], proof: []
      )
      result = Master::Fix::ArtifactPreservation::Result.new(
        "PASS", ["rendered_visual_custody"], nil
      )

      CONTRACT.with_current(contract) do
        CONTRACT.attach_plan!("e" * 64)
        CONTRACT.record_preservation!(
          path:, format: "html", before:, after:, result:, verifier: "visual_custody"
        )
        current = CONTRACT.preservation_evidence
        assert_empty current.fetch("stale_paths")

        File.write(path, "<main>changed later</main>")
        stale = CONTRACT.preservation_evidence
        assert_equal "INCONCLUSIVE", stale.fetch("status")
        assert_equal ["#{relative}/page.html"], stale.fetch("stale_paths")
        assert_match(/no longer matches/, stale.fetch("reason"))
      end
    end
  end

  def test_preservation_receipt_becomes_stale_if_its_artifact_is_replaced_by_a_symlink
    Dir.mktmpdir("task-contract-symlinked-after", Master::REPO_ROOT) do |root|
      Dir.mktmpdir("task-contract-symlink-target") do |outside|
        relative = root.delete_prefix(Master::REPO_ROOT + File::SEPARATOR)
        path = File.join(root, "page.html")
        external = File.join(outside, "page.html")
        before = "before"
        after = "after"
        File.write(path, after)
        File.write(external, after)
        contract = CONTRACT.build(
          intent: "content_only", scope: ["#{relative}/page.html"], preserve: [], proof: []
        )
        result = Master::Fix::ArtifactPreservation::Result.new(
          "PASS", ["rendered_visual_custody"], nil
        )

        CONTRACT.with_current(contract) do
          CONTRACT.attach_plan!("f" * 64)
          CONTRACT.record_preservation!(
            path:, format: "html", before:, after:, result:, verifier: "visual_custody"
          )
          File.delete(path)
          File.symlink(external, path)

          evidence = CONTRACT.preservation_evidence
          assert_equal "INCONCLUSIVE", evidence.fetch("status")
          assert_equal ["#{relative}/page.html"], evidence.fetch("stale_paths")
        end
      end
    end
  end

  def test_transaction_rejects_out_of_scope_paths_before_snapshotting
    Dir.mktmpdir("task-contract-transaction") do |root|
      contract = CONTRACT.build(intent: "functional_change", scope: ["allowed.txt"], preserve: [], proof: [])

      CONTRACT.with_current(contract) do
        transaction = Master::Fix::Transaction.new(root:, paths: ["allowed.txt"])
        assert_instance_of Master::Fix::Transaction, transaction
        assert_raises(CONTRACT::Invalid) do
          Master::Fix::Transaction.new(root:, paths: ["blocked.txt"])
        end
      end
    end
  end

  def test_transaction_rejects_out_of_scope_enlistment
    Dir.mktmpdir("task-contract-enlistment") do |root|
      contract = CONTRACT.build(intent: "functional_change", scope: ["allowed.txt"], preserve: [], proof: [])

      CONTRACT.with_current(contract) do
        transaction = Master::Fix::Transaction.new(root:, paths: ["allowed.txt"]).begin!
        result = transaction.enlist!(["blocked.txt"])
        refute result.ok?
        assert_equal :policy, result.category
        assert_match(/outside task-contract scope/, result.message)
        assert transaction.rollback!.ok?
      end
    end
  end

  def test_new_paths_are_exact_justified_and_inside_scope
    contract = CONTRACT.build(
      intent: "functional_change",
      scope: ["MASTER/lib/example.rb"],
      preserve: [],
      proof: [],
      new_paths: [{ path: "MASTER/lib/example.rb", reason: "A separately loaded protocol adapter." }],
    )

    assert_equal [{ "path" => "MASTER/lib/example.rb", "reason" => "A separately loaded protocol adapter." }],
                 contract.new_paths
    assert_equal contract.new_paths, contract.to_h.fetch("new_paths")
    assert_includes CONTRACT.agent_schema.fetch("optional_fields"), "new_paths"

    assert_raises(CONTRACT::Invalid) do
      CONTRACT.build(intent: "functional_change", scope: ["MASTER/lib/example.rb"],
                      preserve: [], proof: [], new_paths: [{ path: "MASTER/lib/example.rb" }])
    end
    assert_raises(CONTRACT::Invalid) do
      CONTRACT.build(intent: "functional_change", scope: ["MASTER/lib/**"],
                      preserve: [], proof: [], new_paths: [{ path: "MASTER/lib/example.rb", reason: "Scoped" },
                                                          { path: "MASTER/lib/example.rb", reason: "Duplicate" }])
    end
    assert_raises(CONTRACT::Invalid) do
      CONTRACT.build(intent: "functional_change", scope: ["MASTER/lib/**"],
                      preserve: [], proof: [], new_paths: [{ path: "MASTER/lib/new*.rb", reason: "Wildcard" }])
    end
    assert_raises(CONTRACT::Invalid) do
      CONTRACT.build(intent: "functional_change", scope: ["MASTER/lib/existing.rb"],
                      preserve: [], proof: [], new_paths: [{ path: "MASTER/lib/example.rb", reason: "Outside scope" }])
    end
  end

  def test_new_path_refusal_only_requires_declaration_for_missing_repo_paths
    Dir.mktmpdir("task-contract-new-path", Master::REPO_ROOT) do |root|
      relative = File.join(root.delete_prefix(Master::REPO_ROOT + File::SEPARATOR), "new.rb")
      path = File.join(root, "new.rb")
      undeclared = CONTRACT.build(intent: "functional_change", scope: [relative], preserve: [], proof: [])
      declared = CONTRACT.build(
        intent: "functional_change", scope: [relative], preserve: [], proof: [],
        new_paths: [{ path: relative, reason: "A distinct executable entrypoint." }],
      )

      assert_match(/new tracked path/, CONTRACT.new_path_refusal(path, contract: undeclared))
      assert_nil CONTRACT.new_path_refusal(path, contract: declared)
      File.write(path, "existing")
      assert_nil CONTRACT.new_path_refusal(path, contract: undeclared)
    end
  end

  def test_new_path_gate_refuses_symlinked_existing_targets_and_parents
    Dir.mktmpdir("task-contract-links", Master::REPO_ROOT) do |root|
      Dir.mktmpdir("task-contract-outside") do |outside|
        relative = root.delete_prefix(Master::REPO_ROOT + File::SEPARATOR)
        external = File.join(outside, "external.rb")
        File.write(external, "VALUE = true\n")
        linked = File.join(root, "linked.rb")
        File.symlink(external, linked)

        assert_match(/traverses a symlink/, CONTRACT.new_path_refusal(linked))

        nested = File.join(root, "nested")
        File.symlink(outside, nested)
        assert_match(/traverses a symlink/, CONTRACT.new_path_refusal(File.join(nested, "new.rb")))

        normal = File.join(root, "normal.rb")
        File.write(normal, "VALUE = false\n")
        assert_nil CONTRACT.new_path_refusal(normal)
      end
    end
  end

  def test_new_path_gate_refuses_hardlinked_existing_targets
    Dir.mktmpdir("task-contract-hardlink", Master::REPO_ROOT) do |root|
      original = File.join(root, "original.rb")
      linked = File.join(root, "linked.rb")
      File.write(original, "VALUE = true\n")
      File.link(original, linked)

      assert_match(/hard-linked/, CONTRACT.new_path_refusal(linked))
    end
  end

  def test_a_reviewed_plan_declares_the_paths_it_names
    Dir.mktmpdir("task-contract-declared", Master::REPO_ROOT) do |root|
      relative = File.join(root.delete_prefix(Master::REPO_ROOT + File::SEPARATOR), "planned.rb")
      path = File.join(root, "planned.rb")

      CONTRACT.with_current(nil) do
        assert_match(/new tracked path/, CONTRACT.new_path_refusal(path))
        assert_nil CONTRACT.new_path_refusal(path, declared: [relative])
        assert_match(/new tracked path/, CONTRACT.new_path_refusal(path, declared: ["some/other.rb"]))
      end
    end
  end

  def test_agent_prompt_explains_default_deny_new_path_policy
    prompt = CONTRACT.prompt

    assert_includes prompt, "A missing task contract is an empty new_paths declaration"
    assert_includes prompt, "must refuse every new tracked path"
  end

  def test_missing_contract_defaults_to_existing_paths_only
    Dir.mktmpdir("task-contract-default", Master::REPO_ROOT) do |root|
      path = File.join(root, "new.rb")

      CONTRACT.with_current(nil) do
        assert_match(/new tracked path/, CONTRACT.new_path_refusal(path))
        File.write(path, "existing")
        assert_nil CONTRACT.new_path_refusal(path)
      end
    end
  end

  def test_transaction_rejects_new_paths_without_an_active_contract
    Dir.mktmpdir("task-contract-default-transaction", Master::REPO_ROOT) do |root|
      relative = File.join(root.delete_prefix(Master::REPO_ROOT + File::SEPARATOR), "new.rb")

      CONTRACT.with_current(nil) do
        assert_raises(CONTRACT::Invalid) do
          Master::Fix::Transaction.new(root: Master::REPO_ROOT, paths: [relative])
        end
      end
    end
  end

  def test_transaction_rejects_undeclared_new_paths_and_accepts_declared_ones
    Dir.mktmpdir("task-contract-new-transaction", Master::REPO_ROOT) do |root|
      relative = File.join(root.delete_prefix(Master::REPO_ROOT + File::SEPARATOR), "created.rb")
      denied = CONTRACT.build(intent: "functional_change", scope: [relative], preserve: [], proof: [])
      allowed = CONTRACT.build(
        intent: "functional_change", scope: [relative], preserve: [], proof: [],
        new_paths: [{ path: relative, reason: "A distinct runtime adapter." }],
      )

      CONTRACT.with_current(denied) do
        assert_raises(CONTRACT::Invalid) { Master::Fix::Transaction.new(root:, paths: ["created.rb"]) }
      end

      CONTRACT.with_current(allowed) do
        transaction = Master::Fix::Transaction.new(root:, paths: ["created.rb"]).begin!
        assert transaction.rollback!.ok?
      end
    end
  end

  def test_content_only_adds_all_mandatory_preservation_and_proof
    contract = CONTRACT.build(
      intent: "content_only",
      scope: ["FETAT.html"],
      preserve: ["visual_identity"],
      proof: ["focused_tests"],
    )

    assert_includes contract.preserve, "structure"
    assert_includes contract.preserve, "operator_owned_values"
    assert_includes contract.proof, "baseline_hashes"
    assert_includes contract.proof, "law_assessment"
  end

  def test_rejects_parent_traversal_and_absolute_paths
    ["../outside", "/etc/passwd", "RAILS/../../outside"].each do |path|
      assert_raises(CONTRACT::Invalid) do
        CONTRACT.build(intent: "content_only", scope: [path], preserve: [], proof: [])
      end
    end
  end

  def test_rejects_unknown_intent_and_proof_type
    base = { scope: ["MASTER/file.rb"], preserve: [], proof: [] }
    assert_raises(CONTRACT::Invalid) { CONTRACT.build(base.merge(intent: "make_it_pretty")) }
    assert_raises(CONTRACT::Invalid) do
      CONTRACT.build(base.merge(intent: "content_only", proof: ["trust_me"]))
    end
  end

  def test_contract_round_trips_and_covers_a_scoped_file
    contract = CONTRACT.build(
      intent: "functional_change",
      scope: ["RAILS/brgen/**"],
      preserve: [],
      proof: %w[focused_tests rendered_evidence],
    )

    assert_equal 1, contract.to_h.fetch("schema")
    assert_equal "functional_change", contract.to_h.fetch("intent")
    refute contract.to_h.key?("new_paths"), "empty declarations preserve the legacy contract digest shape"
    assert CONTRACT.covers?("RAILS/brgen/app/models/item.rb", scope: contract.scope)
    refute CONTRACT.covers?("RAILS/amber/app/models/item.rb", scope: contract.scope)
    assert_equal %w[baseline_hashes law_assessment path_scoped_diff],
                 contract.proof.grep(/baseline_hashes|law_assessment|path_scoped_diff/)
  end

  def test_documentation_review_is_an_accepted_proof_type
    contract = CONTRACT.build(
      intent: "functional_change",
      scope: ["MASTER/data/task_contract.yml"],
      preserve: [],
      proof: ["documentation_review"],
    )

    assert_includes contract.proof, "documentation_review"
  end
end
