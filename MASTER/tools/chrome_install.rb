# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "open3"
require "rbconfig"
require "tmpdir"
require "timeout"
require "uri"

module Operator
  # Installs the official Chrome for Testing headless shell for rendered checks.
  # It is user-scoped, versioned, and only writes CHROME_PATH to the existing
  # private MASTER env file; it does not alter the host's system packages.
  class ChromeInstall
    MANIFEST_URL = "https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json"
    MAX_ARCHIVE_BYTES = 350 * 1024 * 1024
    ENV_FILE = File.expand_path("~/.config/master/env")

    Failure = Class.new(StandardError)

    def self.platform_for(host_os:, cpu:)
      case host_os
      when /darwin/i
        return "mac-arm64" if cpu.match?(/arm64|aarch64/i)
        return "mac-x64" if cpu.match?(/x86_64|amd64/i)
      when /linux/i
        return "linux-arm64" if cpu.match?(/arm64|aarch64/i)
        return "linux64" if cpu.match?(/x86_64|amd64/i)
      end
      raise Failure, "unsupported host #{host_os}/#{cpu}; OpenBSD users should install the system chromium package"
    end

    def self.safe_archive_entries!(entries, folder:)
      names = Array(entries).map(&:to_s).map(&:strip).reject(&:empty?)
      raise Failure, "Chrome archive contains no files" if names.empty?

      unsafe = names.find do |name|
        name.start_with?("/", "\\") || name.match?(/\A[A-Za-z]:/) ||
          name.split(/[\\\/]/).include?("..") || name.include?("\0")
      end
      raise Failure, "unsafe archive entry: #{unsafe}" if unsafe
      raise Failure, "Chrome archive does not contain #{folder}/" unless names.any? { |name| name.start_with?("#{folder}/") }

      names
    end

    def self.persist_chrome_path!(path, env_file: ENV_FILE)
      path = File.expand_path(path)
      raise Failure, "CHROME_PATH is not executable: #{path}" unless File.file?(path) && File.executable?(path)

      directory = File.dirname(env_file)
      raise Failure, "env directory is a symbolic link: #{directory}" if File.symlink?(directory)
      FileUtils.mkdir_p(directory, mode: 0o700)
      File.chmod(0o700, directory)
      raise Failure, "env file is a symbolic link: #{env_file}" if File.symlink?(env_file)

      old = File.file?(env_file) ? File.read(env_file, encoding: "UTF-8") : ""
      raise Failure, "env file exceeds the 1 MiB safety limit" if old.bytesize > 1_048_576
      unless path.match?(/\A[^\\\"$\x60\r\n]+\z/)
        raise Failure, "home path contains unsupported shell quoting characters: #{path}"
      end

      lines = old.lines.reject { |line| line.match?(/\A\s*(?:export\s+)?CHROME_PATH\s*=/) }
      lines << "\n" unless lines.empty? || lines.last.end_with?("\n")
      lines << "CHROME_PATH=\"#{path}\"\n"
      tmp = "#{env_file}.tmp-#{Process.pid}"
      raise Failure, "temporary env path already exists: #{tmp}" if File.exist?(tmp) || File.symlink?(tmp)
      begin
        File.open(tmp, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(lines.join)
          file.flush
          file.fsync
        end
        File.rename(tmp, env_file)
        File.chmod(0o600, env_file)
      ensure
        File.delete(tmp) if File.file?(tmp) && !File.symlink?(tmp)
      end
      env_file
    end

    def initialize(home: Dir.home, env_file: ENV_FILE)
      @home = File.expand_path(home)
      @env_file = env_file
    end

    def install
      platform = self.class.platform_for(host_os: RbConfig::CONFIG.fetch("host_os"), cpu: RbConfig::CONFIG.fetch("host_cpu"))
      version, url = stable_download(platform)
      folder = File.basename(URI(url).path, ".zip")
      install_root = File.join(@home, ".cache", "pub5", "chrome-headless-shell")
      FileUtils.mkdir_p(install_root, mode: 0o700)
      final_dir = File.join(install_root, version)
      binary_path = File.join(final_dir, folder, "chrome-headless-shell")

      unless File.executable?(binary_path)
        raise Failure, "refusing to replace an existing incomplete install: #{final_dir}" if File.exist?(final_dir) || File.symlink?(final_dir)

        install_archive(url:, install_root:, final_dir:, folder:)
      end
      raise Failure, "Chrome archive did not produce an executable: #{binary_path}" unless File.file?(binary_path)
      File.chmod((File.stat(binary_path).mode & 0o777) | 0o111, binary_path)
      raise Failure, "Chrome binary is not executable: #{binary_path}" unless File.executable?(binary_path)

      probe, probe_status = begin
        Timeout.timeout(8) { Open3.capture2e(binary_path, "--version") }
      rescue StandardError => e
        ["#{e.class}: #{e.message}", nil]
      end
      self.class.persist_chrome_path!(binary_path, env_file: @env_file)
      ENV["CHROME_PATH"] = binary_path

      status = probe_status&.success? ? probe.to_s.lines.first.to_s.strip : "launch probe inconclusive: #{probe.to_s.lines.first.to_s.strip}"
      "browser0: installed #{version} (#{platform})\n" \
        "browser0: CHROME_PATH=#{binary_path}\n" \
        "browser0: #{status}\n" \
        "browser0: saved in #{@env_file} (0600)"
    rescue Failure
      raise
    rescue StandardError => e
      raise Failure, "#{e.class}: #{e.message}"
    end

    private

    def stable_download(platform)
      uri = URI(MANIFEST_URL)
      body = https_get(uri, limit: 1_048_576)
      manifest = JSON.parse(body)
      stable = manifest.fetch("channels").fetch("Stable")
      version = stable.fetch("version").to_s
      raise Failure, "Chrome Stable manifest has an invalid version: #{version.inspect}" unless version.match?(/\A\d+(?:\.\d+){3}\z/)

      rows = stable.fetch("downloads").fetch("chrome-headless-shell")
      row = rows.find { |entry| entry["platform"] == platform }
      raise Failure, "Chrome Stable has no chrome-headless-shell build for #{platform}" unless row

      url = row.fetch("url").to_s
      uri = URI(url)
      prefix = "/chrome-for-testing-public/#{version}/#{platform}/"
      unless uri.is_a?(URI::HTTPS) && uri.host == "storage.googleapis.com" &&
             uri.path.start_with?(prefix) && uri.path.end_with?(".zip")
        raise Failure, "refusing unexpected Chrome archive URL: #{url}"
      end
      [version, url]
    rescue JSON::ParserError, KeyError, URI::InvalidURIError => e
      raise Failure, "Chrome Stable manifest is incomplete: #{e.message}"
    end

    def install_archive(url:, install_root:, final_dir:, folder:)
      Dir.mktmpdir(".chrome-install-", install_root) do |stage|
        zip = File.join(stage, "chrome.zip")
        download_archive(url, zip)
        extractor = find_extractor
        names = list_archive(extractor, zip)
        self.class.safe_archive_entries!(names, folder:)
        extract_archive(extractor, zip, stage)
        expected_dir = File.join(stage, folder)
        binary = File.join(expected_dir, "chrome-headless-shell")
        raise Failure, "expected executable is absent from Chrome archive" unless File.file?(binary)

        File.chmod((File.stat(binary).mode & 0o777) | 0o111, binary)
        File.delete(zip) if File.file?(zip)
        File.rename(expected_dir, final_dir)
      end
    rescue Errno::EEXIST, Errno::ENOTEMPTY
      raise Failure, "another Chrome installation won the versioned path; rerun the installer"
    end

    def download_archive(url, path)
      uri = URI(url)
      total = 0
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 120) do |http|
          request = Net::HTTP::Get.new(uri.request_uri)
          http.request(request) do |response|
            raise Failure, "Chrome download returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
            length = response["content-length"].to_i
            raise Failure, "Chrome archive exceeds the 350 MiB safety limit" if length > MAX_ARCHIVE_BYTES

            response.read_body do |chunk|
              total += chunk.bytesize
              raise Failure, "Chrome archive exceeds the 350 MiB safety limit" if total > MAX_ARCHIVE_BYTES
              file.write(chunk)
            end
          end
        end
        file.flush
        file.fsync
      end
      raise Failure, "Chrome archive download was empty" if total.zero?
    rescue StandardError => e
      File.delete(path) if File.file?(path)
      raise Failure, "download failed: #{e.class}: #{e.message}"
    end

    def find_extractor
      %w[unzip bsdtar].find do |candidate|
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
          File.executable?(File.join(directory, candidate))
        end
      end || raise(Failure, "install unzip or bsdtar to extract Chrome for Testing")
    end

    def list_archive(extractor, zip)
      args = extractor == "unzip" ? [extractor, "-Z1", zip] : [extractor, "-tf", zip]
      output, status = Open3.capture2e(*args)
      raise Failure, "cannot inspect Chrome archive: #{output.lines.first}" unless status.success?

      output.lines.map(&:strip)
    end

    def extract_archive(extractor, zip, directory)
      args = extractor == "unzip" ? [extractor, "-q", zip, "-d", directory] : [extractor, "-xf", zip, "-C", directory]
      output, status = Open3.capture2e(*args)
      raise Failure, "Chrome archive extraction failed: #{output.lines.first}" unless status.success?
    end

    def https_get(uri, limit:)
      raise Failure, "manifest URL must use HTTPS" unless uri.is_a?(URI::HTTPS)
      response_body = +""
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
        response = http.get(uri.request_uri)
        raise Failure, "manifest returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
        response_body = response.body.to_s
      end
      raise Failure, "Chrome manifest exceeds #{limit} bytes" if response_body.bytesize > limit

      response_body
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    puts Operator::ChromeInstall.new.install
  rescue Operator::ChromeInstall::Failure => e
    warn "browser0: BLOCKED: #{e.message}"
    exit 1
  end
end
