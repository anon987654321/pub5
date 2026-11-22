# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "digest"
require "base64"
require "json"
require "fileutils"
require_relative "../lib/io/document_archive"

class DocumentArchiveTest < Minitest::Test
  class FakeAgent
    attr_reader :calls

    def initialize
      @calls = []
    end

    def ask_once(prompt, image: nil, **_options)
      @calls << { prompt:, image: }
      image ? "TRANSCRIPTION\nDear friend,\nA handwritten page.\nOBSERVATIONS\nNo explicit date." :
        "## Chronology\n\nPage 1 is unresolved; no date is established."
    end
  end

  def write_page(path, bytes = "\x89PNG\r\n\x1A\nsource-image".b)
    File.binwrite(path, bytes)
    Digest::SHA256.file(path).hexdigest
  end

  def test_transcribes_each_image_separately_and_preserves_originals
    Dir.mktmpdir("document-archive") do |home|
      source = File.join(home, "photos")
      FileUtils.mkdir_p(source)
      first = File.join(source, "page-a.png")
      second = File.join(source, "page-b.png")
      first_sha = write_page(first)
      second_sha = write_page(second, "\x89PNG\r\n\x1A\nsecond-image".b)
      File.utime(Time.utc(2020, 1, 1), Time.utc(2020, 1, 1), first)
      File.utime(Time.utc(2021, 1, 1), Time.utc(2021, 1, 1), second)
      agent = FakeAgent.new
      archive = Master::Io::DocumentArchive.new(agent:, home:)

      result = archive.analyze(directory: "photos")

      assert_predicate result, :ok?
      value = result.value!
      assert_equal "complete", value.fetch(:status)
      assert_equal 2, value.fetch(:transcribed)
      assert_equal 3, agent.calls.size
      assert_equal File.binread(first), Base64.strict_decode64(agent.calls[0].fetch(:image).fetch(:data))
      assert_equal File.binread(second), Base64.strict_decode64(agent.calls[1].fetch(:image).fetch(:data))
      assert_equal "image/png", agent.calls[0].fetch(:image).fetch(:mime)
      refute agent.calls[0].fetch(:image).key?(:path), "the provider receives the verified bytes, not a host filesystem path"
      assert_includes agent.calls[0].fetch(:prompt), "file timestamp"
      assert_nil agent.calls.last.fetch(:image)
      assert File.file?(value.fetch(:report_path))
      assert File.file?(value.fetch(:manifest_path))
      assert_equal 0o600, File.stat(value.fetch(:report_path)).mode & 0o777
      manifest = JSON.parse(File.read(value.fetch(:manifest_path)))
      assert_equal false, manifest.fetch("originals_modified")
      assert_equal [first_sha, second_sha], manifest.fetch("pages").map { |page| page.fetch("sha256") }
      assert_equal first_sha, Digest::SHA256.file(first).hexdigest
      assert_equal second_sha, Digest::SHA256.file(second).hexdigest
      assert_includes File.read(value.fetch(:report_path)), "Page-level transcriptions"
    end
  end

  def test_reports_unsupported_document_formats_instead_of_transforming_them
    Dir.mktmpdir("document-archive") do |home|
      source = File.join(home, "photos")
      FileUtils.mkdir_p(source)
      File.write(File.join(source, "letter.pdf"), "%PDF-1.4")
      File.write(File.join(source, "letter.heic"), "heic")
      result = Master::Io::DocumentArchive.new(agent: FakeAgent.new, home:).analyze(directory: "photos")

      assert_predicate result, :err?
      assert_equal :validation, result.category
      assert_match(/no supported images/, result.message)
    end
  end

  def test_refuses_a_source_directory_outside_the_operator_home
    Dir.mktmpdir("document-home") do |home|
      Dir.mktmpdir("outside-home") do |outside|
        result = Master::Io::DocumentArchive.new(agent: FakeAgent.new, home:).analyze(directory: outside)

        assert_predicate result, :err?
        assert_equal :policy, result.category
        assert_match(/inside the local home directory/, result.message)
      end
    end
  end

  def test_page_limit_is_bounded_and_the_omitted_count_is_reported
    Dir.mktmpdir("document-archive") do |home|
      source = File.join(home, "photos")
      FileUtils.mkdir_p(source)
      3.times { |index| write_page(File.join(source, "page-#{index}.png")) }
      agent = FakeAgent.new
      result = Master::Io::DocumentArchive.new(agent:, home:).analyze(directory: "photos", max_pages: 1)

      assert_predicate result, :ok?
      assert_equal 1, result.value!.fetch(:pages)
      assert_equal 2, result.value!.fetch(:omitted)
      assert_includes File.read(result.value!.fetch(:report_path)), "Pages omitted by limit: 2"
      assert_equal 2, agent.calls.size
    end
  end

  def test_refuses_a_symlinked_output_directory_without_chmodding_its_target
    Dir.mktmpdir("document-output-home") do |home|
      Dir.mktmpdir("document-output-target") do |outside|
        source = File.join(home, "photos")
        FileUtils.mkdir_p(source)
        write_page(File.join(source, "page.png"))
        output = File.join(home, ".local", "share", "master", "document-archives")
        FileUtils.mkdir_p(File.dirname(output))
        original_mode = File.stat(outside).mode & 0o777
        File.symlink(outside, output)
        result = Master::Io::DocumentArchive.new(agent: FakeAgent.new, home:).analyze(directory: "photos")

        assert_predicate result, :err?
        assert_equal :infrastructure, result.category
        assert_equal original_mode, File.stat(outside).mode & 0o777
        assert_empty Dir.children(outside)
      end
    end
  end

end
