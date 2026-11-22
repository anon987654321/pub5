# frozen_string_literal: true

require_relative "test_helper"
require "cli/welcome"

# The first line of a session is read from live state, so two different moments say two different things.
class TestCliWelcome < Minitest::Test
  def test_the_line_names_the_time_and_the_last_session
    in_root do |root|
      FileUtils.mkdir_p(File.join(root, ".master"))
      last = Time.new(2026, 10, 22, 21, 0, 0)
      File.write(
        File.join(root, ".master", "session.json"),
        JSON.generate("ts" => last.to_i, "name" => "how does one avoid depression?")
      )

      line = Master::CLI::Welcome.line(root, now: last + (3 * 3600))

      assert_equal "00:00, last session 3h ago", line
      refute_includes line, "depression"
      refute_includes line, "avoid"
    end
  end

  def test_a_first_session_says_only_the_time
    in_root do |root|
      assert_equal "09:30", Master::CLI::Welcome.line(root, now: Time.new(2026, 10, 23, 9, 30, 0))
    end
  end

  def test_greeting_context_does_not_export_the_last_message
    in_root do |root|
      FileUtils.mkdir_p(File.join(root, ".master"))
      File.write(
        File.join(root, ".master", "session.json"),
        JSON.generate("ts" => Time.new(2026, 10, 22).to_i,
                      "messages" => [{ "role" => "user", "content" => "how does one avoid depression?" }])
      )

      context = Master::CLI::Welcome.context(root, now: Time.new(2026, 10, 23, 9, 30, 0))

      refute context.key?(:last_message)
      refute_includes context.values.join(" "), "depression"
    end
  end

  def in_root(&) = Dir.mktmpdir(&)
end
