# frozen_string_literal: true

require "tmpdir"
require "digest"
require "json"
require_relative "minitest_helper"
require_relative "../../dilla/dilla"

class TestDillaRenderAudit < Minitest::Test
  def write_fixture(directory)
    path = File.join(directory, "audit-fixture.wav")
    mix = Dilla::Stereo.new(4_410)
    mix.l.each_index do |index|
      sample = Math.sin(2.0 * Math::PI * 440 * index / Dilla::SAMPLE_RATE) * 0.1
      mix.l[index] = mix.r[index] = sample
    end
    Dilla::Wav.write_16bit(path, mix)

    quality = {
      "engine" => "dilla #{Dilla::VERSION}", "duration_s" => 0.1,
      "peak_dbfs" => -20.0, "rms_dbfs" => -23.0, "crest_db" => 3.0,
      "lufs_estimate" => -22.0, "stem_energy_share" => { "drums" => 1.0 }
    }
    session = {
      "engine" => "dilla #{Dilla::VERSION}", "seed" => 1234,
      "progression" => { "id" => "audit_fixture", "bpm" => 92 },
      "bars" => 2, "performer" => { "id" => "fixture" },
      "drums" => "boom_bap", "groove_profile" => "dilla_shadow",
      "arrangement" => [ { "section" => "A", "bars" => 2 } ]
    }
    midi_path = File.join(directory, "audit-fixture.mid")
    track = "\x00\xff\x2f\x00".b
    midi = ["MThd", 6, 1, 1, 480].pack("A4Nnnn") + ["MTrk", track.bytesize].pack("A4N") + track
    File.binwrite(midi_path, midi)

    mp3_path = File.join(directory, "audit-fixture.mp3")
    File.binwrite(mp3_path, "ID3\x04\x00\x00".b + ("\x00" * 128))

    provenance = {
      "engine" => "dilla", "version" => Dilla::VERSION, "seed" => 1234,
      "render" => {
        "wav" => path, "bytes" => File.size(path),
        "sha256" => Digest::SHA256.file(path).hexdigest
      },
      "files" => {
        "midi" => { "path" => midi_path, "bytes" => File.size(midi_path), "sha256" => Digest::SHA256.file(midi_path).hexdigest },
        "mp3" => { "path" => mp3_path, "bytes" => File.size(mp3_path), "sha256" => Digest::SHA256.file(mp3_path).hexdigest }
      }
    }
    {
      "quality" => quality, "session" => session, "provenance" => provenance
    }.each do |name, data|
      Dilla.atomic_write(File.join(directory, "audit-fixture.#{name}.json"), JSON.pretty_generate(data))
    end
    path
  end

  test "technical pass stays inconclusive until a person auditions the render" do
    Dir.mktmpdir("dilla-audit-") do |directory|
      path = write_fixture(directory)
      report = Dilla.audit_render(path)

      assert_equal "PASS", report.fetch("technical_state")
      assert_equal "INCONCLUSIVE", report.fetch("state")
      assert_equal "NOT_PERFORMED", report.dig("manual_audition", "status")
      assert_equal 1234, report.dig("session", "seed")
      assert_equal 44_100, report.dig("audio", "sample_rate")
      assert File.file?(report.fetch("report_path"))
      assert_equal 6, report.dig("manual_audition", "checklist").length
      assert_equal "PASS", report.fetch("checks").find { |row| row["name"] == "midi_structure" }.fetch("state")
      assert_equal "PASS", report.fetch("checks").find { |row| row["name"] == "mp3_frame" }.fetch("state")
    end
  end

  test "a WAV whose checksum disagrees with provenance fails the audit" do
    Dir.mktmpdir("dilla-audit-") do |directory|
      path = write_fixture(directory)
      provenance_path = File.join(directory, "audit-fixture.provenance.json")
      provenance = JSON.parse(File.read(provenance_path))
      provenance["render"]["sha256"] = "0" * 64
      Dilla.atomic_write(provenance_path, JSON.pretty_generate(provenance))

      report = Dilla.audit_render(path)
      assert_equal "FAIL", report.fetch("technical_state")
      assert_equal "FAIL", report.fetch("state")
      assert_equal "FAIL", report.fetch("checks").find { |row| row["name"] == "wav_sha256" }.fetch("state")
    end
  end

  test "the audit refuses to overwrite its report unless requested" do
    Dir.mktmpdir("dilla-audit-") do |directory|
      path = write_fixture(directory)
      Dilla.audit_render(path)
      assert_raises(Errno::EEXIST) { Dilla.audit_render(path) }
      assert_equal "PASS", Dilla.audit_render(path, overwrite: true).fetch("technical_state")
    end
  end
end
