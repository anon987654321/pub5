# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

fleet_path = File.join(Master::ROOT, "web", "app", "services", "fleet_panel.rb")
require fleet_path

# The dashboard renders the fleet: sibling health against apps.yml's own ports
# and domains, the host's load against the guard's own thresholds, and the
# guard's own shed order — parsed from the guard script, never copied. The
# service is plain Ruby, so this suite drives it directly with an injected
# probe; the wiring contracts read the controller, the view, the poller and
# both locales so the panel cannot silently drop off one of them.
class TestDashboardFleetPanel < Minitest::Test
  VIEW = File.join(Master::ROOT, "web", "app", "views", "dashboard", "index.html.erb")
  CONTROLLER = File.join(Master::ROOT, "web", "app", "controllers", "dashboard_controller.rb")
  POLLER = File.join(Master::ROOT, "web", "public", "dashboard_live.js")

  def test_read_inventories_the_siblings_from_apps_yml
    fleet = FleetPanel.read(root: Master::ROOT, probe: ->(_app) { true })

    names = fleet[:apps].map { |app| app[:name] }
    assert_equal %w[brgen amber bsdports mrdamascy], names
    brgen = fleet[:apps].first
    assert_equal 38_182, brgen[:port]
    assert_equal "brgen.no", brgen[:domain]
    assert fleet[:apps].all? { |app| app[:up] == true }, "an injected true probe marks every app up"
  end

  def test_a_refused_probe_is_down_never_an_exception
    fleet = FleetPanel.read(root: Master::ROOT, probe: ->(_app) { false })

    assert fleet[:apps].all? { |app| app[:up] == false }
  end

  def test_the_default_probe_answers_false_without_a_socket_on_a_closed_port
    entry = { name: "nothing", port: 1, domain: "example.invalid" }

    refute FleetPanel.probe_app(entry, probe: nil)[:up]
  end

  def test_the_guard_contract_is_parsed_not_copied
    guard = FleetPanel.read(root: Master::ROOT, probe: ->(_app) { true })[:guard]

    assert_equal %w[bsdports amber], guard[:shed_order], "the cheapest-to-lose app sheds first"
    assert_equal 2, guard[:shed_strikes]
    assert_equal 2.5, guard[:load_warn]
    assert_equal 5.0, guard[:load_crit]
  end

  def test_load_average_is_a_number_or_nil_without_raising
    value = FleetPanel.load_average

    assert(value.nil? || (value.is_a?(Float) && value >= 0.0))
  end

  def test_a_missing_guard_script_degrades_to_a_nil_guard_not_a_crash
    Dir.mktmpdir do |root|
      fleet = FleetPanel.read(root: root, probe: ->(_app) { true })

      assert_empty fleet[:apps]
      assert_nil fleet[:guard]
    end
  end

  def test_the_payload_carries_the_fleet_and_the_quota_facts
    controller = File.read(CONTROLLER)

    assert_includes controller, "fleet: FleetPanel.read(root: root)"
    assert_includes controller, "model_quota: Master::Io::ModelQuota.snapshot"
    assert_includes controller, "cache_efficiency: Master::Trace::CacheEfficiency.snapshot"
    assert_includes controller, 'require_relative "../services/fleet_panel"'
  end

  def test_the_view_and_the_poller_render_the_two_panels
    view = File.read(VIEW)
    poller = File.read(POLLER)

    # The pane id is built from the key by the panel lambda (id: key), so the
    # view's contract is the panel call and the lambda that names its panes.
    assert_includes view, 'id: key', "the panel lambda names each pane after its key"
    %w[fleet quota].each do |panel|
      assert_includes view, %Q{panel.("#{panel}"},
                      "the view declares the #{panel} panel"
      assert_match(/getElementById\('#{panel}'\)/, poller, "the poller writes the #{panel} pane")
    end
    assert_includes poller, "d.fleet", "the poller reads the fleet payload"
    assert_includes poller, "d.model_quota", "the poller reads the quota payload"
    assert_includes poller, "d.cache_efficiency", "the poller reads the cache payload"
    assert_includes poller, "quota.provider", "the poller renders the provider quota sample"
    assert_includes poller, "quota.forecasts", "the poller renders per-model forecasts"
    assert_includes poller, "cache.measured", "the poller distinguishes unknown cache data from zero"
    assert_includes poller, "provider.fresh", "the poller labels sample freshness"
    assert_includes poller, "shed_order", "the poller renders the guard's shed order"
  end

  def test_task_rail_states_have_quiet_visual_distinctions_in_source_and_build
    source = File.read(File.join(Master::ROOT, "web", "styles", "face", "43_face_chrome.css"))
    built = File.read(File.join(Master::ROOT, "web", "public", "face.css"))

    [
      '.master-task[data-state="active"] .master-task-status',
      '.master-task[data-state^="waiting-"] .master-task-status',
      '.master-task[data-state="failed"]',
    ].each do |selector|
      assert_includes source, selector
      assert_includes built, selector
    end
    assert_includes source, "text-decoration-style: dotted;"
    assert_includes built, "text-decoration-style: dotted;"
    assert_includes source, "border-inline-start: 2px solid var(--c-danger);"
    assert_includes built, "border-inline-start: 2px solid var(--c-danger);"
    refute_match(/\.master-task-rail\s*\{\s*\}/, source)
  end

  def test_both_locales_declare_every_fleet_and_quota_label
    %w[en nb].each do |locale|
      translations = YAML.safe_load(File.read(File.join(Master::ROOT, "web", "config", "locales", "#{locale}.yml")))
      dashboard = translations.dig(locale, "dashboard")
      %w[fleet quota].each do |panel|
        assert dashboard.dig("panels", panel), "#{locale} names the #{panel} panel"
        assert dashboard[panel].is_a?(Hash), "#{locale} carries the #{panel} labels"
      end
    end
  end
end
