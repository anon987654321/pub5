# frozen_string_literal: true

require_relative "../capability_stamp"
require_relative "../../voice/typography"

module Master
  module CLI
    class Session
      private

      def display_result(result:, accumulated:, streamed:, units_console: false)
        case result
        in Master::Result::Ok => ok
          @last_ok = true
          @exit_code = 0
          print_answer_attribution("answered")
          display_ok(ok:, accumulated:, streamed:, units_console:)
        in Master::Result::Err => err
          # A turn the operator cancelled did what was asked; ^C already
          # echoed, so there is nothing to add — and "answered" would lie
          # about a turn no one saw complete.
          return if err.category == :abort

          @last_ok = false
          @exit_code = exit_code_for(err)
          return exit_cli if err.category == :shutdown

          print_answer_attribution("failed")
          print_error(err)
        end
      end

      # One line for a one-line error; its own lines for a structured one. The
      # fold reports as header, turn evidence and summary — flattened into a
      # ribbon and cut mid-word, that evidence was unreadable, which is a
      # second error on top of the first.
      # Structured reports already carry the unit that produced them. Reuse
      # that unit instead of prefixing the whole report with a second err0.
      REPORT_UNIT = /\A([a-z][a-z0-9_]*\d+):\s/

      def print_error(err)
        text = err.message.to_s
        return Master::Trace::Dmesg.status("err0", bounded_line(text)) if text.lines.one?

        unit = text[REPORT_UNIT, 1]
        return Master::Trace::Dmesg.block("err0", text) if unit.nil? || unit == "err0"

        Master::Trace::Dmesg.block(unit, text.sub(/\A#{Regexp.escape(unit)}:\s*/, ""))
      end

      def bounded_line(text)
        Master::Voice::Typography.ellipsis(text.gsub(/\s+/, " ").strip, ERROR_TEXT_MAX_CHARS)
      end

      def display_ok(ok:, accumulated:, streamed:, units_console: false)
        text = streamed ? accumulated : success_text(ok)
        if text.to_s.strip.empty?
          # Detailed dmesg replays a line-turn through the units console, so
          # the empty buffer is empty by construction, not an empty answer.
          # The err0 report lied: a long reply followed "turn completed
          # without output" (Johann's log 2026-11-07).
          return display_units_console_turn(ok) if units_console

          return display_empty_success(ok)
        end
        routine = !streamed && routine_success?(text)
        command = diagnostic_command(@last_input)
        markdown_rendered = false

        if !streamed && command.nil? && !structured_payload?(text) &&
           @refs.renderer.respond_to?(:terminal_markdown)
          text = @refs.renderer.terminal_markdown(text, width: reply_measure)
          markdown_rendered = true
        end

        if streamed
          # The stream already carried every chunk to the operator as it
          # arrived (handle_stream_text prints each one at the cursor). All
          # the display owes the stream here is the row's terminating newline:
          # printing the accumulated buffer again appended a second copy to
          # the first ("Grok 4.7, from xAI.Grok 4.7, from xAI.", Johann's
          # log 2026-11-08).
          terminal_puts unless text.to_s.empty? || text.end_with?("\n")
          text = print_unstreamed_reply(ok, streamed_text: text)
        elsif command
          # Pipeline commands already streamed their live dmesg units. Other
          # commands get their human-readable result attached to their command
          # unit. Explicit JSON payloads remain payloads, not terminal prose.
          unless %w[fix review critique].include?(command)
            if structured_payload?(text)
              terminal_puts(text)
            else
              Master::Trace::Dmesg::Report.print(command, text)
            end
          end
        else
          # The reply replaces its row through the guard: while a draft is
          # edited, the row is cleared and the draft is repainted under it.
          terminal_print("\r\e[K") if $stdout.isatty
          display_prepared_terminal_output(text) if routine
          unless routine
            output = markdown_rendered ? text.chomp : @refs.renderer.measure(text.chomp, width: reply_measure)
            display_prepared_terminal_output(output)
          end
        end

        spoken = spoken_form(text)
        unless Master::Trace::Dmesg.log_voice_active? ||
               Master::Trace::Dmesg.log_voice_spoken_recently?(spoken)
          Master::Voice::Playback.speak(spoken)
        end
        print_fix_activity_footer
        print_previous_question_footer
        print_parallel_errors_footer(ok)
        print_capability_stamp(ok)
      end

      def display_empty_success(ok)
        @last_ok = false
        @exit_code = 2
        Master::Trace::Dmesg.status("err0", "turn completed without output")
        value = ok.value
        Master::Trace::Dmesg.status("err0", "result=#{value.class}") if value
      end

      # The turn's text already reached the operator through the units
      # console; keep the ok bookkeeping and the footers, print no reply.
      # The footers read the turn's Result, not the boolean bookkeeping:
      # print_parallel_errors_footer calls .value on what it is handed, and
      # @last_ok is a boolean - passing it raised "undefined method 'value'
      # for true" out of a queued turn's display, and the queue worker
      # reported the crash (Johann's log 2026-11-08).
      def display_units_console_turn(ok)
        print_fix_activity_footer
        print_previous_question_footer
        print_parallel_errors_footer(ok)
        print_capability_stamp(ok)
      end

      def diagnostic_command(input)
        word = input.to_s.strip.split(/\s+/, 2).first.to_s
        return unless word.start_with?("/") || input.to_s.strip.match?(/\A(?:fix|review|critique)\b/i)

        word.delete_prefix("/").downcase
      end

      def structured_payload?(text)
        stripped = text.to_s.lstrip
        stripped.start_with?("{", "[") && stripped.match?(/[}\]]\s*\z/)
      end

      # A pass report is a log, and reading a log aloud from the top takes
      # longer than the pass did. Its milestones were already spoken as they
      # happened (Session::MILESTONE), so what is left to say is the line that
      # closes it. Anything that is not a report is spoken whole.
      REPORT_FOOTER = /\A[a-z]+\d+: (?:complete|incomplete)\b/

      def spoken_form(text)
        last = text.to_s.lines.map(&:strip).reject(&:empty?).last.to_s
        return text unless text.to_s.lines.size > REPORT_MIN_LINES && last.match?(REPORT_FOOTER)

        last
      end

      REPORT_MIN_LINES = 8

      def reply_measure
        [Master::Voice::Renderer::MEASURE, TTY::Screen.width - 1].min
      rescue StandardError
        Master::Voice::Renderer::MEASURE
      end

      def print_previous_question_footer
        return unless @last_input.to_s.lstrip.start_with?("/fix", "fix ")
        return unless @last_ok

        question = @refs.session.last_user_question(before: @last_input)
        return if question.to_s.empty?

        line = "next0: your previous question - #{question}"
        Master::Trace::Dmesg.status("next0", question)
        # The question is continuity context, not a second reply. Keep it visible
        # so /fix can resume the thread without putting two utterances on the speaker.
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.previous_question_footer", event_bus: @refs.bus)
      end

      def print_fix_activity_footer
        return unless @last_input.to_s.lstrip.start_with?("/fix", "fix ")

        summary = @activity&.fix_summary
        return if summary.to_s.empty?

        Master::Trace::Dmesg.status("fix0", summary.delete_prefix("fix0: "))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.fix_activity_footer", event_bus: @refs.bus)
      end

      def print_capability_stamp(ok)
        return unless verbose_output?
        return unless ok.respond_to?(:model)

        model = ok.model
        return if model.to_s.empty?

        Master::Trace::Dmesg.status(
          "model0",
          Master::CLI::CapabilityStamp.render(model:, root: Master::ROOT).to_s.delete_prefix("model0 at master0: "),
        )
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.capability_stamp", event_bus: @refs.bus)
      end

      def print_parallel_errors_footer(ok)
        return unless ok.respond_to?(:value)

        value = ok.value
        return unless value.respond_to?(:[])

        errors = Array(value[:_parallel_errors]).map(&:to_s).reject(&:empty?)
        timeout = value[:_parallel_timeout]
        stage_err = value[:_stage_error].to_s
        lines = errors
        lines << "parallel timeout" if timeout
        lines << stage_err unless stage_err.empty?
        return if lines.empty?

        Master::Trace::Dmesg.status("parallel0", lines.first(3).join("; "))
      end

      # A streamed turn whose answer came from a later step (a tool loop's final reply, or the next lane after
      # one failed mid-stream) printed only what led up to it; the answer itself is printed here. The stream
      # carries the raw reply while the result carries its rendered form, so the duplicate check reads the raw
      # output: rendered text wears ANSI escapes the stream never showed, and one escaped prefix read as "not
      # yet printed" — the reply then appeared twice (Johann's log 2026-11-08).
      def print_unstreamed_reply(ok, streamed_text:)
        raw = raw_success_text(ok).to_s.strip
        return streamed_text if raw.empty? || streamed_text.include?(raw[0, 120])

        display_prepared_terminal_output(measured_reply(raw))
        raw
      end

      # The reply before presentation: the stream printed raw chunks, so the
      # duplicate check and the spoken form read the bytes the stream carried.
      # The value is a Hash when a turn carried rendered/output text; anything
      # else displays as itself - a String responding to [] with a Symbol is a
      # TypeError that killed the queue worker, not a display.
      def raw_success_text(ok)
        value = ok.value
        fields = result_fields(value)
        return value.to_s unless fields

        output = fields[:output].to_s
        output.empty? ? fields[:rendered].to_s : output
      end

      def measured_reply(text)
        rendered = text
        rendered = @refs.renderer.terminal_markdown(text, width: reply_measure) if @refs.renderer.respond_to?(:terminal_markdown)
        @refs.renderer.measure(rendered.to_s.chomp, width: reply_measure)
      end

      # A queued turn's reply prints long after its prompt scrolled past; with
      # several lines waiting, the answer read as belonging to whichever
      # message was typed last (Johann's log 2026-11-08: the depression answer
      # read as a reply to "hey hey"). One dim line binds a turn running off
      # the queue to the line that started it, and names the outcome: a
      # confirm-gated command is not answered, it failed (deploy log
      # 2026-11-11 printed "answered:" over a review refusal).
      def print_answer_attribution(verb)
        return unless Thread.current == @turn_worker && $stdout.tty?

        question = queue_question_brief(@last_input)
        return if question.empty?

        Master::Trace::Dmesg.status("queue0", "#{verb}: #{question}")
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.answer_attribution", event_bus: @refs.bus)
      end

      # The queued line as a receipt shows it: one space run, capped at 72
      # columns on a word boundary, the cut marked. Cutting inside a word
      # invented a command that was never typed ("vm23" -> "vm2", deploy log
      # 2026-11-11) and sent the reader hunting a host that was never named.
      def queue_question_brief(text, cap = 72)
        line = text.to_s.scrub.gsub(/\s+/, " ").strip
        return line if line.length <= cap

        head = line[0, cap].sub(/\s+\S*\z/, "")
        "#{head}\u2026"
      end

      def success_text(ok)
        value = ok.value
        fields = result_fields(value)
        return value.to_s unless fields

        rendered = fields[:rendered].to_s
        return rendered unless rendered.empty?

        fields[:output].to_s
      end

      # Commands may return the typed PipelineContext produced by the last
      # stage, not a plain Hash. It deliberately exposes only [] and key? as
      # its read surface; render its fields instead of leaking Object#to_s.
      def result_fields(value)
        return value if value.is_a?(Hash)
        return value if value.respond_to?(:key?) && value.respond_to?(:[])

        nil
      end

      def routine_success?(text)
        text = text.to_s
        !text.empty? && text.lines.size == 1 && text.length <= ROUTINE_SUCCESS_MAX_LENGTH
      end

      def violations_count
        @violations_mutex.synchronize { @violations }
      end

      def set_violations(count)
        @violations_mutex.synchronize do
          @violations = count
          @prev_violations = count
        end
      end

      def exit_code_for(err)
        case err.category
        when :validation, :policy, :axiom_violation
          1
        when :provider_error, :llm_failure, :llm_call_failure, :no_api_key
          3
        else
          2
        end
      end
    end
  end
end
