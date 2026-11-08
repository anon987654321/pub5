# frozen_string_literal: true

require_relative "../welcome"

module Master
  module CLI
    class Session
      private

      # The live-state welcome is enough at startup. A second model request can
      # occupy the same provider lane as the operator's first turn.
      # Keep the personal greeting available as an explicit opt-in.
      # MASTER_GREETING=1 enables it.
      def greet_from_model
        return unless ENV["MASTER_GREETING"] == "1" && $stdout.tty?

        Thread.new { deliver_greeting }
      end

      # A greeting that arrives after the operator has started talking is stale, and it printed onto the end of
      # the first reply ("...or mainly you?Late for hard conversations, Johann."), so it stands down.
      def deliver_greeting
        text = @refs.agent.ask_once(greeting_prompt, law: false).to_s.strip
        return if text.empty? || @user_active || !@last_input.to_s.empty? || @pipeline_thread

        terminal_puts(@refs.renderer.render(text.lines.first.to_s.strip, mode: :dim))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.greeting", event_bus: @refs.bus)
      end

      def greeting_prompt
        context = Master::CLI::Welcome.context(Master::ROOT)
        language = "English"

        <<~PROMPT
          You are MASTER, greeting the operator as a terminal session opens. One natural line of at most
          twelve words, in #{language}. Be warm without being familiar or theatrical. Do not quote, infer,
          or refer to earlier conversation, personal history, mood, or private topics. Do not ask a question.

          Now: #{context[:time]}. #{context[:line]}.
        PROMPT
      end
    end
  end
end
