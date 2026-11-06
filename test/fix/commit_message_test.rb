# frozen_string_literal: true

require_relative "fix_helper"

# Moved from pub4 MASTER/test/test_fix_commit_message.rb (7600739e08,
# 94ff01dcbf). /fix committed "Fix_loop: fast-fix [pass 1]" and "ABC_SIZE in
# baymard_law.rb" with a one-line body; a three-Law subject lost its file.
class FixCommitMessageTest < Minitest::Test
  Message = Fix::CommitMessage
  TRAILERS = { law: "ABC_SIZE", measured: "1 -> 0", writer: "operator", proof: "rescan" }.freeze

  def repair(laws, file = "laws/pub4/baymard_law.rb")
    Message.repair(laws:, file:, line: 23, before: 1, after: 0, writer: "operator", proof: "rescan")
  end

  def test_the_old_subjects_are_refused
    ["Fix_loop: fast-fix [pass 1]", "ABC_SIZE in baymard_law.rb\n\nABC_SIZE baymard_law.rb:23"].each do |old|
      refute_empty Message.problems(old), old
    end
  end

  def test_a_repair_and_an_autofix_message_satisfy_the_format
    [repair(["ABC_SIZE"]), Message.autofix(paths: %w[a.rb b.rb], laws: %w[TRAILING_WHITESPACE], writer: "operator")]
      .each do |message|
        assert_empty Message.problems(message), message
        assert message.lines.all? { |line| line.chomp.size <= 72 }, message
        assert Message.own?(message)
        %w[Law Measured Writer Proof].each { |key| assert_match(/^#{key}: \S/, message) }
      end
  end

  def test_a_long_subject_is_cut_at_a_word
    message = Message.compose("Repair #{'VERY_LONG_LAW_NAME ' * 6}in file.rb", what: "Changed it", why: "It was wrong",
                                                                                trailers: TRAILERS)

    assert_operator message.lines.first.chomp.size, :<=, 72
    assert_empty Message.problems(message)
  end

  def test_a_many_law_repair_keeps_the_file_and_names_it_from_the_repo_root
    text = repair(%w[MOBILE_FIRST NO_ASCII_LINE_ART SMALL_FILES], "rails/brgen/app/assets/stylesheets/_brgen_core_shell.scss")

    assert_equal "Repair MOBILE_FIRST and 2 more in _brgen_core_shell.scss\n", text.lines.first
    assert_includes text.gsub("\n", " "), "rewrote rails/brgen/app/assets/stylesheets/_brgen_core_shell.scss"
    assert_includes text.gsub("\n", " "), "MOBILE_FIRST, NO_ASCII_LINE_ART and SMALL_FILES findings"
  end

  def test_no_message_carries_the_words_of_a_refactor_claim
    refute_match(/\b(extract|refactor)/i, repair(["ABC_SIZE"]))
  end
end
