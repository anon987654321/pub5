# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# .master/config.yml merges over DEFAULTS, so a misspelled key is kept and never
# read: `budget_mx: 2` leaves the $10 default spending with nothing said.
class TestGroundConfig < Minitest::Test
  def config_with(yaml)
    Dir.mktmpdir("ground_config") do |root|
      FileUtils.mkdir_p(File.join(root, ".master"))
      File.write(File.join(root, ".master", "config.yml"), yaml)
      config = nil
      _out, err = capture_io { config = Master::Ground::Config.new(root) }
      yield config, err, root
    end
  end

  def test_a_near_miss_on_a_known_key_is_named_at_load_and_by_validate
    config_with("budget_mx: 2\n") do |config, err|
      assert_match(/'budget_mx' is not read; did you mean 'budget_max'/, err) # source-assertion: ok — the warning written to stderr, not a source file
      assert_includes config.validate.join, "did you mean 'budget_max'"
      assert_in_delta Master::Ground::Config::BUDGET_MAX_DEFAULT, config.budget_max
    end
  end

  # The web tier and pairing keep their own keys here, so only a near miss is
  # a finding; an unrelated key and a short one two edits away are not.
  def test_legacy_opus_preference_migrates_once_to_routed_default
    config_with("model: claude-opus-5-5\n") do |config, err, root|
      assert_equal Master::Ground::Config::DEFAULTS["model"], config.model
      assert_match(/migrated legacy model preference/, err)
      persisted = YAML.safe_load_file(File.join(root, ".master", "config.yml"), aliases: true)
      assert_equal Master::Ground::Config::DEFAULTS["model"], persisted.fetch("model")
      assert_equal true, persisted.fetch("model_preference_migrated")

      config["model"] = "claude-opus-5-5"
      config.save!
      again = Master::Ground::Config.new(root)
      assert_equal "claude-opus-5-5", again.model
    end
  end

  def test_an_unrelated_key_is_not_a_typo
    config_with("web_token: abc\nroot: /srv\npersona: anchor\n") do |config, err|
      assert_empty err
      assert config.valid?, config.validate.join("; ")
    end
  end

  # One config for every checkout: a shared file beside ~/.config/master/env wins over a
  # checkout's .master/config.yml, MASTER_CONFIG wins over both, and migration moves the
  # checkout file across verified, keeping the original as .migrated.
  def test_the_shared_config_serves_every_checkout_once_migrated
    Dir.mktmpdir("config_home") do |home|
      with_env("XDG_CONFIG_HOME" => home) do
        config_with("model: checkout-model\n") do |_config, _err, root|
          assert_equal File.join(root, ".master", "config.yml"), MasterPaths.config_file(root:)

          assert_match(/moved/, Master::Ground::Config.migrate_to_shared!(root))
          assert_equal File.join(home, "master", "config.yml"), MasterPaths.config_file(root:)
          assert_equal "checkout-model", Master::Ground::Config.new(root)["model"]
          assert File.file?(File.join(root, ".master", "config.yml.migrated"))
          assert_match(/already exists/, Master::Ground::Config.migrate_to_shared!(root))
        end
      end
    end
  end

  def test_master_config_names_the_file_outright
    Dir.mktmpdir("explicit") do |dir|
      path = File.join(dir, "elsewhere.yml")
      with_env("MASTER_CONFIG" => path) { assert_equal path, MasterPaths.config_file(root: dir) }
    end
  end

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV[key]] }
    pairs.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end
end
