# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../tools/chrome_install"
require_relative "../checks/support/chrome_process"

class TestChromeInstall < Minitest::Test
  Installer = Operator::ChromeInstall

  def test_supported_platforms_match_the_official_download_feed
    assert_equal "linux64", Installer.platform_for(host_os: "linux-gnu", cpu: "x86_64")
    assert_equal "linux-arm64", Installer.platform_for(host_os: "linux-gnu", cpu: "aarch64")
    assert_equal "mac-arm64", Installer.platform_for(host_os: "darwin", cpu: "arm64")
    assert_equal "mac-x64", Installer.platform_for(host_os: "darwin", cpu: "x86_64")
    assert_raises(Installer::Failure) { Installer.platform_for(host_os: "openbsd", cpu: "amd64") }
  end

  def test_archive_listing_refuses_path_traversal_and_wrong_roots
    assert Installer.safe_archive_entries!(["chrome-headless-shell-linux64/chrome-headless-shell"], folder: "chrome-headless-shell-linux64")
    assert_raises(Installer::Failure) do
      Installer.safe_archive_entries!(["chrome-headless-shell-linux64/../../outside"], folder: "chrome-headless-shell-linux64")
    end
    assert_raises(Installer::Failure) do
      Installer.safe_archive_entries!(["/tmp/outside"], folder: "chrome-headless-shell-linux64")
    end
    assert_raises(Installer::Failure) do
      Installer.safe_archive_entries!(["chromedriver-linux64/chromedriver"], folder: "chrome-headless-shell-linux64")
    end
  end

  def test_chrome_path_is_persisted_without_rewriting_other_environment_values
    Dir.mktmpdir("chrome-install") do |dir|
      binary = File.join(dir, "chrome-headless-shell")
      File.write(binary, "test executable")
      File.chmod(0o700, binary)
      env_file = File.join(dir, "config", "master", "env")
      FileUtils.mkdir_p(File.dirname(env_file))
      File.write(env_file, "OPENAI_API_KEY=keep-this\nCHROME_PATH=/old/path\nOTHER=value\n")

      Installer.persist_chrome_path!(binary, env_file:)

      written = File.read(env_file)
      assert_includes written, "OPENAI_API_KEY=keep-this"
      assert_includes written, "OTHER=value"
      assert_includes written, "CHROME_PATH=\"#{binary}\""
      assert_equal 0o600, File.stat(env_file).mode & 0o777
      assert_equal 0o700, File.stat(File.dirname(env_file)).mode & 0o777
    end
  end

  def test_chrome_discovery_reads_a_path_added_after_module_load
    old = ENV["CHROME_PATH"]
    Dir.mktmpdir("chrome-discovery") do |dir|
      binary = File.join(dir, "chrome")
      File.write(binary, "test executable")
      File.chmod(0o700, binary)
      ENV["CHROME_PATH"] = binary
      discovery = Object.new.extend(Deploy::ChromeProcess::Discovery)

      assert_equal binary, discovery.chrome_path
      assert discovery.available?
    end
  ensure
    old.nil? ? ENV.delete("CHROME_PATH") : ENV["CHROME_PATH"] = old
  end
end
