# frozen_string_literal: true

require "etc"
require_relative "../../io/exec"

module Master
  module CLI
    class Session
      # One snapshot of how hard the turn works: CPU and resident memory of the
      # session process and everything working under it. The spinner samples it
      # at a slow cadence and maps the score to its speed and color.
      module ResourceLoad
        CPU_CAP = 120.0
        MEMORY_CAP_KB = 512 * 1024
        # ps prints rss in kilobytes, but as pages on OpenBSD.
        OPENBSD = RUBY_PLATFORM.include?("openbsd")

        module_function

        # 0..1 for the whole turn tree; the frame loop never sees a raise.
        def turn(root_pid: Process.pid, snapshot: nil)
          snapshot ||= ->(argv) { Master::Io::Exec.capture2(*argv).first.to_s }
          cpu, rss_kb = walk(root_pid, parse(snapshot.call(%w[ps -axo pid=,ppid=,%cpu=,rss=])))
          score(cpu, rss_kb)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.resource_load")
          0.0
        end

        # One ps snapshot as pid => [ppid, %cpu, rss_kb].
        def parse(out)
          rows = {}
          out.to_s.each_line do |line|
            pid, ppid, cpu, rss = line.split
            next unless pid && ppid && cpu && rss && pid.match?(/\A\d+\z/)

            rows[pid.to_i] = [ppid.to_i, cpu.to_f, rss.to_i * page_kb]
          end
          rows
        end

        # CPU saturates at one busy core, memory at its cap; the blend leans on
        # CPU because that is what a stalled turn feels like first.
        def score(cpu, rss_kb)
          0.6 * (cpu.to_f / CPU_CAP).clamp(0.0, 1.0) +
            0.4 * (rss_kb.to_f / MEMORY_CAP_KB).clamp(0.0, 1.0)
        end

        def page_kb
          OPENBSD ? Etc.sysconf(Etc::SC_PAGESIZE).fdiv(1024) : 1.0
        end

        # Sum of the tree rooted at the session pid: a reparented orphan's
        # edge ends there, so a lost child drops its term, never the total.
        def walk(root_pid, rows)
          row = rows[root_pid]
          return 0.0, 0 unless row

          cpu = row[1]
          rss_kb = row[2]
          stack = children_of(root_pid, rows)
          seen = { root_pid => true }
          until stack.empty?
            pid = stack.pop
            next if seen[pid]

            seen[pid] = true
            entry = rows.fetch(pid)
            cpu += entry[1]
            rss_kb += entry[2]
            stack.concat(children_of(pid, rows))
          end
          [cpu, rss_kb]
        end

        # Descendants of one pid, from one scan.
        def children_of(pid, rows)
          rows.each_with_object([]) { |(child, entry), kids| kids << child if entry[0] == pid && child != pid }
        end
      end
    end
  end
end
