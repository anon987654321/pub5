# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"
require "fix/design_audit"

# The design audit reads shape, so each test builds the shape on a scratch tree and asks what it reports.
class TestDesignAudit < Minitest::Test
  def audit = Master::Fix::DesignAudit

  def tree
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "MASTER", "lib"))
      yield root, File.join(root, "MASTER", "lib")
    end
  end

  def write(path, text = "# x\n")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  SHARED_BODY = "def one = 1\ndef two = 2\ndef three = 3\ndef four = 4\n"

  def test_two_files_of_one_name_with_the_same_methods_are_one_idea_written_twice
    tree do |root, lib|
      write(File.join(lib, "a", "proof.rb"), SHARED_BODY)
      write(File.join(lib, "b", "proof.rb"), SHARED_BODY)

      rows = audit.duplicated_modules(lib, repo_root: root)

      assert_equal 1, rows.size
      assert_includes rows.first.message, "share 4 method names"
    end
  end

  def test_two_files_of_one_name_doing_different_things_are_left_alone
    tree do |root, lib|
      write(File.join(lib, "a", "proof.rb"), SHARED_BODY)
      write(File.join(lib, "b", "proof.rb"), "def alpha = 1\ndef beta = 2\ndef gamma = 3\ndef one = 1\n")

      assert_empty audit.duplicated_modules(lib, repo_root: root)
    end
  end

  def test_a_conventional_name_is_never_a_duplicate
    tree do |root, lib|
      write(File.join(lib, "a", "version.rb"), SHARED_BODY)
      write(File.join(lib, "b", "version.rb"), SHARED_BODY)

      assert_empty audit.duplicated_modules(lib, repo_root: root)
    end
  end

  def test_a_directory_with_one_file_beside_its_parent_module_is_lone
    tree do |_root, lib|
      write(File.join(lib, "face", "law_field.rb"))
      write(File.join(lib, "face.rb"))
      write(File.join(lib, "voice", "a.rb"))
      write(File.join(lib, "voice", "b.rb"))
      write(File.join(lib, "voice.rb"))

      rows = audit.lone_directories(lib)

      assert_equal 1, rows.size
      assert_includes rows.first.message, "face/ holds only law_field.rb"
    end
  end

  def test_a_test_that_mostly_asserts_on_source_text_is_a_spelling_test
    tree do |root, _lib|
      checks = Array.new(6) { |i| "    assert_includes source, \"needle #{i}\"\n" }.join
      write(File.join(root, "MASTER", "test", "test_spelled.rb"),
            "def test_x\n  source = File.read(\"a.rb\")\n#{checks}end\n")

      rows = audit.spelling_tests(repo_root: root)

      assert_equal 1, rows.size
      assert_includes rows.first.message, "6 of 6 assertions"
    end
  end

  def test_a_test_that_runs_code_is_not_a_spelling_test
    tree do |root, _lib|
      body = "  source = File.read(\"a.rb\")\n  assert_includes source, \"one\"\n  assert_equal 3, Thing.call\n" \
             "  assert_equal 4, Thing.call(2)\n  assert_equal 5, Thing.call(3)\n"
      write(File.join(root, "MASTER", "test", "test_behaves.rb"), "def test_x\n#{body}end\n")

      assert_empty audit.spelling_tests(repo_root: root)
    end
  end

  def test_a_subprocess_inside_a_loop_is_reported_once_per_loop
    tree do |_root, lib|
      write(File.join(lib, "slow.rb"),
            "paths.each do |path|\n  Master::Io::Exec.capture3(\"rubocop\", path)\n" \
            "  Master::Io::Exec.capture3(\"reek\", path)\nend\nx = 1\n")

      rows = audit.spawn_in_loops(lib)

      assert_equal 1, rows.size
      assert_equal 1, rows.first.line
    end
  end

  def test_a_loop_without_a_subprocess_is_not_reported
    tree do |_root, lib|
      write(File.join(lib, "fast.rb"), "paths.each do |path|\n  puts path\nend\n")

      assert_empty audit.spawn_in_loops(lib)
    end
  end
end

require_relative "test_helper"
require_relative "../lib/design/authoring"

class DesignAuthoringTest < Minitest::Test
  Authoring = Master::Design::Authoring

  def test_frontend_source_under_rails_is_briefed
    path = "/repo/RAILS/brgen/app/views/posts/index.html.erb"
    text = Authoring.context(path:)

    assert_includes text, "DESIGN AUTHORING"
    assert_includes text, "purpose=read and participate in a post stream"
    assert_includes text, Master::Design::Typeface::HOUSE_RULE
    assert_includes text, "AVOID THE DEFAULTS"
    assert_includes text, "relative size, alignment and visual weight"
  end

  def test_recovered_creative_lenses_are_used_by_design_authoring
    text = Authoring.context(path: "/repo/RAILS/brgen/app/views/posts/index.html.erb")
    assert_includes text, "CREATIVE CRAFT"
    assert_includes text, "STRONG_CENTERS"
    assert_includes text, "Whitespace groups related things"
    assert_includes text, "macro, meso and micro relationships"
    assert_includes text, "generative constraints"
    assert_includes text, "not a universal score"
    music = Master::Design::VisualLanguage.creative_context("music")
    assert_includes music, "Silence, rests"
    assert_includes music, "listening remains human"
    refute_includes music, "Whitespace groups related things"
    assert_equal "", Master::Design::VisualLanguage.creative_context("unknown")
  end

  def test_creative_medium_routes_explicit_craft_requests
    language = Master::Design::VisualLanguage
    assert_equal "architecture", language.creative_medium("what makes good architecture good?")
    assert_equal "software", language.creative_medium("improve the software architecture")
    assert_equal "music", language.creative_medium("compose a beautiful beat")
    assert_equal "photography", language.creative_medium("improve the portrait")
    assert_equal "writing", language.creative_medium("write a letter")
    assert_nil language.creative_medium("my music player crashed")
  end

  def test_multidisciplinary_craft_preserves_distinct_lenses
    language = Master::Design::VisualLanguage
    assert_equal %w[music cinema], language.creative_media("compose music for a film")
    assert_equal %w[software design], language.creative_media("refine the Ruby interface")
    assert_empty language.creative_media("my music player crashed")
    context = language.creative_context(%w[music cinema music])
    assert_includes context, "music: Silence, rests"
    assert_includes context, "cinema: Let an action"
    assert_equal 1, context.scan("music: Silence, rests").size
  end

  def test_bsdports_is_not_held_to_the_house_typeface
    text = Authoring.context(path: "/repo/RAILS/bsdports/app/assets/stylesheets/application.scss")

    assert_includes text, "DESIGN AUTHORING"
    refute_includes text, Master::Design::Typeface::HOUSE_RULE
  end

  def test_ruby_generated_and_vendored_files_get_nothing
    assert_equal "", Authoring.context(path: "/repo/RAILS/brgen/app/models/post.rb")
    assert_equal "", Authoring.context(path: "/repo/MASTER/web/public/face.runtime.js")
    assert_equal "", Authoring.context(path: "/repo/RAILS/brgen/vendor/x.css")
    assert_equal "", Authoring.context(path: "/repo/MASTER/lib/x.js")
  end

  def test_route_follows_the_view_path
    assert_equal "/posts", Authoring.route_for(%w[brgen app views posts index.html.erb])
    assert_equal "/items/new", Authoring.route_for(%w[brgen app views items new.html.erb])
    assert_equal "/", Authoring.route_for(%w[brgen app assets a.css])
  end
end

class DesignMissionTest < Minitest::Test
  Authoring = Master::Design::Authoring

  def test_goal_naming_an_app_gets_its_direction
    text = Authoring.mission_context(goal: "complete the amber wardrobe stylesheet")

    assert_includes text, "DESIGN MISSION"
    assert_includes text, "aesthetic_direction=editorial_wardrobe"
    assert_includes text, Master::Design::Typeface::HOUSE_RULE
  end

  def test_goal_without_an_app_keeps_the_app_independent_half
    text = Authoring.mission_context(goal: "design a landing page")

    assert_includes text, "DESIGN MISSION"
    refute_includes text, "aesthetic_direction="
    assert_includes text, "AVOID THE DEFAULTS"
  end

  def test_frontend_nouns_route_to_the_design_intent
    router = Master::CLI::IntentRouter.new

    assert_equal :design_frontend, router.classify("rewrite the brgen landing stylesheet")
    assert_equal :medium, router.risk(:design_frontend)
    assert_equal :run_ui_review, router.classify("review the design look")
  end

  def notes(memory) = memory.context.map(&:text).join("\n")

  def test_bridge_seeds_the_brief_only_for_design_missions
    memory = Master::Core::Memory.new(risk: :low)
    record = { "operator" => { "intent" => "design_frontend" } }
    Master::CLI::CoreBridge.seed_design_brief(memory, "fix the brgen homepage css", record, root: Master::ROOT)

    assert_match(/design: DESIGN MISSION/, notes(memory))

    other = Master::Core::Memory.new(risk: :low)
    Master::CLI::CoreBridge.seed_design_brief(other, "x", { "operator" => { "intent" => "unknown" } }, root: Master::ROOT)

    refute_match(/DESIGN MISSION/, notes(other))
  end
end

require_relative "test_helper"
require "set"
require_relative "../tools/audit/design_baseline"

class TestDesignBaselineCatalogue < Minitest::Test
  Rule = Struct.new(:id)

  def test_stale_rule_ceiling_cannot_silently_lower_the_measured_baseline
    error = assert_raises(ArgumentError) do
      Operator::DesignBaseline.validate_rule_ceilings!(
        [Rule.new("KNOWN_RULE")],
        expected: Set["KNOWN_RULE", "REMOVED_RULE"],
      )
    end

    assert_match(/REMOVED_RULE/, error.message)
    assert_match(/missing or non-deterministic Laws/, error.message)
  end

  def test_known_deterministic_rule_ceilings_are_accepted
    assert Operator::DesignBaseline.validate_rule_ceilings!(
      [Rule.new("KNOWN_RULE")],
      expected: Set["KNOWN_RULE"],
    )
  end
end

require_relative "test_helper"

class DesignDirectionTest < Minitest::Test
  Surface = Struct.new(:id, :app, :label, :host, :path)

  def test_vertical_direction_uses_product_before_shared_host
    language = Master::Design::VisualLanguage
    {
      ["brgen", "marketplace.brgen.no", "/takeaway/restaurants"] => :transactional_food,
      ["brgen", "marketplace.brgen.no", "/food"] => :transactional_food,
      ["brgen", "dating.brgen.no", "/"] => :intimate_social,
      ["brgen", "radio.brgen.no", "/sets"] => :media_station,
      ["brgen", "tv.brgen.no", "/"] => :media_station,
      ["brgen", "maps.brgen.no", "/"] => :cartographic,
      ["amber", "amberapp.art", "/messages"] => :editorial_wardrobe,
      ["master", "ai.brgen.no", "/"] => :conversational,
      ["mrdamascy", "mrd.brgen.no", "/orders"] => :transactional_food,
      ["bsdports", "bsdports.org", "/ports"] => :utilitarian_terminal,
    }.each do |(app, host, path), direction|
      surface = Surface.new("#{app}#{path}", app, path, host, path)
      assert_equal direction, language.direction_for(surface), surface.id
      assert_includes language.surface_anatomy(surface), "interaction_patterns="
    end
  end

  def test_authority_is_first
    contract = Master::Design::Authority.contract
    assert_equal 1, contract.fetch("priority")
    assert_equal %w[purpose agency clarity hierarchy trust consistency craft delight],
                 Master::Design::Authority::ORDER
  end

  def test_all_schools_inherit_authority
    Master::Design::Authority.schools.each do |name, spec|
      assert_equal true, spec.fetch("inherits_authoritative_design"), "#{name} bypasses authority"
    end
  end

  def test_marketplace_pairing_is_shipped_and_single_family
    key, spec = Master::Design::Pairing.for(school: :commerce_editorial, purpose: "marketplace sale")
    assert_equal "marketplace_sale", key
    assert_equal "house_sans", spec.fetch("display")
    assert Master::Design::Pairing.deployable?(spec)
  end

  def test_marketplace_composition_preserves_transaction_priority
    _, spec = Master::Design::Composition.for(school: :commerce_editorial, purpose: "marketplace sale")
    assert_equal %w[product price headline proof action], spec.fetch("focal_order")
  end

  def test_measure_accessor_delegates_to_thresholds
    assert_equal Master::Design::Thresholds.measure_ideal_ch,
                 Master::Design.measure_ideal_ch
  end

  def test_every_declared_editorial_profile_is_selectable_by_description
    profiles = Master::Design::PlatformProfiles

    assert_equal :medium, profiles.choose("Medium long-form reading")
    assert_equal :new_yorker, profiles.choose("New Yorker editorial magazine")
    assert_equal :x, profiles.choose("X real-time timeline")
  end
end

require_relative "test_helper"
require "fileutils"
require "tmpdir"
require_relative "../lib/fix/design_loop"

class TestDesignLoop < Minitest::Test
  Surface = Struct.new(:id, :app, :label, :host, :path)
  EDIT = Master::Fix::DesignEdit
  LOOP = Master::Fix::DesignLoop
  SCALE = [0.0, 4.0, 8.0, 16.0].freeze
  FILLER = (1..9).map { |n| ".filler-#{n}" }.freeze

  def with_sheet(css = ".card {\n  padding: 4px;\n  color: #111;\n}\n")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "app.scss")
      File.write(path, css)
      yield path
    end
  end

  def reply(path, find:, replace:, why: "more room")
    JSON.generate("file" => path, "find" => find, "replace" => replace, "why" => why)
  end

  def parse(path, find:, replace:, **rules)
    EDIT.parse(reply(path, find:, replace:), allowed: [path], rules: EDIT::Rules.new(guard: nil, scale: nil, **rules))
  end

  def refused(edit) = assert_raises(EDIT::Refused) { edit.check! }.message

  # The commit-msg hook holds every commit to MASTER's shape. The loop wrote
  # "design: <the whole rationale>." with no trailer, so all six edits a run
  # kept on 2026-11-04 were refused and sat uncommitted.
  def test_a_kept_edit_commits_in_masters_commit_shape
    with_sheet do |path|
      why = "A 32px gap under the sign-in heading separates it from the lead paragraph."
      edit = EDIT.parse(reply(path, find: "padding: 4px;", replace: "padding: 8px;", why:),
                        allowed: [path], rules: EDIT::Rules.new(guard: nil, scale: nil))
      loop_run = LOOP.new(plan: LOOP::Plan.new(surfaces: [], root: Dir.pwd, rounds: 1, candidates: 1), world: nil)
      surface = Surface.new("amber/sessions_new/desktop", "amber")
      loop_run.instance_variable_set(:@target, { surface:, score: 52.8 })

      message = loop_run.send(:commit_message, edit, 55.6)

      assert_empty Master::Ground::CommitFormat.problems(message, root: File.expand_path("..", __dir__))
      assert message.start_with?("Refine the amber sessions new layout at desktop width\n\n")
      assert_includes message, "52.8 -> 55.6"
    end
  end

  def test_design_edit_uses_the_shared_atomic_writer
    with_sheet do |path|
      edit = parse(path, find: "padding: 4px;", replace: "padding: 8px;", scale: SCALE)
      calls = []
      writer = Master::Io::AtomicWrite.method(:write_atomic)
      instrumented = lambda do |target, content, **options|
        calls << [target, content, options]
        writer.call(target, content, **options)
      end

      Master::Io::AtomicWrite.stub(:write_atomic, instrumented) do
        edit.apply!
      end

      assert_equal 1, calls.length
      assert_equal path, calls.first.first
      assert_includes calls.first[1], "padding: 8px;"
      assert_equal File.read(path), calls.first[1]
      assert_empty Dir.glob(File.join(File.dirname(path), ".master_atomic_*"))
    end
  end

  def test_an_edit_to_spacing_is_applied_and_undone
    with_sheet do |path|
      edit = parse(path, find: "padding: 4px;", replace: "padding: 16px;")
      original = edit.apply!

      assert_includes File.read(path), "padding: 16px;"
      edit.restore(original)
      assert_includes File.read(path), "padding: 4px;"
    end
  end

  def test_rendered_values_are_refused_whatever_the_model_asks
    with_sheet do |path|
      assert_match(/rendered value/, refused(parse(path, find: "color: #111;", replace: "color: #f00;")))
      swapped = parse(path, find: "padding: 4px;", replace: "padding: 4px;\n  background: blue;")

      assert_match(/rendered value/, refused(swapped))
    end
  end

  def test_existing_decorative_frame_can_be_neutralised_but_not_focus_or_brand
    with_sheet(".card { border: 1px solid red; box-shadow: 0 0 4px black; outline: 2px solid blue; color: red; }") do |path|
      assert parse(path, find: "border: 1px solid red;", replace: "border: 0;").check!
      assert parse(path, find: "box-shadow: 0 0 4px black;", replace: "box-shadow: none;").check!
      assert_match(/colour/, refused(parse(path, find: "outline: 2px solid blue;", replace: "outline: none;")))
      assert_match(/rendered value/, refused(parse(path, find: "color: red;", replace: "")))
    end
  end

  def test_font_shadow_important_repeats_and_missing_text_are_refused
    with_sheet(".a {\n  gap: 4px;\n  gap: 4px;\n}\n") do |path|
      assert_match(/occurs 2 times/, refused(parse(path, find: "gap: 4px;", replace: "gap: 8px;")))
      assert_match(/occurs 0 times/, refused(parse(path, find: "nothing here", replace: "x")))
      forbidden = [".a {\n  font-size: 20px;", ".a {\n  box-shadow: 0 0 4px #000;", ".a {\n  margin: 0 !important;"]
      forbidden.each do |replace|
        assert_raises(EDIT::Refused) { parse(path, find: ".a {", replace:).apply! }
      end
    end
  end

  def test_a_rule_rewritten_onto_one_line_may_keep_its_colour
    css = ".empty {\n  color: var(--text-secondary);\n  padding: 32px 12px;\n}\n"
    with_sheet(css) do |path|
      replace = ".empty { color: var(--text-secondary); padding: 48px 16px; max-inline-size: 66ch; }"
      parse(path, find: css.strip, replace:).apply!

      assert_includes File.read(path), "padding: 48px 16px"
    end
  end

  def test_changing_the_colour_inside_a_one_line_rule_is_refused
    css = ".empty { color: red; padding: 4px; }\n"
    with_sheet(css) do |path|
      edit = parse(path, find: css.strip, replace: ".empty { color: blue; padding: 4px; }")

      assert_raises(EDIT::Refused) { edit.apply! }
    end
  end

  # RENDERED_VALUES in laws.yml names layout constants: the token files stay the operator's.
  def test_token_files_are_never_edited
    Dir.mktmpdir do |dir|
      path = File.join(dir, "_tokens.scss")
      File.write(path, ":root {\n  --space-3: 12px;\n}\n")

      assert_match(/operator-owned/, refused(parse(path, find: "--space-3: 12px;", replace: "--space-3: 16px;")))
    end
  end

  def test_spacing_must_sit_on_the_declared_scale
    with_sheet do |path|
      off = parse(path, find: "padding: 4px;", replace: "padding: 13px;", scale: SCALE)
      on = parse(path, find: "padding: 4px;", replace: "padding: 1rem;", scale: SCALE)

      assert_match(/off the declared spacing scale/, refused(off))
      assert on.check!
    end
  end

  def test_the_mechanical_laws_can_refuse_the_file_as_it_would_be_written
    with_sheet do |path|
      seen = nil
      guard = ->(file, text) { (seen = [file, text]) && "NO_DECORATIVE_FX: gradient" }
      rules = EDIT::Rules.new(guard:, scale: nil)
      edit = EDIT.parse(reply(path, find: "padding: 4px;", replace: "padding: 16px;"), allowed: [path], rules:)

      assert_match(/the laws refuse it: NO_DECORATIVE_FX/, refused(edit))
      assert_includes seen.last, "padding: 16px;"
      assert_includes File.read(path), "padding: 4px;"
    end
  end

  # `main > h1 ~ *` once reached every page of an app and was kept because few pages were re-measured.
  def test_a_new_rule_must_name_a_class_or_id
    with_sheet do |path|
      universal = parse(path, find: "padding: 4px;", replace: "padding: 4px;\n}\nmain > h1 ~ * {\n  margin: 8px;")
      element_only = parse(path, find: "padding: 4px;", replace: "padding: 4px;\n}\nh2 {\n  margin: 8px;")
      named = parse(path, find: "padding: 4px;", replace: "padding: 4px;\n}\n.card .title {\n  margin: 8px;")

      assert_match(/across the whole app/, refused(universal))
      assert_match(/across the whole app/, refused(element_only))
      assert named.check!
    end
  end

  def test_empty_and_ambiguous_file_names_are_refused
    with_sheet do |path|
      other = File.join(File.dirname(path), "other", File.basename(path))
      ["", File.basename(path)].each do |name|
        edit = EDIT.parse(reply(name, find: "padding: 4px;", replace: "padding: 16px;"), allowed: [path, other])
        assert_match(/not one of the offered/, refused(edit))
      end
      edit = EDIT.parse(reply(path, find: "padding: 4px;", replace: "padding: 16px;"), allowed: [path, other])
      assert_equal path, edit.file
    end
  end

  def test_focus_outline_cannot_be_deleted_or_zeroed
    with_sheet(".card { outline: 2px solid blue; outline-width: 2px; }") do |path|
      assert_match(/focus outline/, refused(parse(path, find: "outline: 2px solid blue;", replace: "")))
      assert_match(/focus outline/, refused(parse(path, find: "outline-width: 2px;", replace: "outline-width: 0;")))
    end
  end

  def test_a_file_that_was_not_offered_is_refused
    with_sheet do |path|
      edit = EDIT.parse(reply("/etc/passwd", find: "a", replace: "b"), allowed: [path])

      assert_match(/not one of the offered/, refused(edit))
    end
  end

  # A fake world: padding 4px scores 40 on the home surface and 16px scores 60; others stay 50.
  def fake_score(surface, wide:, other_drop:, flat:)
    return(wide && !flat ? 60.0 : 40.0) if surface.id == "brgen/home"

    wide ? 50.0 - other_drop : 50.0
  end

  def screenshot(path, surface)
    shot = File.join(File.dirname(path), "#{surface.id.tr('/', '_')}.png")
    File.write(shot, "png")
    shot
  end

  NO_DIFFERENCE = '{"better":"same","why":"no difference"}'

  # options: other_drop (score lost elsewhere), flat (score never moves), vision (the check's reply),
  # classes (what is on the page), built (collects the apps whose CSS was rebuilt), seen (collects
  # the surface ids of each measurement), prompts (collects what the model was asked).
  def world_for(path, committed:, **options)
    drop = options.fetch(:other_drop, 0)
    flat = options.fetch(:flat, false)
    vision = options.fetch(:vision, flat ? NO_DIFFERENCE : '{"better":"B","why":"clearer grouping"}')
    built = options.fetch(:built, [])
    seen = options.fetch(:seen, [])
    prompts = options.fetch(:prompts, [])
    on_build = options.fetch(:on_build, ->(_app) {})
    elements = options.fetch(:classes, FILLER + [".card"]).map do |key|
      { "key" => "body>main>#{key}", "rect" => { "w" => 300, "h" => 30 } }
    end
    measure = lambda do |surfaces|
      seen << surfaces.map(&:id)
      wide = File.read(path).include?("padding: 16px")
      surfaces.map do |surface|
        payload = { "score" => fake_score(surface, wide:, other_drop: drop, flat:),
                    "vw" => 390, "vh" => 844, "elements" => elements }
        [surface, payload, screenshot(path, surface)]
      end
    end
    edit = reply(path, find: "padding: 4px;", replace: "padding: 16px;")
    LOOP::World.new(
      measure:,
      ask: lambda do |prompt, images|
        prompts << prompt
        next edit unless prompt.include?("Two renders")
        next vision if images.first.to_s.end_with?(".before.png")

        verdict = JSON.parse(vision)
        verdict["better"] = { "A" => "B", "B" => "A" }.fetch(verdict["better"].to_s, verdict["better"])
        JSON.generate(verdict)
      end,
      build: ->(app) { built << app; on_build.call(app); true },
      commit_file: lambda do |file, message, transaction|
        transaction.delivery.begin!(head_before: "a" * 40, paths: transaction.enlisted_paths)
        transaction.delivery.record_commit!(head_after: "b" * 40)
        finalized = transaction.delivery.finalize!(head: "b" * 40)
        raise finalized.message unless finalized.ok?
        committed << [file, message]
        true
      end,
      sources_for: ->(_surface) { [path] }, guard: nil
    )
  end

  HOME_AND_FEED = [Surface.new("brgen/home", "brgen"), Surface.new("brgen/feed", "brgen")].freeze

  # world: what world_for takes, and surfaces (the surfaces the run measures).
  def loop_for(path, committed:, root: File.dirname(path), **world)
    surfaces = world.delete(:surfaces) || HOME_AND_FEED
    plan = LOOP::Plan.new(surfaces:, root:, rounds: 3, candidates: 1)
    LOOP.new(plan:, world: world_for(path, committed:, **world))
  end

  def stub_scoring(&block)
    store = Master::Fix::LayoutScoreStore
    result = Struct.new(:score, :subs)
    store.stub(:measure, ->(_root, payload) { result.new(payload["score"], { "alignment" => 0.5 }) }) do
      Master::Fix::VisualQualityChecks.stub(:measure, ->(_surface, _payload) { { "offenders" => {} } }, &block)
    end
  end

  def test_an_edit_that_raises_the_score_is_kept_and_committed
    with_sheet do |path|
      committed = []
      stub_scoring do
        rounds = loop_for(path, committed:).run

        assert_equal :kept, rounds.first.outcome
        assert_includes File.read(path), "padding: 16px;"
        assert_equal [path], committed.map(&:first)
        assert_match(/layout score 40\.0 -> 60\.0/, committed.first.last)
      end
    end
  end

  def test_score_gain_without_visual_improvement_is_not_kept
    with_sheet do |path|
      committed = []
      stub_scoring do
        rounds = loop_for(path, committed:, vision: NO_DIFFERENCE).run

        assert_empty rounds.select { |round| round.outcome == :kept }
        assert_empty committed
        assert_includes File.read(path), "padding: 4px;"
      end
    end
  end

  def test_design_prompt_does_not_treat_inapplicable_measures_as_defects
    plan = LOOP::Plan.new(surfaces: [], root: Dir.pwd, rounds: 1, candidates: 1)
    runner = LOOP.new(plan:, world: nil)
    runner.instance_variable_set(:@target, { payload: {} })
    result = Struct.new(:subs).new({ "measure" => nil, "edges" => 0.2, "grid" => 0.0, "scale" => 0.8, "density" => 0.9 })

    Master::Fix::LayoutScoreStore.stub(:measure, result) do
      assert_equal "grid 0.0, edges 0.2, scale 0.8", runner.send(:weakest_measures)
    end
  end

  def test_coordinated_candidate_is_committed_as_one_transaction
    with_sheet do |path|
      other = File.join(File.dirname(path), "second.scss")
      File.write(other, ".card { margin: 4px; }")
      committed = []
      world = world_for(path, committed:)
      ask = world.ask
      proposal = JSON.generate("why" => "unify composition", "edits" => [
        { "file" => path, "find" => "padding: 4px;", "replace" => "padding: 16px;" },
        { "file" => other, "find" => "margin: 4px;", "replace" => "margin: 8px;" }
      ])
      world = world.with(sources_for: ->(_) { [path, other] },
                         ask: ->(prompt, images) { prompt.include?("Two renders") ? ask.call(prompt, images) : proposal })
      plan = LOOP::Plan.new(surfaces: HOME_AND_FEED, root: File.dirname(path), rounds: 1, candidates: 1)
      stub_scoring do
        assert_equal :kept, LOOP.new(plan:, world:).run.first.outcome
      end
      assert_equal [path, other], committed.first.first
      assert_includes File.read(other), "margin: 8px;"
    end
  end

  def test_sparse_compositions_remain_eligible_for_design_review
    with_sheet do |path|
      committed = []
      stub_scoring do
        rounds = loop_for(path, committed:, classes: [".card"]).run
        assert_equal :kept, rounds.first.outcome
      end
      assert_equal [path], committed.map(&:first)
    end
  end

  def test_anchorless_surfaces_are_skipped
    with_sheet do |path|
      stub_scoring do
        assert_empty loop_for(path, committed: [], classes: []).run
      end
    end
  end

  def test_design_rounds_rotate_candidate_scales_even_with_one_candidate
    with_sheet do |path|
      prompts = []
      stub_scoring do
        loop_for(path, committed: [], vision: NO_DIFFERENCE, prompts:).run
      end

      requests = prompts.select { |prompt| prompt.include?("Make ONE edit") }
      assert requests.any? { |prompt| prompt.include?("Macro: strengthen") }
      assert requests.any? { |prompt| prompt.include?("Meso: refine") }
      assert requests.any? { |prompt| prompt.include?("Micro: refine") }
    end
  end

  def test_visual_preference_outranks_numerical_gain_between_candidates
    with_sheet do |path|
      world = world_for(path, committed: []).with(ask: ->(_prompt, _images) { '{"better":"B","why":"better proportion"}' })
      runner = LOOP.new(plan: LOOP::Plan.new(surfaces: [], root: File.dirname(path), rounds: 1, candidates: 2), world:)
      runner.define_singleton_method(:alternative_prompt) { "compare" }
      left = { gain: 20.0, capture: "a.png" }
      right = { gain: 1.0, capture: "b.png" }

      assert_equal right, runner.send(:prefer_candidate, left, right)
    end
  end

  def test_successful_design_candidate_cleans_up_its_transaction
    with_sheet do |path|
      committed = []
      root = File.dirname(path)
      stub_scoring do
        rounds = loop_for(path, committed:, root:).run

        assert_equal :kept, rounds.first.outcome
        transaction_root = File.join(root, Master::Fix::Transaction::ROOT_DIR)
        assert_empty Dir.children(transaction_root)
      end
    end
  end

  def test_interrupted_design_candidate_is_recovered_before_the_next_run
    Dir.mktmpdir do |root|
      path = File.join(root, "app.scss")
      original = ".card {\n  padding: 4px;\n  color: #111;\n}\n"
      File.write(path, original)
      transaction = Master::Fix::Transaction.new(
        root:, paths: [path], id: "design-#{'a' * 20}"
      )
      transaction.begin!
      File.write(path, ".card {\n  padding: 16px;\n  color: #111;\n}\n")
      assert transaction.observe_paths!([path]).ok?
      transaction.close! # Simulate the process exiting while the candidate is still open.

      plan = LOOP::Plan.new(surfaces: [], root:, rounds: 1, candidates: 1)
      world = LOOP::World.new(
        measure: ->(_surfaces) { [] },
        ask: ->(_prompt, _images) { "" },
        build: nil,
        commit_file: ->(_file, _message, _transaction) { false },
        sources_for: ->(_surface) { [] },
        guard: nil
      )
      assert_empty LOOP.new(plan:, world:).run

      assert_equal original, File.read(path)
      refute Master::Fix::Transaction::Recovery.persisted?(root:, id: transaction.id)
    end
  end

  def test_interrupted_rails_recovery_fails_closed_without_a_css_builder
    Dir.mktmpdir do |root|
      path = File.join(root, "RAILS", "brgen", "app", "assets", "stylesheets", "app.scss")
      FileUtils.mkdir_p(File.dirname(path))
      original = ".card {\n  padding: 4px;\n}\n"
      File.write(path, original)
      transaction = Master::Fix::Transaction.new(
        root:, paths: [path], id: "design-#{'c' * 20}"
      )
      transaction.begin!
      File.write(path, ".card {\n  padding: 16px;\n}\n")
      assert transaction.observe_paths!([path]).ok?
      transaction.close!

      plan = LOOP::Plan.new(surfaces: [], root:, rounds: 1, candidates: 1)
      error = assert_raises(RuntimeError) { LOOP.new(plan:, world: nil).run }

      assert_match(/build capability is unavailable/, error.message)
      assert_equal original, File.read(path)
      refute Master::Fix::Transaction::Recovery.persisted?(root:, id: transaction.id)
    end
  end

  def test_interrupted_design_rollback_rebuilds_the_restored_apps_css
    Dir.mktmpdir do |root|
      path = File.join(root, "RAILS", "brgen", "app", "assets", "stylesheets", "app.scss")
      FileUtils.mkdir_p(File.dirname(path))
      original = ".card {\n  padding: 4px;\n}\n"
      File.write(path, original)
      transaction = Master::Fix::Transaction.new(
        root:, paths: [path], id: "design-#{'b' * 20}"
      )
      transaction.begin!
      File.write(path, ".card {\n  padding: 16px;\n}\n")
      assert transaction.observe_paths!([path]).ok?
      transaction.close!

      built = []
      world = LOOP::World.new(
        measure: ->(_surfaces) { [] },
        ask: ->(_prompt, _images) { "" },
        build: ->(app) { built << app; true },
        commit_file: ->(_file, _message, _transaction) { false },
        sources_for: ->(_surface) { [] },
        guard: nil
      )
      plan = LOOP::Plan.new(surfaces: [], root:, rounds: 1, candidates: 1)
      assert_empty LOOP.new(plan:, world:).run

      assert_equal original, File.read(path)
      assert_equal ["brgen"], built
      refute Master::Fix::Transaction::Recovery.persisted?(root:, id: transaction.id)
    end
  end

  def test_a_delivery_without_a_terminal_transaction_receipt_is_not_kept
    with_sheet do |path|
      root = File.dirname(path)
      world = world_for(path, committed: []).with(
        commit_file: lambda do |_file, _message, transaction|
          transaction.delivery.begin!(head_before: "a" * 40, paths: transaction.enlisted_paths)
          transaction.delivery.record_commit!(head_after: "b" * 40)
          true
        end
      )
      plan = LOOP::Plan.new(surfaces: HOME_AND_FEED, root:, rounds: 1, candidates: 1)

      stub_scoring do
        rounds = LOOP.new(plan:, world:).run
        assert_equal :delivery_failed, rounds.first.outcome
        assert_includes File.read(path), "padding: 16px;"
        id = Dir.children(File.join(root, Master::Fix::Transaction::ROOT_DIR)).find { |name| name.start_with?("design-") }
        refute_nil id
        manifest = File.join(root, Master::Fix::Transaction::ROOT_DIR, id, Master::Fix::Transaction::MANIFEST)
        assert_equal "delivering", JSON.parse(File.read(manifest)).fetch("state")
      end
    end
  end

  def test_candidate_is_not_committed_when_source_changes_after_its_measurement
    with_sheet do |path|
      committed = []
      builds = 0
      on_build = lambda do |_app|
        builds += 1
        File.write(path, ".card {\n  padding: 4px;\n  color: #111;\n}\n/* another writer */\n") if builds == 2
      end
      stub_scoring do
        rounds = loop_for(path, committed:, on_build:).run

        assert_equal :failed, rounds.first.outcome
        assert_empty committed
        assert_includes File.read(path), "another writer"
        refute_includes File.read(path), "padding: 16px;"
      end
    end
  end

  def test_final_render_verification_can_refuse_a_previously_good_candidate
    with_sheet do |path|
      committed = []
      calls = 0
      stub_scoring do
        world = world_for(path, committed:)
        original = world.measure
        measure = lambda do |surfaces|
          calls += 1
          rows = original.call(surfaces)
          next rows unless calls == 5

          rows.map do |surface, payload, shot|
            surface.id == "brgen/home" ? [surface, payload.merge("score" => 30.0), shot] : [surface, payload, shot]
          end
        end
        plan = LOOP::Plan.new(surfaces: HOME_AND_FEED, root: File.dirname(path), rounds: 1, candidates: 1)
        rounds = LOOP.new(plan:, world: world.with(measure:)).run

        assert_equal :failed, rounds.first.outcome
        assert_empty committed
        assert_includes File.read(path), "padding: 4px;"
      end
    end
  end

  def test_a_refused_commit_restores_the_candidate_and_is_not_reported_as_kept
    with_sheet do |path|
      stub_scoring do
        world = world_for(path, committed: []).with(
          commit_file: ->(_file, _message, _transaction) { false }
        )
        plan = LOOP::Plan.new(surfaces: HOME_AND_FEED, root: File.dirname(path), rounds: 1, candidates: 1)
        rounds = LOOP.new(plan:, world:).run

        assert_equal :failed, rounds.first.outcome
        assert_includes File.read(path), "padding: 4px;"
        refute_includes File.read(path), "padding: 16px;"
      end
    end
  end

  def test_missing_guard_render_cannot_prove_an_improvement
    with_sheet do |path|
      committed = []
      stub_scoring do
        world = world_for(path, committed:)
        measure = world.measure
        calls = 0
        partial = lambda do |surfaces|
          calls += 1
          rows = measure.call(surfaces)
          calls >= 4 ? rows.reject { |surface, _, _| surface.id == "brgen/feed" } : rows
        end
        plan = LOOP::Plan.new(surfaces: HOME_AND_FEED, root: File.dirname(path), rounds: 1, candidates: 1)
        rounds = LOOP.new(plan:, world: world.with(measure: partial)).run
        assert_empty rounds.select { |round| round.outcome == :kept }
        assert_empty committed
        assert_includes File.read(path), "padding: 4px;"
      end
    end
  end

  def test_failed_navigation_cannot_seed_design_baseline
    with_sheet do |path|
      committed = []
      world = world_for(path, committed:)
      measure = ->(surfaces) { world.measure.call(surfaces).map { |s, p, shot| [s, p.merge("status" => 503), shot] } }
      plan = LOOP::Plan.new(surfaces: HOME_AND_FEED, root: File.dirname(path), rounds: 1, candidates: 1)

      error = assert_raises(RuntimeError) { LOOP.new(plan:, world: world.with(measure:)).run }
      assert_match(/baseline incomplete/, error.message)
      assert_empty committed
    end
  end

  def test_missing_noise_capture_refuses_to_invent_a_baseline
    with_sheet do |path|
      committed = []
      stub_scoring do
        world = world_for(path, committed:)
        measure = world.measure
        calls = 0
        missing = lambda do |surfaces|
          calls += 1
          calls == 3 ? [] : measure.call(surfaces)
        end
        plan = LOOP::Plan.new(surfaces: HOME_AND_FEED, root: File.dirname(path), rounds: 1, candidates: 1)
        rounds = LOOP.new(plan:, world: world.with(measure: missing)).run
        assert_equal :none, rounds.first.outcome
        assert_empty committed
      end
    end
  end

  def test_an_edit_that_hurts_another_surface_is_undone_and_not_committed
    with_sheet do |path|
      committed = []
      stub_scoring do
        rounds = loop_for(path, committed:, other_drop: 5).run

        assert_empty rounds.select { |round| round.outcome == :kept }
        assert_includes File.read(path), "padding: 4px;"
        assert_empty committed
      end
    end
  end
  # The score can sit flat while a person sees a better page, so a vision check decides then.
  def test_a_flat_score_is_kept_when_the_vision_check_says_the_new_render_is_better
    with_sheet do |path|
      committed = []
      stub_scoring do
        rounds = loop_for(path, committed:, flat: true, vision: '{"better":"B","why":"more room"}').run

        assert_equal :kept, rounds.first.outcome
        assert_equal [path], committed.map(&:first)
      end
    end
  end

  def test_a_flat_score_is_undone_when_the_vision_check_cannot_tell_the_renders_apart
    with_sheet do |path|
      committed = []
      stub_scoring do
        rounds = loop_for(path, committed:, flat: true).run

        assert_empty rounds.select { |round| round.outcome == :kept }
        assert_includes File.read(path), "padding: 4px;"
        assert_empty committed
      end
    end
  end
  # A rule that matches nothing on the page changes nothing either judge can see.
  def test_an_edit_to_a_selector_that_is_not_on_the_page_is_refused_without_a_render
    with_sheet do |path|
      committed = []
      stub_scoring do
        rounds = loop_for(path, committed:, classes: FILLER).run

        assert_empty rounds.select { |round| round.outcome == :kept }
        assert_includes File.read(path), "padding: 4px;"
        assert_empty committed
      end
    end
  end

  # A second capture of the target that differs by 15 means a gain of 20 is within the noise.
  def test_a_gain_smaller_than_twice_the_measured_noise_is_not_kept
    with_sheet do |path|
      committed = []
      stub_scoring do
        world = world_for(path, committed:, vision: NO_DIFFERENCE)
        calls = 0
        inner = world.measure
        noisy = lambda do |surfaces|
          calls += 1
          rows = inner.call(surfaces)
          calls == 3 ? rows.map { |s, payload, shot| [s, payload.merge("score" => payload["score"] + 15), shot] } : rows
        end
        plan = LOOP::Plan.new(surfaces: [Surface.new("brgen/home", "brgen")], root: File.dirname(path), rounds: 1, candidates: 1)
        rounds = LOOP.new(plan:, world: world.with(measure: noisy)).run

        assert_empty rounds.select { |round| round.outcome == :kept }
        assert_empty committed
      end
    end
  end

  def test_the_selector_of_the_rule_an_edit_sits_in_is_read_from_the_file
    with_sheet(".a, .b > .c { gap: 4px; }\n.d {\n  padding: 4px;\n}\n") do |path|
      assert_equal %w[.d], parse(path, find: "padding: 4px;", replace: "padding: 8px;").selector_tokens
      assert_equal %w[.a .b .c], parse(path, find: "gap: 4px;", replace: "gap: 8px;").selector_tokens
    end
  end

  # A comment above a rule is not its selector: "see _tokens.scss and README.md"
  # read as the classes .scss and .md, and the edit was refused as not on the page.
  def test_a_comment_above_the_rule_is_not_read_as_its_selector
    sheet = ".x { gap: 4px; }\n// keep in step with _tokens.scss and README.md\n/* v1.2 */\n" \
            ".look-title {\n  margin: 0;\n}\n"
    with_sheet(sheet) do |path|
      assert_equal %w[.look-title], parse(path, find: "margin: 0;", replace: "margin: 4px;").selector_tokens
    end
  end

  # Font size may move in either direction on the declared readable scale.
  def test_a_font_size_takes_only_a_declared_readable_step
    steps = [16.0, 20.0, 24.0]
    with_sheet(".a {\n  gap: 8px;\n}\n") do |path|
      add = ->(size, **rules) { parse(path, find: "gap: 8px;", replace: "gap: 8px;\n  font-size: #{size};", **rules) }

      assert add.("20px", type_scale: steps).check!
      assert add.("1.25rem", type_scale: steps).check!
      assert_match(/not a declared text size/, refused(add.("18px", type_scale: steps)))
      assert_match(/not a declared text size/, refused(add.("clamp(1rem, 2vw, 2rem)", type_scale: steps)))
      assert_match(/not a declared text size/, refused(add.("20px")))
    end
    with_sheet(".a {\n  font-size: 24px;\n}\n") do |path|
      shrunk = parse(path, find: "font-size: 24px;", replace: "font-size: 16px;", type_scale: steps)

      assert shrunk.check!
    end
  end

  def test_alternatives_to_the_same_rule_have_distinct_keys
    with_sheet do |path|
      first = parse(path, find: "padding: 4px;", replace: "padding: 8px;")
      second = parse(path, find: "padding: 4px;", replace: "padding: 16px;")

      refute_equal first.key, second.key
    end
  end

  def test_the_rest_of_the_font_stays_with_the_operator
    with_sheet(".a {\n  gap: 8px;\n}\n") do |path|
      ["font-weight: 700;", "font-family: serif;", "font: 20px/1.2 sans-serif;", "font-size-adjust: 0.5;"].each do |declaration|
        edit = parse(path, find: "gap: 8px;", replace: "gap: 8px;\n  #{declaration}", type_scale: [20.0])

        assert_match(/rendered value/, refused(edit))
      end
    end
  end

  def with_shared_sheet
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "RAILS", "__shared"))
      path = File.join(dir, "RAILS", "__shared", "app.scss")
      File.write(path, ".card {\n  padding: 4px;\n  color: #111;\n}\n")
      yield path, dir
    end
  end

  # A shared stylesheet reaches every app, so a run that measures one app cannot judge an edit to it.
  def test_a_shared_stylesheet_is_refused_when_the_run_measures_one_app
    with_shared_sheet do |path, root|
      committed = []
      stub_scoring do
        rounds = loop_for(path, committed:, root:).run

        assert_empty rounds.select { |round| round.outcome == :kept }
        assert_includes File.read(path), "padding: 4px;"
        assert_empty committed
      end
    end
  end

  def test_a_shared_stylesheet_edit_is_rebuilt_for_every_measured_app
    with_shared_sheet do |path, root|
      committed = []
      built = []
      surfaces = [Surface.new("brgen/home", "brgen"), Surface.new("amber/home", "amber")]
      stub_scoring do
        rounds = loop_for(path, committed:, root:, surfaces:, built:).run

        assert_equal :kept, rounds.first.outcome
        assert_equal %w[amber brgen], built.uniq.sort
      end
    end
  end

  def test_every_measured_app_is_guarded_however_many_surfaces_another_app_has
    with_sheet do |path|
      committed = []
      seen = []
      surfaces = %w[home a b c d e f].map { |name| Surface.new("brgen/#{name}", "brgen") } + [Surface.new("amber/home", "amber")]
      stub_scoring do
        loop_for(path, committed:, surfaces:, seen:).run

        assert_equal surfaces.map(&:id).sort, seen[1].sort
      end
    end
  end
  # The loop holds a surface to the direction the /fix critic and fixer already use, not a second copy.
  def test_the_edit_request_carries_the_design_layer_brief_and_the_house_typeface_rule
    with_sheet do |path|
      prompts = []
      surfaces = [Surface.new("amber/wardrobe", "amber", "wardrobe", nil, "/wardrobe"), Surface.new("amber/feed", "amber", "feed", nil, "/feed")]
      stub_scoring do
        loop_for(path, committed: [], surfaces:, prompts:).run
      end
      request = prompts.find { |text| text.include?("Make ONE edit") }

      assert_includes request, "Flat, brutalist, Swiss"
      assert_includes request, "aesthetic_direction=editorial_wardrobe"
      assert_includes request, Master::Design::Typeface::HOUSE_RULE
      assert_match(/font-size/, request)
    end
  end
end

require_relative "test_helper"
require_relative "../checks/support/design_quality"

class TestDesignQuality < Minitest::Test
  def element(x:, y:, w: 100, h: 44, font_size: 16, font_weight: 400, text: "text", is_control: false, is_image: false)
    Deploy::DesignQuality::Element.new(
      tag: is_control ? "button" : "p",
      role: is_control ? "button" : nil,
      text:,
      x:, y:, w:, h:,
      font_size:, font_weight:,
      color: "#ffffff",
      bg_color: "#000000",
      is_text: !text.empty?,
      is_control:,
      is_image:
    )
  end

  def test_hard_floor_rejects_small_controls
    vector = Deploy::DesignQuality.calculate(
      elements: [element(x: 0, y: 0, w: 40, h: 40, is_control: true)],
      viewport: { w: 390, h: 844 },
      dialect: :social,
    )

    refute vector.hard_ok?
    refute vector.tap_ok
  end

  def test_hard_floor_rejects_contrast_failure
    vector = Deploy::DesignQuality.calculate(
      elements: [element(x: 0, y: 0)],
      viewport: { w: 390, h: 844 },
      dialect: :social,
      contrast_ok: false,
    )

    refute vector.hard_ok?
    refute vector.contrast_ok
  end

  def test_soft_vector_is_bounded
    vector = Deploy::DesignQuality.calculate(
      elements: [element(x: 0, y: 0), element(x: 100, y: 27, font_size: 24, font_weight: 700)],
      viewport: { w: 390, h: 844 },
      dialect: :social,
    )

    vector.soft_axes.values.each do |value|
      assert_operator value, :>=, 0.0
      assert_operator value, :<=, 1.0
    end
    assert vector.contrast_ok
  end

  def test_regression_detects_soft_drop_but_not_within_epsilon
    before = Deploy::DesignQuality::Vector.new(
      rhythm: 1.0, hierarchy: 1.0, density: 1.0, alignment: 1.0, balance: 1.0,
      tap_ok: true, contrast_ok: true
    )
    after = before.dup
    after.rhythm = 0.90
    assert after.regresses?(before)

    after.rhythm = 0.98
    refute after.regresses?(before)
  end
end

require_relative "test_helper"
require_relative "../lib/operator/design_run"

class TestDesignRun < Minitest::Test
  RUN = Operator::DesignRun
  Surface = Struct.new(:id, :pixel_snapshot)
  Round = Struct.new(:outcome)

  def said(kept, surfaces)
    lines = []
    RUN.stub(:say, ->(text) { lines << text }) { RUN.baselines_note(kept, surfaces) }
    lines
  end

  # Baseline approval is the operator's, so a run that kept an edit names what to review first.
  def test_a_kept_edit_names_the_measured_surfaces_that_carry_an_approved_png
    surfaces = [Surface.new("amber/home/desktop", true), Surface.new("amber/feed/desktop", false)]
    lines = said([Round.new(:kept)], surfaces)

    assert_match(/differ on: amber\/home\/desktop\z/, lines.first)
    assert_match(/approve_visual_baselines\.rb --manifest/, lines.last)
  end

  def test_nothing_is_said_without_a_kept_edit_or_without_an_approved_png
    assert_empty said([], [Surface.new("amber/home/desktop", true)])
    assert_empty said([Round.new(:kept)], [Surface.new("amber/feed/desktop", false)])
  end

  def transaction(root, path, id:)
    Master::Fix::Transaction.new(root:, paths: [path], id:).tap(&:begin!)
  end

  def head(root)
    IO.popen(["git", "-C", root, "rev-parse", "HEAD"], &:read).strip
  end

  def git(root, *args) = system("git", "-C", root, *args, out: File::NULL, err: File::NULL)

  def write_all(root, files) = files.each { |rel, text| File.write(File.join(root, rel), text) }

  # A checkout whose MASTER declares data/laws.yml sacred, with laws.yml and app.css edited since its base commit.
  def edited_checkout(root)
    git(root, "init", "-q")
    git(root, "config", "user.email", "test@example.invalid")
    git(root, "config", "user.name", "test")

    FileUtils.mkdir_p(File.join(root, "MASTER", "data"))
    FileUtils.mkdir_p(File.join(root, "RAILS", "visual_contract"))
    File.write(File.join(root, "MASTER", "data", "soul.yml"), "absolute: {}\n")
    write_all(root, "RAILS/visual_contract/base.json" => "a: 1\n", "app.css" => "a {}\n")
    git(root, "add", ".")
    git(root, "commit", "-q", "-m", "base")

    write_all(root, "RAILS/visual_contract/base.json" => "a: 2\n", "app.css" => "b {}\n")
  end

  # Consent is settled once in GeometryProbe.with_browser, which this run opens
  # the browser through, so the loop carries no consent script of its own.
  def test_the_run_carries_no_consent_script_of_its_own
    refute RUN.const_defined?(:DECIDED_CONSENT), "consent lives in GeometryProbe, not here"
  end

  # A design run commits through the transaction receipt and private-index path.
  def test_commit_refuses_a_preserved_asset_and_delivers_an_ordinary_one
    Dir.mktmpdir do |root|
      edited_checkout(root)
      lines, ordinary = commit_preserved_then_ordinary(root)

      assert_match(/base\.json is a preserved project asset/, lines.first)
      assert_equal "design: css\nbase\n", IO.popen(["git", "-C", root, "log", "--format=%s"], &:read)
      refute ordinary.active?
    end
  end

  # Commits a preserved asset (refused, rolled back), then an ordinary file.
  def commit_preserved_then_ordinary(root)
    lines = []
    preserved_path = File.join(root, "RAILS", "visual_contract", "base.json")
    preserved = transaction(root, preserved_path, id: "design-#{'a' * 20}")
    ordinary_path = File.join(root, "app.css")
    ordinary = transaction(root, ordinary_path, id: "design-#{'b' * 20}")

    RUN.stub(:say, ->(text) { lines << text }) do
      refute RUN.commit(preserved_path, "design: contract", root:, transaction: preserved)
      assert preserved.rollback!.ok?
      assert RUN.commit(ordinary_path, "design: css", root:, transaction: ordinary)
    end

    [lines, ordinary]
  end

  def test_report_returns_failure_when_a_partial_run_has_delivery_errors
    Dir.mktmpdir do |root|
      edited_checkout(root)
      result = Struct.new(:outcome, :number, :surface, :why, :before, :after)
      results = [
        result.new(:kept, 1, "brgen/home", "more room", 40.0, 60.0),
        Round.new(:delivery_failed),
      ]
      lines = []
      status = RUN.stub(:say, ->(text) { lines << text }) do
        RUN.report(results, root:, before: head(root), surfaces: [])
      end

      assert_equal 1, status
      assert_match(/design run incomplete: delivery_failed/, lines.join("\n"))
      assert_match(/1 edit\(s\) kept in 2 round\(s\)/, lines.join("\n"))
    end
  end
end

require "fileutils"
require_relative "test_helper"
require "review/scan/law_tree"
require_relative "../lib/fix/scan/ast_fixer"

# One scale for the ratchet, the two scale Laws and their /fix repair. The
# property that matters is agreement: whatever EIGHT_PX_RHYTHM or
# LINE_HEIGHT_ON_SCALE reports, snap_to_design_scale clears, and what it leaves
# the Laws do not report again.
class TestDesignScale < Minitest::Test
  SCALE = Master::Design::Scale.new(Master.tokens.fetch("scale"))

  def test_off_scale_lengths_read_units_and_skip_computed_parts
    assert_equal %w[6px 10px], SCALE.off_scale_lengths("6px 10px")
    assert_empty SCALE.off_scale_lengths("1px 0 auto")
    assert_empty SCALE.off_scale_lengths("0.75rem -8px")
    assert_empty SCALE.off_scale_lengths("calc(var(--x) + 3px)")
  end

  def test_nearest_breaks_a_tie_toward_the_smaller_step
    assert_equal 48.0, SCALE.nearest(52)
    assert_equal 4.0, SCALE.nearest(6)
    assert_equal 8.0, SCALE.nearest(7)
  end

  def test_snap_keeps_the_unit_sign_and_hairline
    assert_equal "8px 12px", SCALE.snap("padding", "7px 11px")
    assert_equal "-8px", SCALE.snap("margin", "-7px")
    assert_equal "0.5rem", SCALE.snap("gap", "0.4rem")
    assert_nil SCALE.snap("margin", "1px 0")
    assert_nil SCALE.snap("padding", "calc(100% - 3px)")
    assert_nil SCALE.snap("width", "10px")
  end

  def test_snap_moves_an_off_scale_line_height_and_leaves_an_absolute_one
    assert_equal "1.4", SCALE.snap("line-height", "1.45")
    assert_nil SCALE.snap("line-height", "1.5")
    assert_nil SCALE.snap("line-height", "20px")
    assert_equal :absolute, SCALE.line_height_kind("20px")
  end

  def test_fix_clears_what_the_laws_report
    source = <<~SCSS
      .card {
        padding: 7px 11px;
        margin: -7px 0 1px;
        gap: 0.4rem;
        line-height: 1.45;
      }
    SCSS
    refute_empty findings(source)

    result = fix(source)
    content = result[:content]

    assert_includes result[:transforms], :design_scale
    snapped = ["padding: 8px 12px;", "margin: -8px 0 1px;", "gap: 0.5rem;", "line-height: 1.4;"]
    snapped.each { |want| assert_includes content, want }
    assert_empty findings(content)
  end

  def test_fix_leaves_comments_opt_outs_computed_values_and_tokens
    source = <<~SCSS
      /* padding: 10px; is the old value */
      // margin: 6px;
      .a {
        /* scale: ok */
        padding: 10px;
        margin: calc(var(--gutter) + 3px);
        --space-odd: 10px;
      }
    SCSS
    result = fix(source)

    assert_equal source, result[:content]
    refute_includes result[:transforms], :design_scale
  end

  def test_fix_is_idempotent
    once = fix(".b { padding: 10px; line-height: 1.3; }\n")[:content]

    assert_equal once, fix(once)[:content]
  end

  # A computed function spans its whole argument list. `max(16px, (100% - 720px)
  # / 2 + 16px)` is one part, so its 720px is the build's arithmetic, not a step;
  # a `[^()]*` body stopped at the inner paren and snapped 720px to 128px.
  def test_fix_leaves_lengths_nested_inside_a_computed_function
    source = "body { margin-inline: max(16px, (100% - 720px) / 2 + 16px); }\n"

    assert_equal source, fix(source)[:content]
    assert_nil SCALE.snap("margin-inline", "max(16px, (100% - 720px) / 2 + 16px)")
  end

  # The slot that hides a computed part held its index between NULs, and
  # BARE_LENGTH read the index as a length: with five or more computed parts the
  # off-scale index 5 snapped to 8 and the wrong part came back.
  def test_fix_keeps_every_part_when_many_computed_values_share_a_declaration
    value = "max(var(--a), env(t)) var(--b) max(var(--c), env(u)) var(--d) max(var(--e), env(v))"
    source = ".c { padding: #{value}; }\n"

    assert_equal source, fix(source)[:content]
    assert_nil SCALE.snap("padding", value)
  end

  # A computed part is untouched, but a bare length beside it still snaps.
  def test_fix_still_snaps_bare_lengths_beside_computed_parts
    assert_equal "8px var(--x) 12px", SCALE.snap("padding", "7px var(--x) 11px")
    assert_equal "max(16px, (100% - 720px)/2 + 16px) 4px",
                 SCALE.snap("padding", "max(16px, (100% - 720px)/2 + 16px) 6px")
  end

  private

  def findings(source)
    %i[EIGHT_PX_RHYTHM LINE_HEIGHT_ON_SCALE].flat_map do |id|
      Law.definitions.fetch(id).scan(source, file: "/repo/app/assets/stylesheets/_card.scss")
    end
  end

  def fix(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "app", "assets", "stylesheets", "_card.scss")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      result = Master::Fix::Scan::AstFixer.fix(path, content)
      { content: File.read(path), transforms: result.transforms }
    end
  end
end
