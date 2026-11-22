# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "yaml"
require_relative "minitest_helper"
require_relative "../../lora/migrate_local"

class TestLoraLocalMigration < Minitest::Test
  Migration = Studio::Lora::LocalMigration

  def with_repositories
    Dir.mktmpdir("studio-lora-migration-") do |root|
      source = File.join(root, "pub4")
      destination = File.join(root, "pub5", "STUDIO", "lora")
      FileUtils.mkdir_p(File.join(source, ".git"))
      yield source, destination
    end
  end

  def write_legacy_subject(source, name: "johann", include_sources: false)
    subject = File.join(source, "STUDIO", "replicate", "lora", name)
    FileUtils.mkdir_p(File.join(subject, "weights", name), mode: 0o700)
    env = File.join(subject, "subject.env")
    File.write(env, "TRIGGER=#{name}_lora\nMODEL=#{name}\n", mode: "w", perm: 0o600)
    manifest = File.join(subject, "weights", name, "replicate_training.json")
    File.write(manifest, JSON.generate("version" => "owner/model:" + ("a" * 64)),
               mode: "w", perm: 0o600)
    dataset = File.join(subject, "dataset")
    FileUtils.mkdir_p(dataset)
    File.write(File.join(dataset, "photo.jpg"), "must not migrate")
    if include_sources
      sources = File.join(subject, "sources")
      FileUtils.mkdir_p(sources, mode: 0o700)
      File.chmod(0o700, sources)
      File.write(File.join(sources, "portrait.jpg"), "approved source", mode: "w", perm: 0o600)
    end
    subject
  end

  def write_consent(destination, subject:, source_sets: [])
    directory = File.join(destination, subject)
    evidence = File.join(directory, "evidence")
    FileUtils.mkdir_p(evidence, mode: 0o700)
    File.chmod(0o700, evidence)

    subject_evidence = File.join(evidence, "subject.txt")
    File.write(subject_evidence, "synthetic subject authority", mode: "w", perm: 0o600)
    source_evidence = {}
    source_sets.each_with_index do |source, index|
      filename = "source-#{index}.txt"
      File.write(File.join(evidence, filename), "synthetic source authority", mode: "w", perm: 0o600)
      source_evidence[source] = {
        "granted_by" => "synthetic rights holder",
        "granted_on" => "2026-11-19",
        "covers" => %w[generation_use provider_processing],
        "stored_at" => "evidence/#{filename}",
      }
    end

    record = {
      "schema" => 1,
      "subject" => subject,
      "subject_consent" => {
        "likeness_generation" => true,
        "provider_processing" => true,
        "evidence" => {
          "granted_by" => "synthetic subject authority",
          "granted_on" => "2026-11-19",
          "covers" => %w[likeness_generation provider_processing],
          "stored_at" => "evidence/subject.txt",
        },
      },
      "source_rights" => {
        "generation_use" => true,
        "provider_processing" => true,
        "evidence" => source_evidence,
      },
    }
    path = File.join(directory, "consent.yml")
    File.write(path, YAML.dump(record), mode: "w", perm: 0o600)
    File.chmod(0o600, path)
  end

  def test_dry_run_is_read_only_and_lists_only_runtime_inputs
    with_repositories do |source, destination|
      write_legacy_subject(source)
      result = Migration.new(source_checkout: source, destination_root: destination).migrate("johann")

      assert_equal "REVIEW", result.fetch("status")
      assert_equal %w[subject.env weights/johann/replicate_training.json],
                   result.fetch("planned").map { |item| item.fetch("path") }.sort
      refute File.exist?(File.join(destination, "johann"))
      assert_equal "must not migrate",
                   File.read(File.join(source, "STUDIO", "replicate", "lora", "johann", "dataset", "photo.jpg"))
    end
  end

  def test_apply_copies_only_pinned_metadata_and_seals_the_destination
    with_repositories do |source, destination|
      write_legacy_subject(source)
      FileUtils.mkdir_p(File.join(destination, "johann"), mode: 0o700)
      write_consent(destination, subject: "johann")

      result = Migration.new(source_checkout: source, destination_root: destination, apply: true).migrate("johann")

      assert_equal "COPIED", result.fetch("status")
      env = File.join(destination, "johann", "subject.env")
      manifest = File.join(destination, "johann", "weights", "johann", "replicate_training.json")
      assert File.file?(env)
      assert File.file?(manifest)
      assert_equal 0o600, File.stat(env).mode & 0o777
      assert_equal 0o600, File.stat(manifest).mode & 0o777
      refute File.exist?(File.join(destination, "johann", "dataset"))
    end
  end

  def test_source_images_need_explicit_source_rights_and_are_copied_private
    with_repositories do |source, destination|
      write_legacy_subject(source, include_sources: true)
      directory = File.join(destination, "johann")
      FileUtils.mkdir_p(directory, mode: 0o700)
      write_consent(destination, subject: "johann", source_sets: ["subject_sources"])

      result = Migration.new(
        source_checkout: source, destination_root: destination,
        apply: true, include_sources: true
      ).migrate("johann")

      assert_equal "COPIED", result.fetch("status")
      image = File.join(directory, "sources", "portrait.jpg")
      assert_equal "approved source", File.read(image)
      assert_equal 0o600, File.stat(image).mode & 0o777
      assert_equal 0o700, File.stat(File.dirname(image)).mode & 0o777
    end
  end

  def test_symlinked_subject_root_is_blocked_not_skipped
    with_repositories do |source, destination|
      real = File.join(source, "real-subject")
      FileUtils.mkdir_p(File.join(real, "weights", "johann"), mode: 0o700)
      link = File.join(source, "STUDIO", "replicate", "lora", "johann")
      FileUtils.mkdir_p(File.dirname(link))
      File.symlink(real, link)

      report = Migration.new(source_checkout: source, destination_root: destination).migrate("johann")

      assert_equal "BLOCKED", report.fetch("status")
      assert_match(/symlink/, report.fetch("reason"))
    end
  end

  def test_apply_without_a_valid_private_consent_record_copies_nothing
    with_repositories do |source, destination|
      write_legacy_subject(source)
      result = Migration.new(source_checkout: source, destination_root: destination, apply: true).migrate("johann")

      assert_equal "BLOCKED", result.fetch("status")
      refute File.exist?(File.join(destination, "johann", "subject.env"))
    end
  end

  def test_interrupted_apply_keeps_every_destination_file_it_already_created
    with_repositories do |source, destination|
      legacy = write_legacy_subject(source, include_sources: true)
      subject_destination = File.join(destination, "johann")
      FileUtils.mkdir_p(subject_destination, mode: 0o700)
      migration = Migration.new(
        source_checkout: source, destination_root: destination,
        apply: true, include_sources: true
      )
      entries = migration.send(:planned_entries, legacy)
      File.delete(File.join(legacy, "sources", "portrait.jpg"))

      error = assert_raises(Migration::Error) do
        migration.send(:apply_entries, subject_destination, entries)
      end

      env = File.join(subject_destination, "subject.env")
      manifest = File.join(subject_destination, "weights", "johann", "replicate_training.json")
      partial_source = File.join(subject_destination, "sources", "portrait.jpg")
      assert File.file?(env), "a previous successful copy must remain"
      assert File.file?(manifest), "a previous successful model descriptor must remain"
      assert File.file?(partial_source), "the failed source destination must remain visible for recovery"
      assert_equal "", File.read(partial_source)
      assert_match(/retained 3 destination path\(s\)/, error.message)
      assert_match(/no files were deleted/, error.message)
    end
  end

  def test_conflicts_and_symlinks_are_never_overwritten_or_followed
    with_repositories do |source, destination|
      legacy = write_legacy_subject(source, include_sources: true)
      directory = File.join(destination, "johann")
      FileUtils.mkdir_p(directory, mode: 0o700)
      existing = File.join(directory, "subject.env")
      File.write(existing, "newer", mode: "w", perm: 0o600)

      conflict = Migration.new(source_checkout: source, destination_root: destination).migrate("johann")
      assert_equal "BLOCKED", conflict.fetch("status")
      assert_equal "newer", File.read(existing)

      source_dir = File.join(legacy, "sources")
      File.symlink(existing, File.join(source_dir, "linked.jpg"))
      blocked = Migration.new(source_checkout: source, destination_root: destination,
                                include_sources: true).migrate("johann")
      assert_equal "BLOCKED", blocked.fetch("status")
      assert_match(/symlink/, blocked.fetch("reason"))
    end
  end
end
