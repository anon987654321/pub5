# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "set"
require_relative "../io/atomic_write"
require_relative "repair_outcomes"

module Master
  module Fix
    # What /fix has learned from the model, so it stops asking what it already
    # asked. Opus declined about a third of the findings it was sent, and every
    # run sent the same unchanged files again: a decline is kept against the
    # file's content, and asked again only once the file changes. A rule the
    # model declines nearly every time is mostly reporting false findings, so
    # past RETIRE_AFTER asks at RETIRE_RATIO it is no longer sent at all, and the
    # run says which rule and why, so the rule is fixed instead.
    class RepairMemory
      include Master::Io::AtomicWrite

      PATH = File.join(".master", "fix_memory.json")
      RETIRE_AFTER = 20
      RETIRE_RATIO = 0.8
      DECLINED = %i[no_proposal].freeze
      APPLIED = %i[applied commit_refused].freeze
      LOCK = Mutex.new
      ANNOUNCED = Set.new
      # A rule's detector fingerprint, once per process: the code a process
      # runs does not change under it (a reload is a new process).
      DETECTORS = {}

      def initialize(root:)
        @root = root
        @file = File.join(root, PATH)
      end

      # The findings still worth a model call: not declined for the file as it
      # is now, and not of a retired rule.
      def fresh(path, findings)
        data = with_store_lock { load }
        declined = declined_for(path, data)
        findings.reject { |finding| declined.include?(finding[:law].to_s) || retired?(finding[:law], data) }
      end

      def retired?(law_id, data = nil)
        data ||= with_store_lock { load }
        stats = data.dig("laws", law_id.to_s)
        return false unless stats && stats["asked"].to_i >= RETIRE_AFTER

        return false if (stats["declined"].to_f / stats["asked"]) < RETIRE_RATIO

        # Once per rule: the counts still move while in-flight repairs land, so
        # the line itself cannot be the key.
        ANNOUNCED.add?(law_id.to_s) && Master::Trace::Dmesg.status(
          "fix0", "#{law_id} retired from model repair: declined #{stats["declined"]} of #{stats["asked"]}"
        )
        true
      end

      # What the model said about a rule describes the detector that found the
      # findings. Once the detector's source changes (a false positive fixed),
      # its count starts afresh and the file declines it earned go with it;
      # otherwise a fixed rule stays retired on the old detector's record. The
      # fingerprint is the detector's whole source file, so an edit beside it
      # also resets, which costs only a few asks. A count kept before
      # fingerprints existed adopts the current one.
      def sync_detectors(laws)
        marks = laws.to_h { |law| [law.id.to_s, DETECTORS.fetch(law.id.to_s) { DETECTORS[law.id.to_s] = detector_digest(law) }] }
        with_store_lock do
          data = load
          changed = marks.count { |id, digest| digest && refingerprint(data, id, digest) }
          save(data) if changed.positive?
        end
      end

      # outcomes is a repair's breakdown, { outcome_symbol => count }. A call the
      # model never answered (quota, no lane) says nothing about the findings,
      # so it counts as neither an ask nor a decline.
      def record(path, law_ids, outcomes)
        verdict = verdict_for(outcomes)
        return if verdict == :unanswered

        with_store_lock do
          data = load
          law_ids.each { |id| tally(data, id.to_s, verdict) }
          remember_file(data, path, law_ids, verdict)
          save(data)
        end
        RepairOutcomes.new(root: @root).record(path, law_ids, outcomes)
      end

      private

      # True when the stats changed: a first fingerprint, or a new detector.
      def refingerprint(data, id, digest)
        stats = data["laws"][id]
        return false if stats.nil? || stats["detector"] == digest

        unless stats["detector"].nil?
          data["laws"][id] = { "asked" => 0, "declined" => 0, "applied" => 0 }
          data["files"].each_value { |entry| entry["declined"] = Array(entry["declined"]) - [id] }
          ANNOUNCED.delete(id)
          Master::Trace::Dmesg.status("fix0", "#{id} detector changed; its repair record starts afresh")
        end
        data["laws"][id]["detector"] = digest
        true
      end

      def detector_digest(law)
        # A Law's detector is its `check` block, its `detect` block, or its class's #check.
        definition = law.respond_to?(:definition) ? law.definition : nil
        block = definition && (definition.check || definition.detect)
        source = block&.source_location || law.class.instance_method(:check).source_location
        file = source&.first
        file && File.file?(file) ? Digest::SHA256.file(file).hexdigest[0, 16] : nil
      rescue NameError
        nil
      end

      def verdict_for(outcomes)
        keys = Array(outcomes&.keys).map(&:to_sym)
        return :applied if keys.intersect?(APPLIED)
        return :unanswered if keys.include?(:model_failed)

        keys.intersect?(DECLINED) ? :declined : :other
      end

      def tally(data, id, verdict)
        stats = (data["laws"][id] ||= { "asked" => 0, "declined" => 0, "applied" => 0 })
        stats["asked"] += 1
        stats["declined"] += 1 if verdict == :declined
        stats["applied"] += 1 if verdict == :applied
      end

      # A decline is kept against the content it was about; a repair changes the
      # file, so what was declined before no longer describes it.
      def remember_file(data, path, law_ids, verdict)
        key = relative(path)
        return data["files"].delete(key) if verdict == :applied
        return unless verdict == :declined

        entry = data["files"][key]
        sha = digest(path)
        earlier = entry && entry["sha"] == sha ? Array(entry["declined"]) : []
        data["files"][key] = { "sha" => sha, "declined" => (earlier + law_ids.map(&:to_s)).uniq }
      end

      def declined_for(path, data)
        entry = data.dig("files", relative(path))
        entry && entry["sha"] == digest(path) ? Array(entry["declined"]) : []
      end

      def load
        return { "files" => {}, "laws" => {} } unless File.exist?(@file) || File.symlink?(@file)

        stat = File.lstat(@file)
        unless stat.file? && !stat.symlink? && stat.nlink == 1
          raise IOError, "repair memory must be a singly linked regular file"
        end
        flags = File::RDONLY
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(@file, flags) do |file|
          opened = file.stat
          current = File.lstat(@file)
          unless current.file? && !current.symlink? && current.nlink == 1 &&
                 current.dev == opened.dev && current.ino == opened.ino
            raise IOError, "repair memory path changed while opening"
          end
          raw = file.read(5 * 1024 * 1024 + 1)
          raise IOError, "repair memory exceeds the 5 MiB safety limit" if raw.bytesize > 5 * 1024 * 1024

          { "files" => {}, "laws" => {} }.merge(JSON.parse(raw))
        end
      rescue JSON::ParserError
        { "files" => {}, "laws" => {} }
      end

      def save(data)
        write_atomic(@file, JSON.pretty_generate(data) + "\n", mode: 0o660)
      end

      # The process mutex protects threads; the sidecar flock protects the
      # read-modify-write cycle between independent MASTER processes sharing
      # one .master directory. Both reads and writes enter through this gate.
      def with_store_lock
        LOCK.synchronize do
          directory = File.dirname(@file)
          expected_root = File.realpath(@root)
          resolved = verified_atomic_directory(directory)
          raise IOError, "repair memory directory escapes its repository" unless
            resolved == directory && (resolved == expected_root || resolved.start_with?(expected_root + File::SEPARATOR))

          FileUtils.mkdir_p(directory, mode: 0o700)
          directory_stat = File.lstat(directory)
          unless directory_stat.directory? && !directory_stat.symlink? &&
                 verified_atomic_directory(directory) == directory &&
                 directory_stat.dev == File.stat(expected_root).dev
            raise IOError, "repair memory directory is not a stable in-repository directory"
          end

          lock_path = "#{@file}.lock"
          flags = File::RDWR | File::CREAT
          flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
          File.open(lock_path, flags, 0o660) do |lock|
            opened = lock.stat
            current = File.lstat(lock_path)
            unless opened.file? && opened.nlink == 1 && current.file? && !current.symlink? &&
                   current.nlink == 1 && current.dev == opened.dev && current.ino == opened.ino
              raise IOError, "repair memory lock must be a stable singly linked regular file"
            end
            File.chmod(0o660, lock_path)
            raise IOError, "could not acquire repair memory lock" unless lock.flock(File::LOCK_EX)

            begin
              current = File.lstat(lock_path)
              unless current.file? && !current.symlink? && current.nlink == 1 &&
                     current.dev == opened.dev && current.ino == opened.ino
                raise IOError, "repair memory lock path changed while waiting"
              end
              yield
            ensure
              lock.flock(File::LOCK_UN)
            end
          end
        end
      rescue SystemCallError => error
        raise IOError, "cannot safely lock repair memory: #{error.class}: #{error.message}"
      end

      def digest(path) = File.file?(path) ? Digest::SHA256.file(path).hexdigest : ""
      def relative(path) = File.expand_path(path).delete_prefix("#{File.expand_path(@root)}/")
    end
  end
end
