# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "shellwords"
require "json"
require "tmpdir"

class TurnRouterTest < Minitest::Test
  def build_container(commands: nil, root: Dir.pwd, agent: nil)
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, **| text }
    {
      session: Struct.new(:budget_max, :cost).new(0, 0.0),
      agent: agent || Struct.new(:model).new("test-model"),
      renderer:,
      commands: commands || { "status" => Master::CLI::CommandRegistry::Command.new { "status-ok" } },
      root:,
      bus: nil,
    }
  end

  # Both, not just teardown. Clearing on the way out protects this file from
  # itself; clearing on the way in protects it from every other file, which is
  # where the leak actually came from (test_cli.rb builds tokenless CLIs).
  def setup
    Fiber[:master_visitor] = nil
  end

  def teardown
    Fiber[:master_visitor] = nil
  end

  # A question is answered, not dispatched: command inference would turn its words into a
  # council review or a shell lookup.
  def test_a_question_goes_to_the_agent_and_never_to_command_inference
    questions = ["In one sentence, what does MASTER/lib/face.rb do?",
                 "Which file defines Master::Face::Contract.stipple_profile?",
                 "why aren't you reading tts out loud?",
                 "how do I run the review pass through master?",
                 "is the council enabled"]
    questions.each do |message|
      reached = nil
      Master::CLI::TurnRouter.stub(:casual_reply, ->(*, **) { reached = :casual; Master::Result.ok({ rendered: "" }) }) do
        Master::CLI::TurnRouter.stub(:infer_operator_command, ->(*, **) { reached = :inferred; nil }) do
          Master::CLI::TurnRouter.call(message:, container: build_container)
        end
      end
      assert_equal :casual, reached, message
    end
  end

  def test_do_can_and_will_imperatives_are_not_misrouted_as_questions
    ["Do fix the broken tests", "Can refactor this method", "Will add authentication"].each do |text|
      refute Master::CLI::TurnRouter.question?(text), text
    end
    assert Master::CLI::TurnRouter.question?("Can refactor this method?")
    assert Master::CLI::TurnRouter.question?("Can you refactor this method?")
  end

  def test_direct_explain_and_describe_instructions_are_not_questions
    ["Explain why the tests fail", "Describe the API", "Please explain the failure"].each do |text|
      refute Master::CLI::TurnRouter.question?(text), text
    end
    assert Master::CLI::TurnRouter.question?("Why do the tests fail")
  end

  def test_an_instruction_is_still_not_a_question
    refute Master::CLI::TurnRouter.question?("run the tests in lib/io")
    refute Master::CLI::TurnRouter.question?("review rails")
    assert Master::CLI::TurnRouter.question?("what is the current model")
  end

  # Every former pipeline spelling is a mode of the one /fix dispatcher.
  def test_legacy_pipeline_words_rewrite_to_one_fix_mode
    router = Master::CLI::TurnRouter

    assert_equal "/fix lib/io", router.rewrite_slash("/fix lib/io")
    {
      audit: %w[audit review critique council],
      visual: %w[visual style],
      elevate: %w[elevate map],
      all: %w[all workflow triad sweep through self],
    }.each do |mode, words|
      words.each do |word|
        assert_equal "/fix --mode=#{mode} lib", router.rewrite_slash("/#{word} lib"), word
      end
    end

    assert_equal "/fix --mode=repair --dry-run RAILS", router.rewrite_slash("/scan RAILS")
    assert_equal "/fix --security lib", router.rewrite_slash("/security lib")
    assert_equal "/fix --prove history", router.rewrite_slash("/prove history")
    assert_equal "/fix --mode=audit", router.rewrite_slash("/fix --mode=audit")
    assert_equal ["fix"], router::PIPELINE_COMMANDS
    assert_equal %w[fix audit review critique council scan visual style elevate map all self workflow triad sweep through prove explain simplify security], router::PIPELINE_SLASH
  end

  def test_a_legacy_pipeline_word_is_accepted_from_model_inference
    router = Master::CLI::TurnRouter

    assert_equal "fix", router.send(:normalize_inferred_command, "scan")
    assert_equal "fix", router.send(:normalize_inferred_command, "review")
    assert_equal "fix", router.send(:normalize_inferred_command, "style")
    assert_equal "fix", router.send(:normalize_inferred_command, "elevate")
    assert_equal "fix", router.send(:normalize_inferred_command, "workflow")
  end

  def test_scan_is_a_read_only_repair_preview_not_a_second_command
    router = Master::CLI::TurnRouter

    refute_includes router::PIPELINE_COMMANDS, "scan"
    assert_equal "/fix --mode=repair --dry-run lib/io", router.rewrite_slash("/scan lib/io")
  end

  # The RAILS constitutional check asks for a reading it can grep and no writes.
  # The flag rides along rather than being eaten as a path.
  def test_a_read_only_fix_keeps_the_flag_the_rails_check_passes
    rewritten = Master::CLI::TurnRouter.rewrite_slash("/fix --dry-run ../RAILS/amber")

    assert_equal "/fix --dry-run ../RAILS/amber", rewritten
  end

  def test_semantic_operator_routing_resolves_inventory_aliases_and_exclusions
    response = {
      "intent" => "operator_action", "operation" => "deploy", "environment" => "production",
      "target_type" => "public", "target" => "public", "exclude" => ["master"],
      "confidence" => 0.96, "reason" => "All public app surfaces except the AI service.",
    }
    agent = Object.new
    agent.define_singleton_method(:ask_once) { |prompt, **options|
      raise "schema was not supplied" unless options[:format].is_a?(Hash)
      raise "inventory context missing" unless prompt.include?("Brgen")
      JSON.generate(response)
    }
    routed = nil
    Master::CLI::TurnRouter.stub(:dispatch_slash, lambda { |command, **|
      routed = command
      Master::Result.ok({ rendered: "captured" })
    }) do
      Master::CLI::TurnRouter.call(
        message: "Please refresh the public applications, but leave the AI service untouched",
        container: build_container(agent:),
      )
    end

    assert_equal "/deploy rails", routed
  end

  def test_semantic_operator_routing_preserves_only_explicit_confirmation
    agent = Object.new
    agent.define_singleton_method(:ask_once) do |_prompt, **|
      JSON.generate(
        "intent" => "operator_action", "operation" => "deploy", "environment" => "production",
        "target_type" => "group", "target" => "rails", "exclude" => [],
        "confidence" => 0.97, "reason" => "The requested application group.",
      )
    end
    routed = nil
    Master::CLI::TurnRouter.stub(:dispatch_slash, lambda { |command, **|
      routed = command
      Master::Result.ok({ rendered: "captured" })
    }) do
      Master::CLI::TurnRouter.call(
        message: "Could you roll out the Rails applications --confirm",
        container: build_container(agent:),
      )
    end

    assert_equal "/deploy rails --confirm", routed
  end

  def test_semantic_operator_question_is_not_dispatched_as_a_mutation
    agent = Object.new
    agent.define_singleton_method(:ask_once) do |_prompt, **|
      JSON.generate(
        "intent" => "conversation", "operation" => "none", "environment" => "unknown",
        "target_type" => "all", "target" => "all", "exclude" => [],
        "confidence" => 0.99, "reason" => "This is a question about a deployment.",
      )
    end
    reached = nil
    Master::CLI::TurnRouter.stub(:casual_reply, ->(*, **) { reached = :chat; Master::Result.ok({ rendered: "answer" }) }) do
      Master::CLI::TurnRouter.stub(:dispatch_slash, ->(*) { reached = :dispatch; flunk "a question must not dispatch" }) do
        Master::CLI::TurnRouter.call(
          message: "Why did the last deploy fail?",
          container: build_container(agent:),
        )
      end
    end

    assert_equal :chat, reached
  end

  def test_an_explicit_fix_reference_routes_all_named_trees_before_operator_intent
    message = "Pursue completion of /fix over RAILS MASTER OPENBSD STUDIO BIZ and push to pub5 main"
    routed = nil

    Master::CLI::TurnRouter.stub(:dispatch_slash, lambda { |command, **|
      routed = command
      Master::Result.ok({ rendered: "captured" })
    }) do
      Master::CLI::TurnRouter.call(message:, container: build_container)
    end

    assert_equal "/fix --mode=all RAILS MASTER OPENBSD STUDIO BIZ", routed
  end

  def test_status_question_bypasses_unavailable_operator_intent
    agent = Object.new
    agent.define_singleton_method(:model) { "test-model" }
    agent.define_singleton_method(:ask_once) { |*| raise "operator classifier must not run for questions" }
    container = build_container(agent:)
    reached = nil

    Master::CLI::TurnRouter.stub(:casual_reply, ->(*, **) {
      reached = :chat
      Master::Result.ok({ rendered: "status answer" })
    }) do
      Master::CLI::TurnRouter.call(message: "What's the status?", container:)
    end

    assert_equal :chat, reached
  end

  def test_a_file_read_is_not_casual_for_an_operator
    refute Master::CLI::TurnRouter.casual?("read CLAUDE.md")
  end

  # Security: ai.brgen.no serves the open internet, and AuthTier only *labels*
  # tokenless requests "visitor" rather than rejecting them. Everything past the
  # visitor check in TurnRouter.call can reach real capability — the Fold reaches
  # Core::World#do_exec with model-chosen argv, and infer_operator_command
  # reconstructs slash commands from plain English (defeating the leading-"/"
  # block in chat_controller#message). Visitors must land on casual_reply only.
  def test_visitor_cannot_reach_fold_or_command_registry
    ["fix the bug", "run master through itself", "implement pagination for posts"].each do |message|
      Fiber[:master_visitor] = true
      reached = :none

      Master::CLI::TurnRouter.stub(:run_fold, ->(*, **) { reached = :fold; Master::Result.ok({ rendered: "" }) }) do
        Master::CLI::TurnRouter.stub(:dispatch_inferred, ->(*, **) { reached = :command; Master::Result.ok({ rendered: "" }) }) do
          Master::CLI::TurnRouter.stub(:casual_reply, ->(*, **) { reached = :casual; Master::Result.ok({ rendered: "" }) }) do
            Master::CLI::TurnRouter.call(message:, container: build_container)
          end
        end
      end

      assert_equal :casual, reached, "visitor message #{message.inspect} escaped to #{reached}"
    end
  end

  def test_visitor_cannot_reach_media_intent
    Fiber[:master_visitor] = true
    reached = :none
    Master::Io::MediaIntent.stub(:dispatch, ->(*) { reached = :media; Master::Result.ok({ rendered: "" }) }) do
      Master::CLI::TurnRouter.stub(:casual_reply, ->(*, **) { reached = :casual; Master::Result.ok({ rendered: "" }) }) do
        Master::CLI::TurnRouter.call(message: "generate a photo of bergen", container: build_container)
      end
    end
    assert_equal :casual, reached
  end

  def test_visitor_can_attempt_pair_code_redemption_but_not_pair_status_or_other_slash_commands
    Fiber[:master_visitor] = true
    router = Master::CLI::TurnRouter
    assert router.visitor_pair_redemption?("/pair ABCDEFGH")
    refute router.visitor_pair_redemption?("/pair")
    refute router.visitor_pair_redemption?("/pair issue")
    refute router.visitor_pair_redemption?("/fix")
    refute router.visitor_pair_redemption?("/pair ABCDEFGI")
  end

  def test_run_fold_refuses_visitors_directly
    Fiber[:master_visitor] = true
    result = Master::CLI::TurnRouter.run_fold("do something", container: build_container)

    assert result.err?
    assert_match(/not available to visitors/, result.message.to_s)
    assert_equal :policy, result.category
  end

  def test_public_site_news_request_uses_tool_capable_chat_not_fold
    message = "Go to www.nrk.no, give me today's news in norwegian"
    reached = :none

    Master::CLI::TurnRouter.stub(:casual_reply, lambda { |text, **|
      reached = :chat
      Master::Result.ok({ rendered: text })
    }) do
      Master::CLI::TurnRouter.stub(:run_fold, ->(*) { reached = :fold; flunk "read-only web research must not enter the coding fold" }) do
        result = Master::CLI::TurnRouter.call(message:, container: build_container)

        assert result.ok?
        assert_equal :chat, reached
        assert_equal message, result.value[:rendered]
      end
    end
  end

  def test_public_site_request_with_mutating_intent_is_not_classified_as_research
    refute Master::CLI::TurnRouter.public_research_request?(
      "Go to https://example.com and publish this post",
    )
  end

  def test_authenticated_turns_still_reach_fold
    Fiber[:master_visitor] = nil
    reached = :none

    Master::CLI::TurnRouter.stub(:run_fold, ->(*, **) { reached = :fold; Master::Result.ok({ rendered: "" }) }) do
      Master::CLI::TurnRouter.call(message: "implement pagination for posts", container: build_container)
    end

    assert_equal :fold, reached
  end

  # A coding goal that Infer does not promote to an operator command: "fix the
  # bug" now routes to /fix via PIPELINE_COMMANDS, so it no longer reaches the
  # Fold. This message stays plain language all the way down.
  def test_plain_language_routes_to_fold
    fold = { reason: :complete, turns: 1, summary: "done", transcript: [] }
    Master.stub(:any_api_key_present?, true) do
      Master::CLI::CoreBridge.stub(:run, fold) do
        result = Master::CLI::TurnRouter.call(message: "implement pagination for posts", container: build_container)
        assert result.ok?, -> { "fold errored: #{result.message}" }
        assert_match(/fold0: complete/, result.value[:rendered])
      end
    end
  end

  # /fix writes code; a person asking about a heater or a bike is not asking for it.
  def test_fix_about_things_that_are_not_code_is_not_the_command
    fix = Master::CLI::TurnRouter::FIX_COMMAND

    ["fix the heater in my flat", "fix my bike", "fix it", "fixing things is hard"].each do |text|
      refute_match fix, text
    end

    ["fix", "fix lib/cli", "fix rails", "fix the failing tests", "fix the lint violations"].each do |text|
      assert_match fix, text
    end
  end

  # Bare words the operator types as whole instructions. "status?" ends in a
  # question mark, which question?() would otherwise read as chat; the
  # go-words mean continue the work. A sentence that merely contains the
  # words stays a sentence.
  def test_imperative_shorthands_are_whole_utterances_only
    router = Master::CLI::TurnRouter

    assert_equal "/status", router.imperative_shorthand("status")
    assert_equal "/status", router.imperative_shorthand("status?")
    assert_equal "/status", router.imperative_shorthand("Status.")
    assert_equal "/fix", router.imperative_shorthand("go")
    assert_equal "/fix", router.imperative_shorthand("go on")
    assert_equal "/fix", router.imperative_shorthand("keep going")
    assert_equal "/fix", router.imperative_shorthand("Keep going!")
    assert_equal "/fix", router.imperative_shorthand("carry on")

    [nil, "gone fishing", "keep going, I'll make coffee",
     "how do I keep going?", "status of the deploy", "go away"].each do |text|
      assert_nil router.imperative_shorthand(text), text.inspect
    end
  end

  def test_a_status_question_dispatches_status_not_a_chat
    ran = []
    command = Master::CLI::CommandRegistry::Command.new { ran << :status; "status-ok" }
    container = build_container(commands: { "status" => command })
    Master::CLI::TurnRouter.stub(:casual_reply, ->(*, **) { flunk "status? reached casual chat" }) do
      Master::CLI::TurnRouter.stub(:run_fold, ->(*, **) { flunk "status? reached the fold" }) do
        result = Master::CLI::TurnRouter.call(message: "status?", container:)
        assert result.ok?
      end
    end
    assert_equal [:status], ran
  end

  def test_a_bare_go_continues_the_convergence_work
    ran = []
    command = Master::CLI::CommandRegistry::Command.new { ran << :fix; "fix-ok" }
    container = build_container(commands: { "status" => command, "fix" => command })
    Master::CLI::TurnRouter.stub(:casual_reply, ->(*, **) { flunk "keep going reached casual chat" }) do
      Master::CLI::TurnRouter.stub(:run_fold, ->(*, **) { flunk "keep going reached the fold" }) do
        result = Master::CLI::TurnRouter.call(message: "keep going", container:)
        assert result.ok?
      end
    end
    assert_equal [:fix], ran
  end

  def test_fix_language_is_promoted_to_operator_command_not_fold
    inferred = Master::CLI::TurnRouter.infer_operator_command("fix the bug", container: build_container)

    refute_nil inferred, "expected Infer to promote 'fix the bug' to an operator command"
    assert_includes Master::CLI::TurnRouter::PIPELINE_COMMANDS, inferred[:command]
  end

  def test_a_sentence_asking_to_fix_reaches_the_writing_verb
    inferred = Master::CLI::TurnRouter.infer_operator_command("can you fix and commit all these violations?",
                                                              container: build_container)

    assert_equal "fix", inferred[:command]
    assert_match(%r{\A/fix}, Master::CLI::TurnRouter.rewrite_slash("/#{inferred[:command]} #{inferred[:args]}"))
  end

  # The command is gone; the word people use for it still reaches the engine,
  # because asking to be told what is wrong is where a fix starts.
  def test_a_sentence_asking_to_scan_reaches_the_same_engine
    assert_equal "fix", Master::CLI::TurnRouter.send(:normalize_inferred_command, "scan")
  end

  def test_pipeline_inference_preserves_narrower_target_arguments
    router = Master::CLI::TurnRouter
    value = Struct.new(:args).new("rails")

    assert_equal "rails/brgen", router.pass_command_args(value, "review rails/brgen")
    assert_equal "rails/brgen", router.pass_command_args(Struct.new(:args).new("rails/brgen"), "review rails")
    assert_equal "master", router.pass_command_args(Struct.new(:args).new("itself"), "run through itself")
  end

  def test_an_inferred_word_no_handler_takes_stays_a_sentence
    inferred = Master::CLI::TurnRouter.infer_operator_command("read lib/trace/dmesg.rb and summarise it",
                                                              container: build_container)

    assert_nil inferred, "no handler answers /dmesg, so the sentence must reach the model"
  end

  def test_slash_routes_to_command_registry_not_fold_or_chat
    ran = []
    command = Master::CLI::CommandRegistry::Command.new { ran << :status; "status-ok" }
    Master::CLI::TurnRouter.stub(:run_fold, ->(*, **) { flunk "/status reached the fold" }) do
      Master::CLI::TurnRouter.stub(:casual_reply, ->(*, **) { flunk "/status reached casual chat" }) do
        Master::CLI::TurnRouter.call(message: "/status", container: build_container(commands: { "status" => command }))
      end
    end
    assert_equal [:status], ran
  end

  def test_slash_status_renders_command_output
    result = Master::CLI::TurnRouter.call(message: "/status", container: build_container)
    assert result.ok?
    assert_match(/status-ok/, result.value[:rendered].to_s)
  end

  def test_slash_command_context_keeps_the_turn_cancellation_token
    token = Master::Core::CancellationToken.new
    seen = nil
    command = Master::CLI::CommandRegistry::Command.new do |ctx|
      seen = ctx.cancellation
      "status-ok"
    end
    container = build_container(commands: { "status" => command })

    result = Master::CLI::TurnRouter.call(message: "/status", container:, cancellation: token)

    assert result.ok?
    assert_same token, seen
  end

  # ChatService builds image_payload from the upload token, but the face used
  # to drop it: TurnRouter.casual_reply never put :image on the agent ctx, so
  # a visitor who attached a photo talked to a model that could not see it.
  def test_casual_reply_forwards_image_to_the_agent
    image = { data: "abc", mime: "image/jpeg", name: "x.jpg" }
    seen = nil
    agent = Object.new
    agent.define_singleton_method(:call) do |ctx|
      seen = ctx
      Master::Result.ok("ok")
    end
    container = build_container.merge(agent:)

    Master.stub(:any_api_key_present?, true) do
      result = Master::CLI::TurnRouter.casual_reply("what is this", container:, image:)
      assert result.ok?
    end

    assert_equal image, seen[:image]
    assert_equal "what is this", seen[:message]
  end

  def test_run_promotes_to_fold
    fold = { reason: :complete, turns: 1, summary: "shipped", transcript: [] }
    Master.stub(:any_api_key_present?, true) do
      Master::CLI::CoreBridge.stub(:run, fold) do
        result = Master::CLI::TurnRouter.call(message: "/run add tests", container: build_container)
        assert result.ok?, -> { "fold errored: #{result.message}" }
        assert_match(/shipped/, result.value[:rendered])
      end
    end
  end
  # LoRA video requests use the named STUDIO subject model and bypass generic
  # command inference; the source image remains untouched by the animation lane.
  def test_lora_video_request_is_dispatched_before_command_inference
    Dir.mktmpdir("turn-router-lora") do |root|
      still = File.join(root, "johann_selfie_01.jpg")
      File.write(still, "fixture")
      fake = Object.new
      fake.define_singleton_method(:animate) do |source, prompt:, subject:, duration:|
        { still: source, clip: File.join(root, "johann_film_test.mp4") }
      end

      Master::Io::IdeaPicture.stub(:new, fake) do
        Master::CLI::TurnRouter.stub(:infer_operator_command, ->(*) { raise "media intent fell through to command inference" }) do
          result = Master::CLI::TurnRouter.call(
            message: "make a video with Johann's lora from #{still}",
            container: build_container(root:),
          )

          assert result.ok?, -> { result.message.to_s }
          assert_equal :lora_video, result.value!.fetch(:media)
          assert_equal "johann", result.value!.fetch(:subject)
        end
      end
    end
  end

  def test_blocked_fold_report_does_not_dump_a_read_file
    private_text = "sensitive project instructions\n" + Array.new(24) { |index| "private detail #{index + 1}\n" }.join
    transcript = ["0: read(path) -> ok: #{private_text}"]
    result = Master::CLI::TurnRouter.fold_to_result(
      reason: :blocked, turns: 5, risk: :medium,
      summary: "blocked: command execution is not enabled; no command was run",
      transcript:,
    )

    refute result.ok?
    assert_match(/0: read\(path\) -> ok: \d+B, 25 lines/, result.message)
    refute_includes result.message, "private detail 24"
    assert_includes result.message, "no command was run"
  end

  def test_fold_result_preserves_cancellation_and_ambiguous_outcome_categories
    cancelled = Master::CLI::TurnRouter.fold_to_result(
      reason: :cancelled, turns: 1, summary: "cancelled", transcript: [],
    )
    audit_failed = Master::CLI::TurnRouter.fold_to_result(
      reason: :trace_failed, turns: 1, summary: "after-event failed", transcript: [],
    )
    unknown = Master::CLI::TurnRouter.fold_to_result(
      reason: :unknown_outcome, turns: 1, summary: "receipt missing", transcript: [],
    )
    recovery_failed = Master::CLI::TurnRouter.fold_to_result(
      reason: :recovery_failed, turns: 1, summary: "rollback unproven", transcript: [],
    )
    approval = Master::CLI::TurnRouter.fold_to_result(
      reason: :needs_user, turns: 1, summary: "approval unavailable", transcript: [],
    )

    assert_equal :cancelled, cancelled.category
    assert_equal :unknown_outcome, audit_failed.category
    assert_equal :unknown_outcome, unknown.category
    assert_equal :recovery_failed, recovery_failed.category
    assert_equal :human_decision, approval.category
    [cancelled, audit_failed, unknown, recovery_failed, approval].each { |result| refute result.ok? }
  end

  def test_inferred_slash_route_retains_the_active_cancellation_token
    token = Master::Core::CancellationToken.new
    container = build_container
    captured = nil
    dispatcher = lambda do |input, container:, felt_sense: nil, on_turn: nil, cancellation: nil|
      captured = { input:, cancellation: }
      Master::Result.ok({ rendered: "routed" })
    end

    Master::CLI::TurnRouter.stub(:dispatch_slash, dispatcher) do
      result = Master::CLI::TurnRouter.dispatch_inferred(
        { command: "run", args: "read README.md", confidence: 0.9 },
        container:, cancellation: token,
      )
      assert result.ok?
    end

    assert_equal "/run read README.md", captured[:input]
    assert_same token, captured[:cancellation]
  end

  def test_fold_routing_activates_cooperative_cancellation_before_setup
    token = Master::Core::CancellationToken.new
    Master.stub(:llm_reachable?, false) do
      result = Master::CLI::TurnRouter.run_fold(
        "inspect the project", container: build_container, cancellation: token
      )
      refute result.ok?
      assert_predicate token, :active?
    end
  end

  def test_document_archive_intent_is_narrow_and_extracts_a_folder
    router = Master::CLI::TurnRouter

    assert router.document_archive_request?("please transcribe the handwritten letters in photos folder")
    assert router.document_archive_request?("enter the photos folder and analyze some letters")
    assert router.document_archive_request?("tell MASTER to enter the photos folder and analyze some letters")
    refute router.document_archive_request?("can you analyze these letters?")
    refute router.document_archive_request?("analyze the Rails controller")
    refute router.document_archive_request?("I wonder how to transcribe these old letters")
    assert_equal "~/Photos/Letters", Shellwords.split(router.document_archive_args("transcribe the letters in ~/Photos/Letters")).first
    assert_equal "photos", Shellwords.split(router.document_archive_args("transcribe the letters")).first
  end

  def test_plain_language_letter_request_routes_to_the_documents_command
    routed = nil
    message = "please decipher the handwritten letters in ~/Photos"
    container = build_container
    Master::CLI::TurnRouter.stub(:dispatch_slash, lambda { |slash, **|
      routed = slash
      Master::Result.ok({ rendered: "document archive started" })
    }) do
      result = Master::CLI::TurnRouter.call(message:, container:)
      assert_predicate result, :ok?
    end
    assert_equal "/documents analyze \\~/Photos", routed
  end

end
