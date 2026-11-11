# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

# OPENBSD/lib/ruby_select.sh is the one place the deploy path picks a Ruby, so
# these run it under sh and zsh against a throwaway PATH holding fake
# generic and versioned interpreters; the selector must not depend on a
# hard-coded release list.
class TestRubySelect < Minitest::Test
  LIB = File.expand_path("../lib/ruby_select.sh", __dir__)

  def with_path(*names)
    Dir.mktmpdir do |dir|
      names.each do |name|
        path = File.join(dir, name)
        version = name[/\d+/] == "40" ? "40" : "34"
        File.write(path, "#!/bin/sh\nprintf #{version}\n")
        FileUtils.chmod(0o755, path)
      end
      yield dir
    end
  end

  def resolve(dir, shell: "/bin/sh", env: {})
    script = '. "$1" && printf "%s|%s|%s|%s|%s" "$RUBY" "$RUBY_SUFFIX" "$BUNDLE" "$GEM" "$RUBY_CACHE_KEY"'
    out, err, status = Open3.capture3({ "PATH" => dir, "RUBY" => nil }.merge(env), shell, "-c", script, shell, LIB, unsetenv_others: true)
    [out, err, status]
  end

  def shells
    ["/bin/sh", *Dir["/bin/zsh", "/usr/bin/zsh", "/opt/homebrew/bin/zsh"].first(1)]
  end

  def test_uses_first_compatible_versioned_ruby_when_no_generic_exists
    with_path("ruby34", "ruby40", "bundle34", "bundle40", "gem34", "gem40") do |dir|
      shells.each do |shell|
        out, err, status = resolve(dir, shell: shell)
        assert status.success?, err
        assert_equal [File.join(dir, "ruby34"), "34", File.join(dir, "bundle34"), File.join(dir, "gem34"), "ruby34"], out.split("|")
      end
    end
  end

  def test_uses_ruby34_when_it_is_the_only_one
    with_path("ruby34", "bundle34", "gem34") do |dir|
      shells.each do |shell|
        out, err, status = resolve(dir, shell: shell)
        assert status.success?, err
        assert_equal [File.join(dir, "ruby34"), "34", File.join(dir, "bundle34"), File.join(dir, "gem34"), "ruby34"], out.split("|")
      end
    end
  end

  def test_requires_matching_bundle_and_gem_for_versioned_ruby
    with_path("ruby34", "bundle", "gem") do |dir|
      _out, err, status = resolve(dir)
      refute status.success?
      assert_match(/matching bundle34 is unavailable/, err)
    end
  end

  def test_dotted_suffix_outranks_the_undotted_name
    with_path("ruby3.4", "ruby34", "bundle3.4", "gem3.4") do |dir|
      out, = resolve(dir)
      assert_equal [File.join(dir, "ruby3.4"), "3.4", File.join(dir, "bundle3.4")], out.split("|").first(3)
    end
  end

  def test_env_override_wins
    with_path("ruby34", "ruby40", "bundle34", "gem34") do |dir|
      out, = resolve(dir, env: { "RUBY" => File.join(dir, "ruby34") })
      assert_equal [File.join(dir, "ruby34"), "34", File.join(dir, "bundle34")], out.split("|").first(3)
    end
  end

  def test_errors_when_no_ruby_exists
    skip "a package ruby exists in /usr/local/bin" if Dir["/usr/local/bin/ruby*"].any?
    with_path do |dir|
      _out, err, status = resolve(dir)
      refute status.success?
      assert_match(/no compatible Ruby found/, err)
    end
  end

def test_bundler_stays_on_the_installed_version
  with_path("ruby34", "bundle34", "gem34") do |dir|
    shells.each do |shell|
      out, err, status = Open3.capture3({ "PATH" => dir }, shell, "-c", %q(. "$1" && printf "%s" "$BUNDLE_VERSION"), shell, LIB, unsetenv_others: true)
      assert status.success?, err
      assert_equal "system", out, "a lockfile from another Bundler must not trigger a switch the deploy user cannot install"
    end
    out, = Open3.capture3({ "PATH" => dir, "BUNDLE_VERSION" => "4.0.7" }, "/bin/sh", "-c", %q(. "$1" && printf "%s" "$BUNDLE_VERSION"), "sh", LIB, unsetenv_others: true)
    assert_equal "4.0.7", out
  end
end
end
