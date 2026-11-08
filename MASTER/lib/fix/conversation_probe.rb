# frozen_string_literal: true

require "open3"
require "pty"
require "timeout"
require_relative "../cli/routing/model_router"
require_relative "../ground/swallow"
require_relative "../trace/dmesg"
require_relative "../voice/dialogue_rubric"

module Master
  module Fix
    # The conversation surface measured the way the operator meets it: a real CLI
    # boot in a pseudo-terminal. The deterministic suite (corpus integrity, intent
    # routing, the bench instrument itself, prompt reach) runs without a model; the
    # live suite sends bounded scripted turns from data/dialogue_rubric.yml#ux_probe
    # through `bin/master --fast -p` in a PTY and grades the replies with the same
    # rubric bench the conversational constitution ships. A turn whose lane cannot
    # serve is INCONCLUSIVE, never a pass; a reply whose text cannot be extracted is
    # INCONCLUSIVE too, because a probe that grades banner noise would punish
    # nothing. The stage owns no repairs of its own: its findings ride the run like
    # any other stage's, so the repair passes auto-correct and the next pass or run
    # re-measures.
    module ConversationProbe
      SCENARIO_INTENTS = %w[day_to_day chitchat support].freeze
      MAX_LIVE_TURNS = Integer(ENV.fetch("MASTER_FIX_CONVERSATION_MAX", "2")).clamp(0, 8)
      PTY_TIMEOUT_S = Integer(ENV.fetch("MASTER_CONVERSATION_PTY_TIMEOUT", "120"))
      ANSI_RE = /\e\[[0-9;]*[A-Za-z]/.freeze
      # master0:, boot0:, budget0:, fix0: ... every instrument prints "name0 at ".
      STATUS_LINE_RE = /\A[a-z]+0\b/.freeze
      # A lane that cannot serve answers with the degraded path, not silence; those
      # replies are evidence the surface booted, not evidence about conversation law.
      DEGRADED_RE = /
        no\s+model|without\s+a\s+model|model\s+(?:unavailable|lane)|lane\s+(?:unavailable|probe|failed)
        |not\s+(?:available|configured|landed)|blocked|inconclusive
      /xi.freeze
      RUBRIC_DATA = "MASTER/data/dialogue_rubric.yml"
      RUBRIC_RUBY = "MASTER/lib/voice/dialogue_rubric.rb"
      ROUTER_RUBY = "MASTER/lib/cli/routing/model_router.rb"

      Report = Data.define(:status, :deterministic, :live, :findings, :brief, :case_count, :failed_count)

      module_function

      def run(root:, target: nil, agent: nil, bus: nil, spawner: nil, max_live: MAX_LIVE_TURNS,
              deterministic: true, live: true)
        master_root = File.expand_path(root)
        findings = []
        det = deterministic ? deterministic_suite(master_root:, findings:) : { status: "SKIPPED", checks: {} }
        live_report = if !live || max_live.to_i.zero?
                        { status: "SKIPPED", reason: max_live.to_i.zero? ? "MASTER_FIX_CONVERSATION_MAX=0" : "live turns not requested", cases: [] }
                      else
                        live_suite(master_root:, findings:, root:, agent:, bus:, spawner:, max_live:)
                      end
        status = overall_status(det, live_report)
        brief = render_brief(status:, det:, live_report:, target:)
        case_count = Array(live_report[:cases]).size
        failed_count = Array(live_report[:cases]).count { |row| row[:status] == :fail }
        bus&.publish("fix_loop:conversation", target: target.to_s, status:, deterministic: det[:status],
                     live: live_report[:status], cases: case_count, findings: findings.size)
        Master::Trace::Dmesg.status(
          "conv0",
          "#{status} det=#{det[:status]} live=#{live_report[:status]} cases=#{case_count} findings=#{findings.size}",
        )
        Report.new(status:, deterministic: det, live: live_report, findings:, brief:, case_count:, failed_count:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix_loop.conversation_probe", event_bus: bus)
        Master::Trace::Dmesg.status("conv0", "inconclusive, #{e.class}: #{e.message}")
        Report.new(
          status: "INCONCLUSIVE", deterministic: { status: "INCONCLUSIVE" }, live: { status: "SKIPPED", cases: [] },
          findings: [], brief: "CONVERSATION PROBE: INCONCLUSIVE - #{e.class}: #{e.message.to_s[0, 200]}",
          case_count: 0, failed_count: 0,
        )
      end

      # The no-model half: the corpus, the routing expectations it names, the bench
      # instrument against a known-bad reply, and the reach of the rubric into the
      # rendered prompt. Each check names its owning file, so a failure is a finding
      # the repair loop can act on. Rubric data reads the MASTER root; findings name
      # checkout-relative paths.
      def deterministic_suite(master_root:, findings:)
        checks = []
        checks << corpus_check(master_root:, findings:)
        checks << routing_check(master_root:, findings:)
        checks << instrument_check(findings:)
        checks << prompt_reach_check(master_root:, findings:)
        { status: findings.any? ? "FAIL" : "PASS", checks: }
      rescue StandardError => e
        findings << finding(RUBRIC_RUBY, "conversation_probe/deterministic: #{e.class}: #{e.message.to_s[0, 160]}")
        { status: "FAIL", checks: [] }
      end

      def corpus_check(master_root:, findings:)
        scenarios = Master::Voice::DialogueRubric.ux_scenarios(root: master_root)
        if scenarios.empty?
          findings << finding(RUBRIC_DATA, "conversation_probe/corpus: ux_probe scenarios missing")
          return { name: "corpus", status: "FAIL", detail: "no ux_probe scenarios" }
        end
        { name: "corpus", status: "PASS", detail: "#{scenarios.size} scenarios" }
      end

      def routing_check(master_root:, findings:)
        classifier = Object.new.extend(Master::CLI::Routing::ModelRouter::IntentClassification)
        misroutes = []
        Master::Voice::DialogueRubric.ux_scenarios(root: master_root).each do |scenario|
          intent = scenario["intent"].to_s
          user = scenario["user"].to_s
          routed = case intent
                   when "chitchat" then classifier.classify_intent(user) == :chitchat
                   when "day_to_day" then classifier.classify_intent(user) != :chitchat
                   else Master::Voice::DialogueRubric.support_relevant?(user)
                   end
          misroutes << "#{scenario["id"]}: #{intent} routed #{intent == "support" ? "outside the support cues" : classifier.classify_intent(user).inspect}" unless routed
        end
        misroutes.each do |misroute|
          owner = misroute.include?("outside the support cues") ? RUBRIC_RUBY : ROUTER_RUBY
          findings << finding(owner, "conversation_probe/routing: #{misroute}")
        end
        { name: "routing", status: misroutes.any? ? "FAIL" : "PASS",
          detail: misroutes.any? ? misroutes.join("; ")[0, 180] : "every scenario routes as its intent names" }
      end

      # A check's first run is against a known-bad input: the bench must catch the
      # forbidden opener the constitution itself declares, count two questions, and
      # grade an empty reply as clean of the patterns it never saw.
      def instrument_check(findings:)
        bad = Master::Voice::DialogueRubric.evaluate("As an AI language model, I hope this helps!")
        missed = []
        missed << "forbidden opener undetected" unless bad.any? { |row| row.include?("no_ai_isms") }
        missed << "question limit undetected" unless Master::Voice::DialogueRubric.question_count("One? Two?") == 2
        missed << "empty reply graded dirty" unless Master::Voice::DialogueRubric.evaluate("").empty?
        missed.each { |miss| findings << finding(RUBRIC_RUBY, "conversation_probe/instrument: #{miss}") }
        { name: "instrument", status: missed.any? ? "FAIL" : "PASS",
          detail: missed.any? ? missed.join("; ") : "bench catches its own known-bad reply" }
      end

      def prompt_reach_check(master_root:, findings:)
        block = Master::Voice::DialogueRubric.prompt_block(root: master_root)
        missing = if block.to_s.empty?
                    { message: "the dialogue rubric prompt block is absent", detail: "prompt block absent" }
                  else
                    absent = Master::Voice::DialogueRubric.dimensions(root: master_root).keys.reject { |name| block.include?("#{name}:") }
                    absent.empty? ? nil : { message: "dimensions #{absent.join(", ")} never reach the prompt", detail: absent.join(", ")[0, 120] }
                  end
        findings << finding(RUBRIC_RUBY, "conversation_probe/prompt_reach: #{missing[:message]}") if missing
        { name: "prompt_reach", status: missing ? "FAIL" : "PASS",
          detail: missing ? missing[:detail] : "every rubric dimension reaches the prompt" }
      end

      # The with-model half: bounded scripted turns through the PTY one-shot surface.
      def live_suite(master_root:, findings:, root:, agent:, bus:, spawner:, max_live:)
        cases = Master::Voice::DialogueRubric.ux_scenarios(root: master_root).first(max_live.to_i).map do |scenario|
          row = live_case(scenario, root:, agent:, spawner:)
          bus&.publish("fix_loop:conversation_case", id: scenario["id"], intent: scenario["intent"],
                       status: row[:status], seconds: row[:seconds])
          row
        end
        findings.concat(case_findings(cases))
        status = if cases.any? { |row| row[:status] == :fail }
                   "FAIL"
                 elsif cases.any? { |row| row[:status] == :inconclusive }
                   "INCONCLUSIVE"
                 else
                   "COMPLETE"
                 end
        { status:, cases: }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix_loop.conversation_probe.live", event_bus: bus)
        { status: "INCONCLUSIVE", reason: "#{e.class}: #{e.message.to_s[0, 160]}", cases: [] }
      end

      def live_case(scenario, root:, agent:, spawner:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        turn = scenario["user"].to_s
        result = if spawner
                   spawner.call(turn)
                 elsif agent.respond_to?(:ask_once)
                   answer = agent.ask_once(turn, operation: :conversation_probe).to_s
                   { status: :ok, output: answer }
                 else
                   pty_turn(turn, root:)
                 end
        seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
        case result[:status]
        when :ok
          reply = extract_reply(result[:output].to_s)
          return case_row(scenario, :inconclusive, seconds, "reply text not extractable from terminal output") if reply.to_s.strip.empty?
          # A degraded lane answers with the no-model path; grading it would measure
          # nothing and still report green. It is INCONCLUSIVE, never a pass.
          if DEGRADED_RE.match?(reply)
            return case_row(scenario, :inconclusive, seconds, "the lane did not serve a real reply (degraded output)", reply:)
          end

          violations = Master::Voice::DialogueRubric.evaluate(reply)
          return case_row(scenario, :fail, seconds, violations.join("; ")[0, 220], reply:) if violations.any?

          case_row(scenario, :pass, seconds, nil, reply:)
        else
          case_row(scenario, :inconclusive, seconds, result[:message].to_s[0, 200])
        end
      end

      def case_row(scenario, status, seconds, reason, reply: nil)
        { id: scenario["id"].to_s, intent: scenario["intent"].to_s, status:, seconds:, reason:,
          must: Array(scenario["must"]), reply: reply.to_s[0, 400] }
      end

      # A live reply that violates the bench is a finding against the conversational
      # constitution that owns response shape, with the corpus data beside it.
      def case_findings(cases)
        cases.select { |row| row[:status] == :fail }.map do |row|
          finding(RUBRIC_DATA, "conversation_probe/live #{row[:id]} (#{row[:intent]}): #{row[:reason]}")
        end
      end

      # One real boot in a pseudo-terminal, the way bin/smoke boots it: the cheap-boot
      # environment, --fast, the turn as -p. The reply is whatever the terminal shows.
      def pty_turn(turn, root:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        output = +""
        env = {
          "MASTER_WEB" => "0", "MASTER_SKIP_TTS" => "1", "MASTER_SKIP_BOOT_SCAN" => "1",
          "MASTER_BACKGROUND" => "0", "MASTER_AUTOFIX" => "0", "MASTER_WATCH" => "0",
          "MASTER_WATCHER" => "0", "MASTER_HEARTBEAT" => "0",
        }
        master = File.join(File.expand_path(root), "bin", "master")
        exit_status = nil
        PTY.spawn(env, master, "--fast", "-p", turn) do |reader, writer, pid|
          writer.close
          begin
            Timeout.timeout(PTY_TIMEOUT_S) do
              while (chunk = reader.readpartial(16_384))
                output << chunk
              end
            end
          rescue EOFError, Errno::EIO
            nil
          rescue Timeout::Error
            Process.kill("TERM", pid) rescue nil
            return { status: :timeout, message: "no reply within #{PTY_TIMEOUT_S}s", output:, seconds: PTY_TIMEOUT_S }
          end
          _pid, exit_status = Process.wait2(pid)
        end
        seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
        return { status: :error, message: "bin/master exited #{exit_status&.exitstatus}", output:, seconds: } unless exit_status&.success?

        { status: :ok, output:, seconds: }
      rescue StandardError => e
        { status: :unavailable, message: "PTY unavailable: #{e.class}: #{e.message.to_s[0, 120]}", output:, seconds: 0 }
      end

      # Strip ANSI styling and the instrument status lines; what remains is the prose
      # the operator read. Banner art and boot chatter carry no rubric verdicts.
      def extract_reply(output)
        text = output.to_s.gsub(ANSI_RE, "")
        prose = text.lines.map(&:rstrip).reject do |line|
          line.strip.empty? || STATUS_LINE_RE.match?(line.strip)
        end.join("\n").strip
        prose.empty? ? nil : prose
      end

      def overall_status(det, live_report)
        return "FAIL" if det[:status] == "FAIL" || live_report[:status] == "FAIL"
        return "INCONCLUSIVE" if live_report[:status] == "INCONCLUSIVE" || det[:status] == "INCONCLUSIVE"

        "PASS"
      end

      def render_brief(status:, det:, live_report:, target:)
        cases = Array(live_report[:cases])
        counts = %i[pass fail inconclusive].to_h do |key|
          [key, cases.count { |row| row[:status] == key }]
        end
        lines = [
          "CONVERSATION PROBE: #{status}",
          "Target: #{target}. Deterministic suite: #{det[:status]} (#{Array(det[:checks]).map { |check| "#{check[:name]}=#{check[:status]}" }.join(", ")}).",
          "Live turns: #{live_report[:status]} - #{counts[:pass]} pass, #{counts[:fail]} fail, #{counts[:inconclusive]} inconclusive, #{cases.size} asked.",
          live_report[:reason] ? "Live reason: #{live_report[:reason]}" : nil,
          "Replies are graded with the dialogue rubric bench; each case's must[] rides for the critique stage. External conversation research (ar5iv/arXiv, GitHub) rides the conversation research domain.",
        ].compact
        cases.select { |row| %i[fail inconclusive].include?(row[:status]) }.each do |row|
          lines << "case #{row[:id]} (#{row[:intent]}): #{row[:status]} - #{row[:reason]}"
        end
        lines.join("\n")
      end

      def finding(file, message)
        { file:, line: nil, law: nil, message:, severity: :warning, confidence: 0.9,
          fix: "Read the named surface, repair the conversational constitution or its routing, and let the next probe re-measure." }
      end
    end
  end
end
