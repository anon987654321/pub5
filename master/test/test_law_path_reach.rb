# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"
require File.join(Master::ROOT, "law", "definition") unless defined?(::Law)
::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?

# a40d93e579 dropped 41 path scopes from the laws.yml catalogue and nothing
# read them anywhere else, so each of those Laws judged every file in the
# repository: COMMERCE_AMBER_DOES_NOT_OWN_BRGEN fired on brgen's own
# marketplace, CLI_ANALYZE_TARGET_ROUTING on every new YAML file. Each scope
# is now the Law.define `path`.
#
# For every one, the Law reaches a file inside its scope and not one outside
# it; a Law with a detector also flags its bad fixture written inside and
# stays silent on the same text written outside, selected the way Law.scan
# selects (applies?, then scan).
#
# PROSE_ACTIVE_VOICE and PROSE_OMIT_QUALIFIERS carried path_pattern ".", which matches every file:
# they are universal and not listed.
class TestLawPathReach < Minitest::Test
  VIEWS = "rails/brgen/app/views/posts/index.html.erb"
  PUBLIC_HTML = "rails/brgen/public/offline.html"
  RAILS_JS = "rails/brgen/app/javascript/controllers/swipe_controller.js"
  STUDIO_JS = "studio/dilla/web/player.js"
  RAILS_SCSS = "rails/brgen/app/assets/stylesheets/application.scss"
  STUDIO_CSS = "studio/dilla/web/player.css"

  MIGRATION = "rails/brgen/db/migrate/20261105000000_add_things.rb"
  MODEL = "rails/brgen/app/models/thing.rb"
  AMBER_ORDER = "rails/amber/app/models/order.rb"
  MARKETPLACE_ORDER = "rails/brgen_marketplace/app/models/order.rb"
  BPLANS_HTML = "BPLANS/ai3.html"

  # Law => [a file inside its scope, a file outside it].
  REACH = {
    BEM_IN_VIEWS: [VIEWS, PUBLIC_HTML],
    CAPABILITY_REDUCTION_IS_MONOTONIC: ["master/lib/core.rb", "master/lib/core_helpers.rb"],
    CLI_ANALYZE_TARGET_ROUTING: ["master/data/patterns.yml", "master/data/new_registry.yml"],
    CLI_FACE_DEDICATED_TTY: ["master/lib/cli/command_registry.rb", "master/lib/cli/web_server.rb"],
    CLI_PROMPT_COMPOSITION: ["master/lib/voice/renderer/prompt.rb", "master/lib/voice/speech.rb"],
    CLI_TREE_TARGET_RESOLUTION: ["master/lib/cli/tree.rb", "master/lib/fix/tree.rb"],

    COMMERCE_AMBER_DOES_NOT_OWN_BRGEN: [AMBER_ORDER, MARKETPLACE_ORDER],
    COMMERCE_BRGEN_DOES_NOT_OWN_AMBER: [MARKETPLACE_ORDER, AMBER_ORDER],
    COMMERCE_EXTERNAL_SOURCES_STAY_EXPLAINABLE: ["rails/amber/app/services/price_feed.rb", "rails/amber/app/price.rb"],
    DIRECT_MANIPULATION_FEEDBACK: [RAILS_JS, STUDIO_JS],
    GESTURE_OWNERSHIP: [RAILS_JS, STUDIO_JS],
    HAPTIC_SINGLE_SOURCE: [RAILS_JS, STUDIO_JS],

    I18N_COVERAGE: [VIEWS, PUBLIC_HTML],
    INTER_MODEL_CONTRACT: ["master/lib/review/council/vote.rb", "master/lib/review/scan.rb"],
    INTERACTION_PERFORMANCE: [RAILS_SCSS, STUDIO_CSS],
    MIGRATION_ADD_REFERENCE_NO_FK: [MIGRATION, MODEL],
    MIGRATION_FIND_OR_CREATE_BY: [MIGRATION, MODEL],
    MIGRATION_NOT_NULL_NO_DEFAULT: [MIGRATION, MODEL],

    MIGRATION_REMOVE_COLUMN: [MIGRATION, MODEL],
    NO_SILENT_TEST_SKIP: ["master/test/test_thing.rb", "master/lib/thing.rb"],
    OPENBSD_DMESG_CONSOLE_STYLE: ["master/lib/voice/speech.rb", "master/lib/cli/speech.rb"],
    PAPER_NOT_PURE_WHITE: ["rails/mrdamascy/app/assets/stylesheets/a.css", "rails/brgen/app/assets/stylesheets/a.css"],
    PARAMETRIC_MARK_ONLY: ["rails/mrdamascy/app/assets/stylesheets/a.css", "rails/brgen/app/assets/stylesheets/a.css"],
    SIGNAL_COLOR_NAMING: ["rails/mrdamascy/app/assets/stylesheets/a.css", "rails/brgen/app/assets/stylesheets/a.css"],

    POINTER_FEEDBACK_EARLY: [RAILS_JS, STUDIO_JS],
    PROSE_ACTIVE_VOICE_NB: ["rails/brgen/config/locales/nb.yml", "rails/brgen/config/locales/en.yml"],
    PROSE_OMIT_QUALIFIERS_NB: ["rails/brgen/config/locales/nb.yml", "rails/brgen/config/locales/en.yml"],
    RATE_LIMITING_MISSING: ["rails/brgen/app/controllers/things_controller.rb", MODEL],
    README_VISION: ["master/README.md", "rails/README.md"],
    SIGNATURE_MOMENT: [RAILS_JS, STUDIO_JS],

    SKIP_TO_MAIN: ["rails/brgen/app/views/layouts/application.html.erb", VIEWS],
    STATE_CHOREOGRAPHY: [RAILS_JS, STUDIO_JS],
    STRICT_LOADING_MISSING: [MODEL, "rails/brgen/app/services/thing_finder.rb"],
    TACTILE_FEEDBACK: [RAILS_JS, STUDIO_JS],
    UTILITY_CLASS_SOUP: [VIEWS, PUBLIC_HTML],
    VISUAL_IDENTITY_SOURCE_OF_TRUTH: ["master/data/tokens.yml", "master/data/new_registry.yml"],

    VISUAL_PARTICLE_STIPPLE_PRIMARY: ["master/data/tokens.yml", "master/data/new_registry.yml"],
    VOICE_FAILURES_ARE_ACTIONABLE: ["master/lib/voice/speech.rb", "master/lib/cli/speech.rb"],
    WAITING_STATE_MEANING: [RAILS_JS, STUDIO_JS],
  }.freeze

  def test_every_restored_scope_is_declared_on_its_law
    unscoped = REACH.keys.reject { |id| ::Law.definitions.fetch(id).path }

    assert_empty unscoped, "these Laws lost their path and reach every file again"
  end

  def test_each_law_reaches_inside_its_scope_and_not_outside
    REACH.each do |id, (inside, outside)|
      law = ::Law.definitions.fetch(id)

      assert law.applies?("/repo/#{inside}", language(inside)), "#{id} must reach #{inside}"
      refute law.applies?("/repo/#{outside}", language(outside)), "#{id} must not reach #{outside}"
    end
  end

  def test_each_detector_flags_its_bad_fixture_inside_and_stays_silent_outside
    Dir.mktmpdir("law-path-reach") do |root|
      REACH.each do |id, (inside, outside)|
        law = ::Law.definitions.fetch(id)
        next unless law.main_detector? && law.bad

        text = Array(law.bad).join("\n")

        refute_empty findings(law, file: File.join(root, inside), text:), "#{id} must flag its bad fixture at #{inside}"
        assert_empty findings(law, file: File.join(root, outside), text:), "#{id} must stay silent at #{outside}"
      end
    end
  end

  def test_bokmal_prose_laws_reach_bplans_html_and_not_other_html
    cases = {
      PROSE_ACTIVE_VOICE_NB: [
        "<p>Feilen ble rettet av vedlikeholderen.</p>",
        "<p>Vedlikeholderen rettet feilen.</p>",
      ],
      PROSE_OMIT_QUALIFIERS_NB: [
        "<p>Dette er veldig raskt.</p>",
        "<p>Dette er raskt.</p>",
      ],
    }

    cases.each do |id, (bad, good)|
      law = ::Law.definitions.fetch(id)

      assert law.applies?("/repo/#{BPLANS_HTML}", "html"), "#{id} must reach BPLANS HTML"
      refute law.applies?("/repo/rails/brgen/public/offline.html", "html"),
             "#{id} must not reach unrelated HTML"

      Dir.mktmpdir("bplans-prose") do |root|
        refute_empty findings(law, file: File.join(root, BPLANS_HTML), text: bad), "#{id} must flag its bad HTML fixture"
        assert_empty findings(law, file: File.join(root, BPLANS_HTML), text: good), "#{id} must pass its good HTML fixture"
        assert_empty findings(law, file: File.join(root, "rails/brgen/public/offline.html"), text: bad),
                     "#{id} must stay silent outside BPLANS"
      end
    end
  end

  # The scanner's shape for the one Law named first in this commit's subject:
  # brgen's own marketplace code is not amber reaching into brgen.
  def test_amber_ownership_law_is_silent_on_brgen_marketplace
    law = ::Law.definitions.fetch(:COMMERCE_AMBER_DOES_NOT_OWN_BRGEN)
    file = File.join(Master::ROOT, "..", "rails/brgen_marketplace/app/models/marketplace/order.rb")

    refute law.applies?(File.expand_path(file), "ruby")
  end

  private

  def language(rel) = Master.language_for(rel)&.to_s

  # Law.scan's own selection, for one Law: the whole registry would run the
  # external linters on every probe file.
  def findings(law, file:, text:)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, text)
    law.applies?(file, language(file)) ? law.scan(File.read(file), file:) : []
  end
end
