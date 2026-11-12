# frozen_string_literal: true

require "ipaddr"
require "time"
require_relative "../result"
require_relative "../boot/paths"

module Master
  module Ground
    # Bounded PII spot-check for files deliberately placed inside an operator-
    # selected root. It reports matches in the supplied sample, not compliance.
    class PrivacyAuditor
      EMAIL = /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/.freeze
      PHONE = /\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b/.freeze
      SSN = /\b\d{3}-\d{2}-\d{4}\b/.freeze
      IPV4_CANDIDATE = /\b(?:\d{1,3}\.){3}\d{1,3}\b/.freeze
      REDACTED = "[REDACTED]".freeze
      MAX_BYTES = 16 * 1024 * 1024
      MAX_SAMPLE_BYTES = 400
      MAX_SAMPLES = 5
      SECRET_COMPONENT = /\A(?:\.env(?:rc|[._-][a-z0-9._-]+)?|credentials?|secrets?|private[_-]?keys?)\z/i.freeze

      def initialize(root: MasterPaths.state, clock: -> { Time.now.utc })
        @root = File.expand_path(root)
        @clock = clock
      end

      def scan(text:, source: "provided input", max_sample: 3)
        body = text.to_s
        return Result.err("privacy_auditor: input exceeds #{MAX_BYTES} bytes", category: :validation) if body.bytesize > MAX_BYTES

        sample_limit = Integer(max_sample)
        return Result.err("privacy_auditor: max_sample must be 0..#{MAX_SAMPLES}", category: :validation) unless sample_limit.between?(0, MAX_SAMPLES)

        ipv4 = body.scan(IPV4_CANDIDATE).count { |candidate| valid_ip?(candidate) }
        hits = {
          email: body.scan(EMAIL).size, phone: body.scan(PHONE).size,
          ssn: body.scan(SSN).size, ip: ipv4,
        }.freeze
        total = hits.values.sum
        Result.ok(
          schema: 1, source: source.to_s.gsub(/[^\w:.-]/, "_")[0, 64],
          at: now.iso8601, pii: hits, total:,
          samples: redacted_samples(body, sample_limit),
          risk: risk_of(hits), not_run: total.zero? ? [] : ["review of the complete source and its lawful handling"],
        )
      rescue ArgumentError => error
        Result.err("privacy_auditor: #{error.message}", category: :validation)
      rescue StandardError => error
        Result.err("privacy_auditor: #{error.class}: #{error.message}", category: :infrastructure)
      end

      def scan_file(path:)
        return Result.err("privacy_auditor: selected root is missing or symlinked", category: :policy) unless File.directory?(@root) && !File.symlink?(@root)
        real_root = File.realpath(@root)
        full = File.expand_path(path.to_s, real_root)
        return Result.err("privacy_auditor: path is outside the selected root", category: :policy) unless full.start_with?(real_root + File::SEPARATOR)
        relative_parts = full.delete_prefix(real_root + File::SEPARATOR).split(File::SEPARATOR)
        return Result.err("privacy_auditor: refusing credential path", category: :policy) if relative_parts.any? { |part| SECRET_COMPONENT.match?(part) }
        return Result.err("privacy_auditor: refusing symlink path", category: :policy) if symlink_component?(full, real_root)
        return Result.err("privacy_auditor: no such regular file", category: :validation) unless File.file?(full)
        return Result.err("privacy_auditor: file exceeds size limit", category: :validation) if File.size(full) > MAX_BYTES
        return Result.err("privacy_auditor: refusing multiply-linked file", category: :policy) if File.stat(full).nlink > 1

        body = File.binread(full).force_encoding(Encoding::UTF_8)
        return Result.err("privacy_auditor: file is not valid UTF-8", category: :validation) unless body.valid_encoding?

        scan(text: body, source: relative_parts.join("/"))
      rescue SystemCallError => error
        Result.err("privacy_auditor: #{error.class}: #{error.message}", category: :infrastructure)
      end

      private

      def symlink_component?(path, root)
        relative = path.delete_prefix(root + File::SEPARATOR)
        cursor = root
        relative.split(File::SEPARATOR).any? do |component|
          cursor = File.join(cursor, component)
          File.symlink?(cursor)
        end
      end

      def valid_ip?(candidate)
        IPAddr.new(candidate)
        true
      rescue IPAddr::InvalidAddressError
        false
      end

      def redacted_samples(body, limit)
        return [] if limit.zero?
        body.each_line.filter_map do |line|
          next unless line.match?(EMAIL) || line.match?(PHONE) || line.match?(SSN) ||
                      line.scan(IPV4_CANDIDATE).any? { |candidate| valid_ip?(candidate) }

          value = line.gsub(EMAIL, REDACTED).gsub(PHONE, REDACTED).gsub(SSN, REDACTED)
          value = value.gsub(IPV4_CANDIDATE) { |candidate| valid_ip?(candidate) ? REDACTED : candidate }
          value.byteslice(0, MAX_SAMPLE_BYTES).to_s
        end.uniq.first(limit)
      end

      def risk_of(hits)
        return "HIGH" if hits[:ssn].positive?
        return "MEDIUM" if hits[:email].positive? || hits[:phone].positive?
        return "LOW" if hits.values.any?(&:positive?)

        "LOW"
      end

      def now
        value = @clock.call
        raise TypeError, "clock must return Time" unless value.is_a?(Time)
        value.utc
      end
    end
  end
end
