# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../MASTER/tools/rails/layout_drift_audit"

class LayoutDriftAuditTest < Minitest::Test
  def audit
    @audit ||= Operator::LayoutDriftAudit.new(root: Dir.tmpdir)
  end

  def test_feed_list_scanner_masks_erb_output_before_finding_tag_end
    source = <<~ERB
      <ul role="list" class="feed_list<%= size > 1 ? " feed-grid" : "" %>">
        <li>one</li>
      </ul>
    ERB

    tags = audit.feed_list_open_tags(source)

    assert_equal 1, tags.length
    assert_match(/role="list"/, tags.first)
    assert_match(/feed_list/, tags.first)
  end

  def test_feed_list_scanner_reports_missing_list_role
    source = '<ul class="feed_list"><li>one</li></ul>'

    assert_equal 1, audit.feed_list_violations(source).length
  end

  def test_feed_list_scanner_accepts_role_before_dynamic_attributes
    source = '<ul role="list" class="feed_list<%= dynamic_class %>">'

    assert_empty audit.feed_list_violations(source)
  end

  def test_only_real_post_list_items_receive_block_boxes
    css = <<~SCSS
      .feed_list > li { display: contents; }
      .feed_list.post-card-list > li {
        display: block;
        min-inline-size: 0;
      }
    SCSS

    assert_includes css, ".feed_list.post-card-list > li"
    assert_match(/\.feed_list\.post-card-list > li\s*\{\s*display:\s*block;/, css)
  end

  def repository_audit
    @repository_audit ||= Operator::LayoutDriftAudit.new(root: File.expand_path("../..", __dir__))
  end

  def test_vertical_front_pages_have_primary_headings
    findings = repository_audit.run
    %w[brgen amber marketplace dating tv maps takeaway radio messenger bsdports mrdamascy].each do |vertical|
      finding = findings.find { |item| item.code == "vertical.#{vertical}.primary_heading" }
      assert finding, "missing heading audit for #{vertical}"
      assert_equal "PASS", finding.status, finding.message
    end
  end

  def test_shared_post_updates_do_not_touch_post_rows
    findings = repository_audit.run
    %w[post_card.root_identity post_card.brgen_vote_event post_card.brgen_vote_no_post_touch
       post_card.brgen_vote_only_replace post_card.brgen_vote_score_refresh
       post_card.brgen_comment_count_event post_card.brgen_comment_no_post_touch].each do |code|
      finding = findings.find { |item| item.code == code }
      assert finding, "missing shared-post audit for #{code}"
      assert_equal "PASS", finding.status, finding.message
    end
  end

  def test_report_marks_browser_and_runtime_evidence_as_not_run
    Dir.mktmpdir do |root|
      report = Operator::LayoutDriftAudit.new(root:)
      report.run

      assert_includes report.findings.map(&:code), "rendered_visual"
      assert_includes report.findings.map(&:code), "runtime_suites"
      assert_equal 2, report.findings.count { |finding| finding.status == "NOT_RUN" }
    end
  end
end
