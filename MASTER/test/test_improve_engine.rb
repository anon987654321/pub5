# frozen_string_literal: true

require_relative "test_helper"
require "fix/improve"
require "fileutils"

# The elevation engine: /fix improves, ideates and restructures. These tests
# pin the engine's contract — findings in the improvement shape, ideas in the
# ledger, proposals that name both endpoints — without touching the repo.
class TestImproveEngine < Minitest::Test
  def setup
    @root = File.join(Dir.tmpdir, "improve_test_#{Process.pid}")
    %w[lib docs].each { |dir| FileUtils.mkdir_p(File.join(@root, dir)) }
    @engine = Master::Fix::Improve::Engine.new(root: @root)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write(path, text)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, text)
    full
  end

  def test_elevation_findings_use_the_nonblocking_warning_severity
    assert_equal :warning, Master::Fix::Improve::SEVERITY
    assert_equal 1, Master::Fix::Severity.rank(Master::Fix::Improve::SEVERITY)
  end

  def test_elevates_a_long_method_as_an_improvement_finding
    path = write("lib/wide.rb", "# frozen_string_literal: true\nclass Wide\n" +
      "  def claimable\n" + (1..60).map { |i| "    x#{i} = #{i}" }.join("\n") + "\n  end\nend\n")
    findings = @engine.elevate(files: [path])
    assert findings.any?, "a 60-line method must be elevated"
    finding = findings.first
    assert_equal Master::Fix::Improve::LAW_ID, finding[:law]
    assert_equal :improvement, finding[:kind]
    assert finding[:message].include?("long_method")
    assert finding[:fix].length > 20
  end

  def test_business_plan_html_and_markdown_are_prose_elevation_surfaces
    assert_equal :prose, Master::Fix::Improve::Domains.domain_for("BIZ/plan.html")
    assert_equal :prose, Master::Fix::Improve::Domains.domain_for("BIZ/research/plan.md")
    assert_equal :visual, Master::Fix::Improve::Domains.domain_for("RAILS/brgen/app/views/posts/index.html.erb")
    assert_equal :visual, Master::Fix::Improve::Domains.domain_for("RAILS/brgen/app/assets/stylesheets/posts.scss")
  end

  def test_audio_files_are_not_claimed_as_machine_assessed_music
    assert_nil Master::Fix::Improve::Domains.domain_for("STUDIO/dilla/blue-hour.wav")
    assert_nil Master::Fix::Improve::Domains.domain_for("STUDIO/dilla/blue-hour.flac")
    assert_equal :music, Master::Fix::Improve::Domains.domain_for("STUDIO/dilla/blue-hour.sco")
  end

  def test_improvement_coverage_reports_only_files_with_a_real_domain_probe
    score = Master::Fix::Improve::Domains.coverage(files: [
      write("lib/reader.rb", "# frozen_string_literal: true\n"),
      write("bin/start.sh", "#!/bin/sh\n"),
      write("music/blue-hour.wav", "not audio"),
      write("docs/README.md", "# Read me\n"),
    ])

    assert_equal 4, score[:files_seen]
    assert_equal 2, score[:measured_files]
    assert_equal %w[code prose], score[:domains]
  end

  def test_javascript_is_a_measured_code_surface_and_reports_precise_lines
    path = write("lib/entry.js", "const answer = 42;")
    findings = @engine.elevate(files: [path])

    finding = findings.find { |row| row[:message].include?("missing_final_newline") }
    refute_nil finding
    assert_equal 1, finding[:line]
    assert_equal "lib/entry.js", finding[:file]
  end

  def test_yaml_duplicate_keys_are_identified_as_structural_polish
    path = write("docs/settings.yml", "feature:\n  enabled: true\n  enabled: false\n")
    findings = @engine.elevate(files: [path])

    finding = findings.find { |row| row[:message].include?("duplicate_yaml_key") }
    refute_nil finding
    assert_equal 3, finding[:line]
    assert_equal :improvement, finding[:kind]
  end

  def test_markdown_heading_hierarchy_and_generic_links_are_reported
    path = write("docs/guide.md", "# Guide\n\n### Details\n\n[click here](https://example.test)\n")
    findings = @engine.elevate(files: [path])

    assert findings.any? { |row| row[:message].include?("heading_level_skip") }, findings.inspect
    assert findings.any? { |row| row[:message].include?("generic_link_text") }, findings.inspect
  end

  def test_html_image_and_icon_controls_need_accessible_names
    FileUtils.mkdir_p(File.join(@root, "docs", "views"))
    path = write("docs/views/index.html.erb",
      '<img src="coat.jpg"><form><button></button></form><button><svg></svg></button>' +
      '<a href="/next"><i class="icon"></i></a><a href="/empty"></a><div tabindex="2">skip</div>')

    findings = Master::Fix::Improve::Domains.scan(root: @root, files: [path])
    signals = findings.map(&:signal)

    assert_includes signals, "image_without_alt"
    assert_includes signals, "icon_only_button"
    assert_includes signals, "icon_only_link"
    assert_includes signals, "empty_button"
    assert_includes signals, "empty_link"
    assert_includes signals, "positive_tabindex"
    assert_includes signals, "implicit_form_button_type"
  end

  def test_polish_coverage_exposes_per_domain_counts
    files = [
      write("lib/main.js", "const main = true;\n"),
      write("docs/guide.md", "# Guide\n"),
      write("docs/settings.yml", "enabled: true\n"),
      write("docs/views/page.html", "<main>Page</main>\n"),
    ]
    coverage = Master::Fix::Improve::Domains.coverage(files:)

    assert_equal 4, coverage[:measured_files]
    assert_equal({ "code" => 1, "prose" => 1, "structure" => 1, "visual" => 1 }, coverage[:domain_counts])
  end

  def test_discovers_interaction_and_recovery_opportunities_in_javascript
    path = write("lib/request.js",
      "export async function save() { window.confirm('Save?'); return fetch('/api'); }\n")
    findings = Master::Fix::Improve::Domains.scan(root: @root, files: [path])
    signals = findings.map(&:signal)

    assert_includes signals, "native_dialog"
    assert_includes signals, "fetch_without_visible_error_path"
  end

  def test_discovers_keyboard_focus_and_reduced_motion_gaps
    path = write("docs/views/controls.scss", "button { outline: none; transition: opacity .2s; }\n")
    findings = Master::Fix::Improve::Domains.scan(root: @root, files: [path])
    signals = findings.map(&:signal)

    assert_includes signals, "focus_outline_removed"
    assert_includes signals, "motion_without_reduced_motion_path"
  end

  def test_discovers_missing_document_language_title_and_form_labels
    path = write("docs/views/form.html.erb",
      '<!doctype html><html><head></head><body><input id="email" type="email"><button></button></body></html>')
    findings = Master::Fix::Improve::Domains.scan(root: @root, files: [path])
    signals = findings.map(&:signal)

    assert_includes signals, "document_language_missing"
    assert_includes signals, "document_title_missing"
    assert_includes signals, "form_control_without_label"
    assert_includes signals, "empty_button"
  end

  def test_broken_relative_markdown_links_are_reported_but_existing_links_are_not
    existing = write("docs/known.md", "# Known\n")
    broken = write("docs/guide.md", "[known](known.md) [missing](missing.md)\n")
    findings = Master::Fix::Improve::Domains.scan(root: @root, files: [broken])
    broken_link = findings.find { |row| row.signal == "broken_relative_link" }

    refute_nil broken_link
    assert_equal 1, broken_link.line
    assert File.file?(existing)
    assert_equal [], Master::Fix::Improve::Domains.scan(root: @root, files: [existing])
  end

  def test_polish_coverage_names_quality_areas_and_external_evidence_boundaries
    files = [
      write("lib/main.js", "const main = true;\n"),
      write("docs/guide.md", "# Guide\n"),
      write("docs/settings.yml", "enabled: true\n"),
      write("docs/views/page.html", "<main>Page</main>\n"),
    ]
    coverage = Master::Fix::Improve::Domains.coverage(files:)

    assert_includes coverage[:quality_areas], "accessibility"
    assert_includes coverage[:quality_areas], "interaction"
    assert_includes coverage[:quality_areas], "provenance"
    assert_includes coverage[:external_review_areas], "assistive_technology"
    assert_includes coverage[:external_review_areas], "human_listening"
    assert_includes coverage[:external_review_areas], "user_acceptance"
  end

  def test_improvement_receipt_includes_quality_and_external_review_scope
    files = [
      write("lib/main.js", "const ready = true;\n"),
      write("docs/guide.md", "# Guide\n"),
      write("docs/settings.yml", "enabled: true\n"),
      write("docs/views/page.scss", "a { transition: opacity .2s; }\n"),
    ]
    coverage = Master::Fix::Improve::Domains.coverage(files:)

    assert_includes coverage[:quality_areas], "interaction"
    assert_includes coverage[:quality_areas], "provenance"
    assert_includes coverage[:external_review_areas], "rendered_composition"
    assert_includes coverage[:external_review_areas], "assistive_technology"
  end

  def test_elevates_prose_placeholders
    path = write("docs/README.md", "# X\n\n" + ("word " * 80) + "\n\nTODO: write this later.\n")
    findings = @engine.elevate(files: [path])
    assert findings.any? { |f| f[:message].include?("placeholder") }, findings.inspect
  end

  def test_invalid_yaml_is_reported_without_silently_aborting_other_polish_checks
    path = write("docs/broken.yml", "enabled: [true, false\n")
    findings = Master::Fix::Improve::Domains.scan(root: @root, files: [path])

    finding = findings.find { |row| row.signal == "invalid_yaml_structure" }
    refute_nil finding
    assert_operator finding.line, :>, 0
  end

  def test_empty_studio_music_metadata_is_a_structural_polish_finding
    path = write("STUDIO/dilla/session.yml", "bpm:\n")
    findings = Master::Fix::Improve::Domains.scan(root: @root, files: [path])

    finding = findings.find { |row| row.signal == "empty_music_field" }
    refute_nil finding
    assert_equal :structure, finding.domain
    assert_equal 1, finding.line
  end

  def test_elevates_unmarked_scores_in_the_music_domain
    path = write("docs/piece.sco", "i1 0 2 0.5\ni1 2 2 0.4\n")
    findings = @engine.elevate(files: [path])
    assert findings.any? { |f| f[:message].include?("unmarked_score") }, findings.inspect
  end

  def test_elevate_returns_at_most_two_steps_per_domain
    files = 5.times.map do |i| write("lib/wide#{i}.rb", "# frozen_string_literal: true\nclass W#{i}\n" +
      "  def run\n" + (1..60).map { |j| "    x#{j} = #{j}" }.join("\n") + "\n  end\nend\n") end
    findings = @engine.elevate(files:)
    code_findings = findings.count { |f| f[:message].include?("elevation[code]") }
    assert_operator code_findings, :<=, 2
  end

  def test_ideate_writes_the_ledger_the_next_run_reads
    write("README.md", "# Root\n\n" + ("word " * 80))
    ideas = @engine.ideate(files: [File.join(@root, "README.md")])
    ledger = File.join(@root, Master::Fix::Improve::Ideate::LEDGER_PATH)
    assert File.file?(ledger), "ideas must survive in #{Master::Fix::Improve::Ideate::LEDGER_PATH}"
    data = JSON.parse(File.read(ledger))
    assert_equal Master::Fix::Improve::Ideate::SCHEMA, data["schema"]
  end


  def test_live_ruby_architecture_report_does_not_reappear_as_ideation
    path = write("MASTER/lib/convergence/architecture.rb", "module Master; end\n")

    ideas = @engine.ideate(files: [path])

    refute ideas.any? { |idea| idea.source == "persona.newcomer" }, ideas.inspect
  end

  def test_restructure_proposals_name_both_endpoints_and_an_existing_source
    @engine = nil
    lib = File.join(@root, "lib")
    FileUtils.mkdir_p(File.join(lib, "tiny"))
    File.write(File.join(lib, "tiny.rb"), "# frozen_string_literal: true\nclass Tiny\n  def one\n  end\nend\n")
    File.write(File.join(lib, "tiny", "extra.rb"), "# frozen_string_literal: true\n# small helper\nX = 1\n")
    restructure = Master::Fix::Improve::Restructure.new(root: @root)
    proposals = restructure.proposals(files: Dir[File.join(@root, "lib/**/*.rb")])
    skip "no merge target for this layout" if proposals.empty?
    proposal = proposals.first
    assert File.file?(proposal.from)
    refute_empty proposal.to
  end
end
