# frozen_string_literal: true

require_relative "test_helper"

# English is the default; Norwegian only when the person wrote Norwegian.
class TestGreetingLanguage < Minitest::Test
  Language = Master::Voice::Language

  def test_english_and_unclear_text_read_as_english
    assert_equal :en, Language.detect("hi, what time is it in Oslo?")
    assert_equal :en, Language.detect(nil)
  end

  def test_norwegian_reads_as_norwegian
    assert_equal :nb, Language.detect("hei, hva er klokka?")
  end

  def test_the_greeting_names_only_the_language_of_the_last_message
    session = Master::CLI::Session.allocate
    Master::CLI::Welcome.stub(:context, { time: "Monday 23:25", line: "x" }) do
      Master::CLI::Welcome.stub(:read_session, { "messages" => [{ "role" => "user", "content" => "hi there" }] }) do
        prompt = session.send(:greeting_prompt)
        assert_includes prompt, "in\nEnglish."
        refute_includes prompt, "hi there"
      end
      Master::CLI::Welcome.stub(:read_session, { "messages" => [{ "role" => "user", "content" => "hei, hvordan går det?" }] }) do
        prompt = session.send(:greeting_prompt)
        assert_includes prompt, "in\nNorwegian Bokmål."
        refute_includes prompt, "hvordan går det"
      end
    end
  end
end
