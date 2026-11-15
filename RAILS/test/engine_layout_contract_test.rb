# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# The engine layout has one traversal answer, EngineRoots, because the depth
# has already bitten twice: a single-level glob went blind to the five engines
# when they moved under engines/<name>/, and a bare trailing ** matches one
# level in a Ruby glob, so the nested takeaway engine went unseen again — the
# flash contract reported flash.takeaway.allergens_saved as unresolvable while
# the mounted engine served it. This contract pins the traversal itself, so
# the next nesting level fails here and not three consumers away.
class EngineLayoutContractTest < Minitest::Test
  REPOSITORY_ROOT = File.expand_path("../..", __dir__)
  RAILS_ROOT = File.join(REPOSITORY_ROOT, "RAILS")
  SURFACES = File.join("MASTER", "checks", "support", "brgen_vertical_surfaces.rb")

  def setup
    roots = [ENV["PUB5_ROOT"].to_s.strip, REPOSITORY_ROOT, "/home/dev/pub5"].reject(&:empty?)
    require File.join(roots.find { |root| File.file?(File.join(root, SURFACES)) } || roots.first, SURFACES)
  end

  def test_every_registered_engine_root_exists
    EngineRoots::PATHS.each do |name, path|
      assert File.directory?(File.join(RAILS_ROOT, path)), "engine #{name} registered at #{path} but the directory is not there"
    end
  end

  def test_the_traversal_sees_engines_at_any_nesting_depth
    views = EngineRoots.app_view_paths(RAILS_ROOT)
    controllers = EngineRoots.app_controller_paths(RAILS_ROOT)
    locale_dirs = EngineRoots.app_locale_dirs(RAILS_ROOT)

    # A top-level engine and a twice-nested one; both must appear.
    assert views.grep(%r{engines/dating/app/views/}).any?, "the view traversal lost the top-level engines"
    assert views.grep(%r{engines/marketplace/engines/takeaway/app/views/}).any?,
           "the view traversal is blind to twice-nested engines — the takeaway bug again"
    assert controllers.grep(%r{engines/marketplace/engines/takeaway/app/controllers/}).any?,
           "the controller traversal is blind to twice-nested engines"
    assert locale_dirs.grep(%r{engines/marketplace/engines/takeaway/config/locales\z}).any?,
           "the locale traversal is blind to twice-nested engines"
  end

  def test_no_traversal_invents_files_that_do_not_exist
    EngineRoots.app_view_paths(RAILS_ROOT).each { |path| assert File.file?(path), "traversal returned a missing view: #{path}" }
    EngineRoots.app_controller_paths(RAILS_ROOT).each { |path| assert File.file?(path), "traversal returned a missing controller: #{path}" }
  end
end
