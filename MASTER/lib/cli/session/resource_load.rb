# frozen_string_literal: true

require "etc"
require_relative "../../io/exec"

module Master
  module CLI
    class Session
      # One snapshot of how hard the turn works: CPU and resident memory of the
      # session process and everything working under it, blended with host load.
      # The spinner samples it at a slow cadence and maps the score to speed/color.
      module ResourceLoad
        CPU_CAP = 120.0
        MEMORY_CAP_KB = 512 * 1024
        PROCESS_WEIGHT = 0.65
        HOST_WEIGHT = 0.35
        LOAD_AVERAGE_WEIGHTS = [0.60, 0.30, 0.10].freeze
        # ps prints rss in kilobytes, but as pages on OpenBSD.
        OPENBSD = RUBY_PLATFORM.include?("openbsd")

        module_function

        # 0..1 for the turn and its host; injected snapshots stay deterministic.
        def turn(root_pid: Process.pid, snapshot: nil, load_average: nil, cpu_count: nil)
          injected_snapshot = !snapshot.nil?
          snapshot ||= ->(argv) { Master::Io::Exec.capture2(*argv).first.to_s }
          rows = parse(snapshot.call(%w[ps -axo pid=,ppid=,%cpu=,rss=]))
          return 0.0 unless rows.key?(root_pid)

          cpu, rss_kb = walk(root_pid, rows)
          process_pressure = score(cpu, rss_kb)
          averages = load_average
          averages = system_load_average if averages.nil? && !injected_snapshot
          host_pressure = host_score(averages, cpu_count || logical_cpu_count)
          return process_pressure unless host_pressure

          (process_pressure * PROCESS_WEIGHT + host_pressure * HOST_WEIGHT).clamp(0.0, 1.0)
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

        # An unavailable host CPU count removes only the host component. It must
        # never turn a usable process-tree measurement into a zero score.
        def logical_cpu_count
          Etc.nprocessors
        rescue StandardError, NotImplementedError
          nil
        end

        # The CLI spinner follows the host CPU load average, not the
        # memory or process-tree score used by the wider resource indicator.
        def cpu_load
          host_score(system_load_average, logical_cpu_count) || 0.0
        end

        # Weighted 1/5/15-minute load, normalized by logical CPU count.
        def host_score(load_average, cpu_count)
          values = Array(load_average).first(3).map { |value| Float(value) }
          return unless values.length == 3 && values.all? { |value| value.finite? && value >= 0 }

          processors = Integer(cpu_count)
          return unless processors.positive?

          weighted = values.zip(LOAD_AVERAGE_WEIGHTS).sum { |value, weight| value * weight }
          (weighted / processors).clamp(0.0, 1.0)
        rescue ArgumentError, TypeError, RangeError
          nil
        end

        # Linux exposes load average as a proc file; the BSD and macOS path uses
        # the native sysctl interface. Missing permissions/platform support simply
        # remove the host component rather than breaking the thinking indicator.
        def system_load_average
          raw = if File.readable?("/proc/loadavg")
                  File.read("/proc/loadavg")
                else
                  Master::Io::Exec.capture2("sysctl", "-n", "vm.loadavg").first.to_s
                end
          values = raw.scan(/\d+(?:\.\d+)?/).first(3)
          return unless values.length == 3

          values.map(&:to_f)
        rescue StandardError
          nil
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
