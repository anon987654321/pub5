# frozen_string_literal: true

module Master
  module Fix
    module Scan
      # The progress monitor of the scan, re-opening the FileProcessor defined
      # in fix/scan/file_processor.rb: what each law in flight reports, the
      # small watcher that samples that in-memory state once a second, and the
      # CHECK_PROGRESS_FILE / console heartbeat it feeds. All private; the
      # public surface stays in fix/scan/file_processor.rb, and every path here
      # is listed in data/autoload.yml under
      # autoload.reopens_a_constant_defined_elsewhere.
      class FileProcessor
        PROGRESS_POLL_SECONDS = 1.0
        PROGRESS_IDLE_GRACE_SECONDS = 3.0
        PROGRESS_HEARTBEAT_SECONDS = 5.0

        private

        # Constructor state of the progress monitor, kept beside the methods that read it.
        def init_progress_state
          @progress_path = ENV.fetch("CHECK_PROGRESS_FILE", "").to_s
          @progress_writer_id = "#{Process.pid}-#{object_id}"
          @progress_mutex = Mutex.new
          @active_law_checks = {}
          @progress_previous_callbacks = {}
          @progress_sequence = 0
          @progress_thread = nil
          @progress_idle_since = nil
          @progress_last_check = nil
          @progress_error_reported = false
        end

        # The monitor reports the law that's actually in flight, not merely the
        # outer scan stage. One small watcher samples this in-memory state once a
        # second; worker threads never contend on progress-file I/O.
        def begin_law_progress(pass:, law:, index:, total:, path:)
          return unless progress_reporting?

          previous_callback = Thread.current.thread_variable_get(:master_scan_progress_callback)
          # Object identity keeps simultaneous worker threads from collapsing
          # into one hash key when they enter the scanner at the same time.
          token = Object.new
          Thread.current.thread_variable_set(:master_scan_progress_callback, progress_callback(token, total))

          row = initial_progress_row(pass:, law:, index:, total:, path:)
          @progress_mutex.synchronize do
            @progress_sequence += 1
            row["checks"] = @progress_sequence
            @progress_previous_callbacks[token] = previous_callback
            @active_law_checks[token] = row
            @progress_idle_since = nil
            @progress_last_check = row
            start_progress_monitor_locked
          end
          token
        end

        def end_law_progress(token)
          return unless token

          previous_callback = nil
          @progress_mutex.synchronize do
            previous_callback = @progress_previous_callbacks.delete(token)
            finished = @active_law_checks.delete(token)
            if finished && @active_law_checks.empty?
              @progress_idle_since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              @progress_last_check = finished.merge(
                "state" => "idle",
                "active" => 0,
                "updated_at" => Time.now.to_f,
              )
            end
          end
          Thread.current.thread_variable_set(:master_scan_progress_callback, previous_callback)
        end

        def start_progress_monitor_locked
          return if @progress_thread&.alive?

          @progress_thread = Thread.new { run_progress_monitor }
          @progress_thread.name = "master-scan-progress" if @progress_thread.respond_to?(:name=)
        end

        def run_progress_monitor
          last_console_beat = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          loop do
            sleep PROGRESS_POLL_SECONDS
            snapshot, stop = progress_tick
            break if stop
            next unless snapshot

            last_console_beat = emit_progress(snapshot, last_console_beat)
          end
        rescue StandardError => e
          Master::Trace::Dmesg.status("scan0", "progress monitor failed, #{e.class}: #{e.message.to_s[0, 140]}")
        ensure
          @progress_mutex.synchronize do
            @progress_thread = nil if @progress_thread == Thread.current
          end
        end

        # One poll of the watcher: read the in-memory state and decide between
        # the running row and the idle one, or retire once the last law has been
        # quiet past the grace period.
        def progress_tick
          snapshot = nil
          stop = false
          @progress_mutex.synchronize do
            if @active_law_checks.empty?
              stop, snapshot = idle_tick(Process.clock_gettime(Process::CLOCK_MONOTONIC))
            else
              snapshot = running_row
            end
          end
          [snapshot, stop]
        end

        def idle_tick(now)
          @progress_idle_since ||= now
          if now - @progress_idle_since >= PROGRESS_IDLE_GRACE_SECONDS
            @progress_thread = nil if @progress_thread == Thread.current
            return [true, nil]
          end

          [false, idle_row]
        end

        def idle_row
          return nil unless @progress_last_check

          @progress_last_check.merge(
            "state" => "idle",
            "active" => 0,
            "monitor_at" => Time.now.to_f,
          )
        end

        def running_row
          current = @active_law_checks.values.max_by { |row| row.fetch("checks") }
          current.merge(
            "state" => "running",
            "active" => @active_law_checks.size,
            "monitor_at" => Time.now.to_f,
          )
        end

        # The snapshot goes to the CHECK_PROGRESS_FILE when one is asked for;
        # otherwise the console gets a heartbeat only while a law is running.
        # Returns the console beat so an idle stretch keeps its own cadence.
        def emit_progress(snapshot, last_console_beat)
          if @progress_path.empty?
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            if snapshot["state"] == "running" && now - last_console_beat >= PROGRESS_HEARTBEAT_SECONDS
              Master::Trace::Dmesg.status("scan0", progress_line(snapshot))
              last_console_beat = now
            end
          else
            write_progress_snapshot(snapshot)
          end
          last_console_beat
        end

        # The callback a law run, and the nested detectors inside laws.yml's own
        # pass, call to say which law is in flight; the watcher samples what it
        # wrote under the same mutex.
        def progress_callback(token, total)
          lambda do |inner_pass:, inner_law:, index:, total:, path:|
            @progress_mutex.synchronize do
              active = @active_law_checks[token]
              next unless active

              @progress_sequence += 1
              active.merge!(progress_fields(inner_pass, inner_law, index, total, path))
              @progress_last_check = active
            end
          end
        end

        def progress_fields(inner_pass, inner_law, index, total, path)
          {
            "pass" => inner_pass.to_s,
            "law" => inner_law.to_s,
            "file" => relative_progress_path(path),
            "n" => index,
            "total" => total,
            "name" => "#{inner_pass} #{inner_law}",
            "at" => Time.now.to_f,
            "updated_at" => Time.now.to_f,
            "checks" => @progress_sequence,
          }
        end

        def initial_progress_row(pass:, law:, index:, total:, path:)
          law_id = law.respond_to?(:id) ? law.id.to_s : law.class.name.to_s
          {
            "kind" => "scan",
            "state" => "running",
            "pass" => pass.to_s,
            "law" => law_id,
            "file" => relative_progress_path(path),
            "n" => index,
            "total" => total,
            "name" => "#{pass} #{law_id}",
            "at" => Time.now.to_f,
            "updated_at" => Time.now.to_f,
          }
        end

        def progress_reporting? = ENV["MASTER_SCAN_PROGRESS"] != "0"

        def write_progress_snapshot(row)
          temporary = "#{@progress_path}.scan-#{@progress_writer_id}"
          File.open(temporary, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |io|
            io.write(JSON.generate(row))
            io.flush
          end
          File.rename(temporary, @progress_path)
        rescue SystemCallError, IOError => e
          should_report = @progress_mutex.synchronize do
            next false if @progress_error_reported

            @progress_error_reported = true
          end
          Master::Trace::Dmesg.status("scan0", "progress file unavailable, #{e.class}: #{e.message}") if should_report
        ensure
          begin
            File.delete(temporary) if temporary && File.exist?(temporary)
          rescue SystemCallError
            nil
          end
        end

        def relative_progress_path(path)
          expanded = File.expand_path(path.to_s)
          [Master::REPO_ROOT, Master::ROOT].compact.each do |root|
            base = File.expand_path(root)
            return expanded.delete_prefix("#{base}/") if expanded.start_with?("#{base}/")
          end
          path.to_s
        end

        def progress_line(row)
          format(
            "active pass=%s law=%s file=%s checks=%s law=%s/%s workers=%s for %ds",
            row.fetch("pass"), row.fetch("law"), row.fetch("file"), row.fetch("checks"),
            row.fetch("n"), row.fetch("total"), row.fetch("active", 1),
            [Time.now.to_f - row.fetch("at").to_f, 0].max.round
          )
        end
      end
    end
  end
end
