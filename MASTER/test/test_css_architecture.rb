# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

require_relative "../checks/support/css_autofix_region"
require_relative "../checks/support/geometry_autofix"
require_relative "../checks/lib/source/css_layer_stack"
require_relative "../checks/lib/source/css_no_important"
require_relative "../checks/lib/source/css_specificity_ceiling"

# Proofs for the cascade architecture: the layer-stack check, the generated-
# region important ban, the specificity ceiling, and the autofix writer that
# must land inside @layer autofix without ever emitting !important.
#
# Nothing here reads the real RAILS tree: each test builds a small app-shaped
# tmp tree and points the check's constants at it, the way the checks
# themselves read the tree (Fleet-shaped roots, one application.scss entry).
class CssArchitectureTest < Minitest::Test
  STACK_ORDER = %w[reset tokens base components utilities autofix].freeze
  ORDER_LINE = "@layer reset, tokens, base, components, utilities, autofix;\n"

  def setup
    @root = Dir.mktmpdir("css-arch")
    @rails = File.join(@root, "RAILS")
    @app = "brgen"
    FileUtils.mkdir_p(File.join(@rails, @app, "app/assets/stylesheets"))
    FileUtils.mkdir_p(File.join(@rails, @app, "app/assets/builds"))
    @original_data = File.read(data_path)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  # --- data is the single owner -----------------------------------------

  def test_data_order_ends_with_autofix_layer
    order = yaml_data.dig("cascade_layers", "order")
    assert_equal "autofix", order.last
    assert_includes order, "components"
  end

  def test_data_bans_important_in_autofix_layer
    forbidden = yaml_data.dig("cascade_layers", "rules", "forbid_important_in")
    assert_includes forbidden, "autofix"
  end

  def test_data_ceiling_parses
    assert_equal "0,3,0", yaml_data.dig("specificity", "ceiling")
  end

  # --- shared region shape ----------------------------------------------

  def test_region_wrap_applies_only_to_declared_stack
    region = "HEADER\n.btn { min-height: 44px; }\n"
    bare = Deploy::CssAutofixRegion.wrap(region, ".btn { color: red; }\n")
    layered = Deploy::CssAutofixRegion.wrap(region, "#{ORDER_LINE}.btn { color: red; }\n")

    assert_equal region, bare
    assert layered.start_with?("@layer autofix {\n")
    assert layered.end_with?("}\n")
    assert_equal region, Deploy::CssAutofixRegion.unwrap(layered)
  end

  def test_region_bodies_find_the_writer
    source = <<~SCSS
      .card { padding: 0; }
      #{Deploy::CssAutofixRegion::GEOMETRY_OPEN}
      .btn { min-height: 44px; }
      #{Deploy::CssAutofixRegion::GEOMETRY_CLOSE}
    SCSS
    bodies = Deploy::CssAutofixRegion.region_bodies(source)
    assert_equal 1, bodies.size
    assert_includes bodies[0], ".btn { min-height: 44px; }"
  end

  # --- css_layer_stack --------------------------------------------------

  def test_layer_stack_warns_when_entry_declares_nothing
    entry("/* no layers yet */\n.card { padding: 0; }\n")
    result = run_layer_stack
    assert_empty result.failures
    assert result.warnings.any? { |m| m.include?("declares no cascade layer stack") }
  end

  def test_layer_stack_fails_on_competing_order_statement
    entry(ORDER_LINE)
    partial = File.join(@rails, @app, "app/assets/stylesheets", "_competing.scss")
    File.write(partial, "@layer reset, base;\n.card { padding: 0; }\n")
    result = run_layer_stack
    assert result.failures.any? { |m| m.include?("declares a @layer order statement") }
  end

  def test_layer_stack_fails_on_wrong_order
    entry("@layer reset, tokens, base, utilities, components, autofix;\n")
    result = run_layer_stack
    assert result.failures.any? { |m| m.include?("does not match") }
  end

  def test_layer_stack_fails_on_second_statement_in_entry
    entry("#{ORDER_LINE}@layer base, components;\n")
    result = run_layer_stack
    assert result.failures.any? { |m| m.include?("@layer order statements") }
  end

  def test_layer_stack_fails_when_declared_stack_keeps_unlayered_rules
    entry("#{ORDER_LINE}.card { padding: 0; }\n")
    result = run_layer_stack
    assert result.failures.any? { |m| m.include?("outside any @layer") }
  end

  def test_layer_stack_passes_layered_entry
    entry("#{ORDER_LINE}@layer components {\n  .card { padding: 0; }\n}\n")
    result = run_layer_stack
    assert_empty result.failures
    assert_empty result.soft_failures
  end

  def test_layer_stack_requires_generated_region_inside_autofix_layer
    source = "#{ORDER_LINE}@layer components {\n  .card { padding: 0; }\n}\n"
    source += "#{Deploy::CssAutofixRegion::GEOMETRY_OPEN}\n.btn { min-height: 44px; }\n#{Deploy::CssAutofixRegion::GEOMETRY_CLOSE}\n"
    entry(source)
    result = run_layer_stack
    assert result.failures.any? { |m| m.include?("outside @layer autofix") }
  end

  def test_layer_stack_accepts_wrapped_generated_region
    source = "#{ORDER_LINE}@layer components {\n  .card { padding: 0; }\n}\n"
    source += "#{Deploy::CssAutofixRegion::GEOMETRY_OPEN}\n@layer autofix {\n.btn { min-height: 44px; }\n}\n#{Deploy::CssAutofixRegion::GEOMETRY_CLOSE}\n"
    entry(source)
    result = run_layer_stack
    assert_empty result.failures
  end

  # --- css_no_important -------------------------------------------------

  def test_no_important_fails_on_important_inside_generated_region
    source = "#{Deploy::CssAutofixRegion::GEOMETRY_OPEN}\n.btn { min-height: 44px !important; }\n#{Deploy::CssAutofixRegion::GEOMETRY_CLOSE}\n"
    entry(source)
    result = run_no_important
    assert result.failures.any? { |m| m.include?("generated autofix region") }
  end

  def test_no_important_fails_on_important_inside_bare_autofix_layer
    source = "@layer autofix {\n.glow { display: none !important; }\n}\n"
    entry(source)
    result = run_no_important
    assert result.failures.any? { |m| m.include?("!important") }
  end

  def test_no_important_warns_not_fails_on_author_important
    entry(".btn { color: red !important; }\n")
    result = run_no_important
    assert_empty result.failures
    assert result.warnings.any? { |m| m.include?("author !important") }
  end

  # --- css_specificity_ceiling -----------------------------------------

  def test_specificity_flags_id_heavy_selector_from_build
    File.write(build_path, ".card { color: red; }\n#shop .a .b .c .d { color: blue; }\n")
    result = run_specificity
    assert result.warnings.any? { |m| m.include?("exceeds 0,3,0") }
    assert_empty result.failures # mode warn
  end

  def test_specificity_is_inconclusive_without_build
    FileUtils.rm_f(build_path)
    result = run_specificity
    assert result.unchecked.any? { |m| m.include?("no compiled build") }
  end

  def test_specificity_mode_fail_hard_fails
    data = yaml_data
    data["specificity"]["mode"] = "fail"
    File.write(data_path, YAML.dump(data))
    File.write(build_path, "#shop .a .b .c .d { color: blue; }\n")
    result = run_specificity
    assert result.failures.any? { |m| m.include?("css_specificity_ceiling") }
  ensure
    write_data_file
  end

  def test_specificity_ignores_where_and_honours_ceiling
    File.write(build_path, ":where(#shop, #a, #b) .c { color: red; }\n.card:hover:focus { color: blue; }\n")
    result = run_specificity
    assert_empty result.failures
    assert_empty result.soft_failures
  end

  # --- autofix writers ---------------------------------------------------

  def test_geometry_autofix_writes_unlayered_region_for_unmigrated_entry
    with_tmp_tree(Deploy::GeometryAutofix) do
      entry(".card { height: 40px; }\n")
      Deploy::GeometryAutofix.apply([{ app: @app, selector: "div.card", kind: :touch, detail: "28px" }])
      source = File.read(entry_path)
      assert_includes source, Deploy::CssAutofixRegion::GEOMETRY_OPEN
      refute_includes source, "@layer autofix"
      assert_includes source, "min-height: 44px"
    end
  end

  def test_geometry_autofix_wraps_region_when_stack_declared
    with_tmp_tree(Deploy::GeometryAutofix) do
      entry("#{ORDER_LINE}@layer components {\n.card { height: 40px; }\n}\n")
      Deploy::GeometryAutofix.apply([{ app: @app, selector: "div.card", kind: :touch, detail: "28px" }])
      source = File.read(entry_path)
      assert_match(/#{Regexp.escape(Deploy::CssAutofixRegion::GEOMETRY_OPEN)}\n@layer autofix \{\n/, source)
      assert_includes source, "min-height: 44px"
    end
  end

  def test_geometry_autofix_merges_existing_rows_across_rounds
    with_tmp_tree(Deploy::GeometryAutofix) do
      entry(".card { height: 40px; }\n")
      Deploy::GeometryAutofix.apply([{ app: @app, selector: "div.card", kind: :touch, detail: "28px" }])
      Deploy::GeometryAutofix.apply([{ app: @app, selector: "ul.nav", kind: :overflow, detail: "spill" }])
      source = File.read(entry_path)
      assert_includes source, "min-height: 44px"
      assert_includes source, "max-width: 100%"
      # One region, not two: the merge is a union inside the same markers.
      assert_equal 1, source.scan(Regexp.new(Regexp.escape(Deploy::CssAutofixRegion::GEOMETRY_OPEN))).size
    end
  end

  def test_geometry_writer_never_emits_important
    with_tmp_tree(Deploy::GeometryAutofix) do
      entry(".card { height: 40px; }\n")
      Deploy::GeometryAutofix.apply([{ app: @app, selector: "div.card", kind: :touch, detail: "28px" }])
      refute_match(/!\s*important/, File.read(entry_path))
    end
  end

  # --- helpers -----------------------------------------------------------

  def yaml_data
    YAML.safe_load_file(data_path)
  end

  def data_path
    File.expand_path("../data/css_architecture.yml", __dir__)
  end

  def write_data_file
    # Restore the shipped data file after a test mutated it (mode fail).
    File.write(data_path, @original_data)
  end

  def entry_path
    File.join(@rails, @app, "app/assets/stylesheets/application.scss")
  end

  def build_path
    File.join(@rails, @app, "app/assets/builds/application.css")
  end

  def entry(body)
    File.write(entry_path, body)
  end

  # Each check class pins its corpus at constant time (ROOT/RAILS/APPS). The
  # proofs rebind those constants to the tmp tree instead of touching the
  # real repo - including the writer paths, so an autofix round inside a proof
  # can never reach the real RAILS entry or run the real builder.
  def with_tmp_tree(klass)
    rebind = lambda do |mod|
      mod.send(:remove_const, :ROOT) if mod.const_defined?(:ROOT, false)
      mod.const_set(:ROOT, @root)
      if mod.const_defined?(:RAILS, false)
        mod.send(:remove_const, :RAILS)
        mod.const_set(:RAILS, @rails)
      end
      if mod.const_defined?(:RAILS_ROOT, false)
        mod.send(:remove_const, :RAILS_ROOT)
        mod.const_set(:RAILS_ROOT, @rails)
      end
      if mod.const_defined?(:DATA, false)
        mod.send(:remove_const, :DATA)
        mod.const_set(:DATA, data_path)
      end
      if mod.const_defined?(:APPS, false)
        mod.send(:remove_const, :APPS)
        mod.const_set(:APPS, [@app].freeze)
      end
      if mod.const_defined?(:MASTER_WEB, false)
        mod.send(:remove_const, :MASTER_WEB)
        mod.const_set(:MASTER_WEB, [].freeze)
      end
    end
    rebind.call(klass)
    rebind.call(Deploy::GeometryAutofix) if klass == Deploy::GeometryAutofix
    yield
  ensure
    [klass, Deploy::GeometryAutofix].uniq.each do |mod|
      %i[ROOT RAILS RAILS_ROOT DATA APPS MASTER_WEB].each do |name|
        mod.send(:remove_const, name) if mod.const_defined?(name, false)
      end
    end
    # The removed constants are re-evaluated lazily by the next require of the
    # file through test_helper's load path; define them back from the source
    # so later tests see the shipped corpus again.
    restore_consts(klass)
    restore_consts(Deploy::GeometryAutofix)
  end

  def restore_consts(mod)
    repo = File.expand_path("../../..", __dir__)
    set = lambda do |mod, name, value|
      mod.send(:remove_const, name) if mod.const_defined?(name, false)
      mod.const_set(name, value)
    end
    case mod.name
    when "Deploy::CssLayerStackCheck"
      set.call(mod, :ROOT, repo)
      set.call(mod, :RAILS, File.join(repo, "RAILS"))
      set.call(mod, :DATA, File.join(repo, "MASTER", "data", "css_architecture.yml"))
      set.call(mod, :APPS, Fleet.asset_roots.freeze)
    when "Deploy::CssNoImportantCheck"
      set.call(mod, :ROOT, repo)
      set.call(mod, :RAILS, File.join(repo, "RAILS"))
      set.call(mod, :APPS, Fleet.asset_roots.freeze)
      set.call(mod, :MASTER_WEB, %w[MASTER/web/public/face.css MASTER/web/public/chat_upload.css].freeze)
    when "Deploy::CssSpecificityCeilingCheck"
      set.call(mod, :ROOT, repo)
      set.call(mod, :RAILS, File.join(repo, "RAILS"))
      set.call(mod, :DATA, File.join(repo, "MASTER", "data", "css_architecture.yml"))
      set.call(mod, :APPS, Fleet.asset_roots.freeze)
    when "Deploy::GeometryAutofix"
      set.call(mod, :ROOT, repo)
      set.call(mod, :RAILS_ROOT, File.join(repo, "RAILS"))
    end
  end

  def run_layer_stack
    with_tmp_tree(Deploy::CssLayerStackCheck) { Deploy::CssLayerStackCheck.run }
  end

  def run_no_important
    with_tmp_tree(Deploy::CssNoImportantCheck) { Deploy::CssNoImportantCheck.run }
  end

  def run_specificity
    with_tmp_tree(Deploy::CssSpecificityCeilingCheck) { Deploy::CssSpecificityCeilingCheck.run }
  end
end
