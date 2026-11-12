# frozen_string_literal: true

require "digest"
require "shellwords"

module Master
  module Fix
    # Validated, content-bearing evidence for the OpenBSD RTFM_FIRST law.
    # This is deliberately part of TaskContract: the write and execution
    # boundaries consume the same receipt rather than trusting prompt text.
    module OpenBSDManualPreflight
      MAX_BYTES = 32 * 1024 * 1024
      MAX_SOURCE_READS = 96
      MAX_MANUAL_PAGES = 80

      COMMAND_MANUALS = {
        "pfctl" => "pfctl(8)", "rcctl" => "rcctl(8)", "doas" => "doas(1)",
        "ifconfig" => "ifconfig(8)", "route" => "route(8)", "netstat" => "netstat(1)",
        "sysctl" => "sysctl(8)", "pkg_add" => "pkg_add(1)", "pkg_delete" => "pkg_delete(1)",
        "pkg_info" => "pkg_info(1)", "relayd" => "relayd(8)", "httpd" => "httpd(8)",
        "sshd" => "sshd(8)", "smtpd" => "smtpd(8)", "smtpctl" => "smtpctl(8)",
        "rc" => "rc(8)", "syspatch" => "syspatch(8)", "upgrade" => "upgrade(8)",
        "mount" => "mount(8)", "umount" => "umount(8)", "disklabel" => "disklabel(8)",
        "bioctl" => "bioctl(8)", "installboot" => "installboot(8)", "fsck" => "fsck(8)",
        "useradd" => "useradd(8)", "usermod" => "usermod(8)", "userdel" => "userdel(8)",
        "chown" => "chown(8)", "chmod" => "chmod(1)", "reboot" => "reboot(8)",
        "shutdown" => "shutdown(8)", "halt" => "halt(8)"
      }.freeze
      SSH_OPTIONS_WITH_VALUE = %w[
        -B -b -c -D -E -e -F -I -i -J -L -l -m -O -o -p -Q -R -S -W -w
      ].freeze

      module_function

      def normalize(value, task_scope:)
        return nil if value.nil?
        raise TaskContract::Invalid, "openbsd_preflight must be a mapping" unless value.is_a?(Hash)

        attributes = value.to_h.transform_keys(&:to_s)
        required = %w[hostname os_release architecture scope source_reads native_interfaces manual_pages]
        optional = %w[no_native_interfaces_reason]
        missing = required - attributes.keys
        unknown = attributes.keys - required - optional
        raise TaskContract::Invalid, "openbsd_preflight is missing: #{missing.join(', ')}" unless missing.empty?
        raise TaskContract::Invalid, "openbsd_preflight has unknown fields: #{unknown.join(', ')}" unless unknown.empty?

        hostname = attributes.fetch("hostname").to_s.strip
        release = attributes.fetch("os_release").to_s.strip
        architecture = attributes.fetch("architecture").to_s.strip
        raise TaskContract::Invalid, "openbsd_preflight.hostname is required" if hostname.empty?
        unless release.match?(/\A[0-9]+(?:\.[0-9]+){0,2}\z/)
          raise TaskContract::Invalid, "openbsd_preflight.os_release is invalid"
        end
        unless architecture.match?(/\A[A-Za-z0-9_.-]+\z/)
          raise TaskContract::Invalid, "openbsd_preflight.architecture is required"
        end

        scope = Array(attributes.fetch("scope")).map { |path| TaskContract.safe_path(path) }.uniq.sort
        raise TaskContract::Invalid, "openbsd_preflight.scope must name an OPENBSD path" if scope.empty?
        scope.each do |entry|
          probe = entry.end_with?("/**") ? "#{entry.delete_suffix("/**")}/.preflight-scope-probe" : entry
          unless probe == "OPENBSD" || probe.start_with?("OPENBSD/")
            raise TaskContract::Invalid, "openbsd_preflight scope must stay under OPENBSD/: #{entry}"
          end
          unless TaskContract.covers?(probe, scope: task_scope)
            raise TaskContract::Invalid, "openbsd_preflight scope exceeds task scope: #{entry}"
          end
        end

        source_rows = Array(attributes.fetch("source_reads"))
        raise TaskContract::Invalid, "openbsd_preflight.source_reads must include complete target/dependency reads" if source_rows.empty?
        raise TaskContract::Invalid, "too many OpenBSD source receipts" if source_rows.size > MAX_SOURCE_READS
        source_total = 0
        source_paths = []
        source_reads = source_rows.map do |row|
          raise TaskContract::Invalid, "OpenBSD source receipt must be a mapping" unless row.is_a?(Hash)
          item = row.to_h.transform_keys(&:to_s)
          allowed = %w[path content complete sha256 bytes lines]
          raise TaskContract::Invalid, "OpenBSD source receipt has unknown fields" unless (item.keys - allowed).empty?
          path = TaskContract.safe_path(item.fetch("path"))
          raise TaskContract::Invalid, "duplicate OpenBSD source receipt: #{path}" if source_paths.include?(path)
          source_paths << path
          content = item.fetch("content").to_s
          raise TaskContract::Invalid, "OpenBSD source receipt is not marked complete: #{path}" unless item.fetch("complete") == true
          raise TaskContract::Invalid, "OpenBSD source receipt is empty: #{path}" if content.empty?
          source_total += content.bytesize
          raise TaskContract::Invalid, "OpenBSD source content exceeds #{MAX_BYTES} bytes" if source_total > MAX_BYTES
          digest = repository_content_digest(path, content, root: Master::REPO_ROOT)
          bytes = content.bytesize
          lines = content.lines.length
          validate_measurements!(item, digest:, bytes:, lines:, label: path)
          {
            "path" => path.freeze, "content" => content.freeze, "complete" => true,
            "sha256" => digest.freeze, "bytes" => bytes, "lines" => lines
          }.freeze
        end

        interfaces = Array(attributes.fetch("native_interfaces")).map do |entry|
          page_id = entry.to_s.strip.downcase
          unless page_id.match?(/\A[a-z0-9_.+-]+\([1-9]\)\z/)
            raise TaskContract::Invalid, "invalid OpenBSD native interface page: #{entry.inspect}"
          end
          page_id
        end.uniq.sort

        manual_rows = Array(attributes.fetch("manual_pages"))
        raise TaskContract::Invalid, "too many OpenBSD manual-page receipts" if manual_rows.size > MAX_MANUAL_PAGES
        manual_total = 0
        manual_pages = manual_rows.map do |row|
          raise TaskContract::Invalid, "OpenBSD manual receipt must be a mapping" unless row.is_a?(Hash)
          item = row.to_h.transform_keys(&:to_s)
          allowed = %w[page section source content complete sha256 bytes lines]
          raise TaskContract::Invalid, "OpenBSD manual receipt has unknown fields" unless (item.keys - allowed).empty?
          page = item.fetch("page").to_s.strip.downcase
          section = item.fetch("section").to_s.strip
          page_id = "#{page}(#{section})"
          unless page.match?(/\A[a-z0-9_.+-]+\z/) && section.match?(/\A[1-9]\z/)
            raise TaskContract::Invalid, "invalid canonical OpenBSD manual page: #{page_id}"
          end
          source = item.fetch("source").to_s.strip
          versioned_url = %r{\Ahttps://man\.openbsd\.org/OpenBSD-#{Regexp.escape(release)}/[A-Za-z0-9_.+-]+\.[1-9]\z}
          local_page = %r{\Atarget-local:/\S+/man[1-9]/[A-Za-z0-9_.+-]+\.[1-9]\z}
          unless source.match?(versioned_url) || source.match?(local_page)
            raise TaskContract::Invalid, "OpenBSD manual source must be target-local or exact-release versioned: #{page_id}"
          end
          content = item.fetch("content").to_s
          raise TaskContract::Invalid, "OpenBSD manual receipt is not marked complete: #{page_id}" unless item.fetch("complete") == true
          title = content.lines.first(8).join
          unless title.match?(/#{Regexp.escape(page)}\\s*\\(#{Regexp.escape(section)}\\)/i)
            raise TaskContract::Invalid, "OpenBSD manual content does not identify #{page_id} in its opening lines"
          end
          if content.bytesize < 64 || content.lines.length < 3
            raise TaskContract::Invalid, "OpenBSD manual content is too short to be a complete read: #{page_id}"
          end
          manual_total += content.bytesize
          raise TaskContract::Invalid, "OpenBSD manual content exceeds #{MAX_BYTES} bytes" if manual_total > MAX_BYTES
          digest = Digest::SHA256.hexdigest(content.b)
          bytes = content.bytesize
          lines = content.lines.length
          validate_measurements!(item, digest:, bytes:, lines:, label: page_id)
          {
            "page" => page.freeze, "section" => section.freeze, "source" => source.freeze,
            "content" => content.freeze, "complete" => true, "sha256" => digest.freeze,
            "bytes" => bytes, "lines" => lines
          }.freeze
        end
        manual_ids = manual_pages.map { |page| "#{page.fetch("page")}(#{page.fetch("section")})" }.uniq
        missing_manuals = interfaces - manual_ids
        unless missing_manuals.empty?
          raise TaskContract::Invalid, "native interfaces lack full manual receipts: #{missing_manuals.join(', ')}"
        end

        no_native_reason = attributes["no_native_interfaces_reason"].to_s.strip
        if interfaces.empty?
          if no_native_reason.length < 24
            raise TaskContract::Invalid, "no-native-interface preflight needs an evidence-based reason"
          end
        elsif attributes.key?("no_native_interfaces_reason")
          raise TaskContract::Invalid, "no_native_interfaces_reason must be absent when native interfaces are declared"
        end

        {
          "hostname" => hostname.freeze, "os_release" => release.freeze,
          "architecture" => architecture.freeze, "scope" => scope.freeze,
          "source_reads" => source_reads.freeze, "native_interfaces" => interfaces.freeze,
          "manual_pages" => manual_pages.freeze,
          "no_native_interfaces_reason" => (no_native_reason.freeze unless no_native_reason.empty?)
        }.compact.freeze
      rescue KeyError => error
        raise TaskContract::Invalid, "OpenBSD preflight receipt is incomplete: #{error.key}"
      end

      def validate_measurements!(item, digest:, bytes:, lines:, label:)
        { "sha256" => digest, "bytes" => bytes, "lines" => lines }.each do |key, actual|
          next unless item.key?(key)
          unless item.fetch(key) == actual
            raise TaskContract::Invalid, "OpenBSD preflight #{label} #{key} does not match full content"
          end
        end
      end

      def repository_content_digest(path, expected_content = nil, root: Master::REPO_ROOT)
        repository = File.realpath(root)
        absolute = File.expand_path(path.to_s, repository)
        unless absolute.start_with?(repository + File::SEPARATOR)
          raise TaskContract::Invalid, "OpenBSD preflight source escapes repository: #{path}"
        end
        cursor = repository
        relative = absolute.delete_prefix(repository + File::SEPARATOR)
        segments = relative.split(File::SEPARATOR)
        segments.each_with_index do |segment, index|
          cursor = File.join(cursor, segment)
          stat = File.lstat(cursor)
          raise TaskContract::Invalid, "OpenBSD preflight source contains a symlink: #{path}" if stat.symlink?
          if index < segments.length - 1 && !stat.directory?
            raise TaskContract::Invalid, "OpenBSD preflight source has a non-directory parent: #{path}"
          end
          if index == segments.length - 1
            raise TaskContract::Invalid, "OpenBSD preflight source is not a regular file: #{path}" unless stat.file?
            raise TaskContract::Invalid, "OpenBSD preflight source is hard-linked: #{path}" unless stat.nlink == 1
          end
        end
        actual = File.binread(absolute)
        if expected_content && actual != expected_content.to_s.b
          raise TaskContract::Invalid, "OpenBSD source read is stale or incomplete: #{path}"
        end
        Digest::SHA256.hexdigest(actual)
      rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => error
        raise TaskContract::Invalid, "OpenBSD preflight source cannot be read completely: #{path} (#{error.class})"
      end

      def repository_relative(path, root: Master::REPO_ROOT)
        repository = File.realpath(root)
        absolute = File.expand_path(path.to_s, repository)
        return unless absolute.start_with?(repository + File::SEPARATOR)
        absolute.delete_prefix(repository + File::SEPARATOR)
      rescue ArgumentError, SystemCallError
        nil
      end

      def source_staleness(preflight, root: Master::REPO_ROOT)
        Array(preflight.fetch("source_reads")).each do |row|
          actual = repository_content_digest(row.fetch("path"), nil, root:)
          return "source receipt is stale: #{row.fetch("path")}" unless actual == row.fetch("sha256")
        end
        nil
      rescue TaskContract::Invalid => error
        error.message
      end

      def ensure_task_contract_loaded!
        require_relative "task_contract" unless defined?(Master::Fix::TaskContract)
      end

      def refusal_for_path(path:, contract: nil, repo_root: Master::REPO_ROOT)
        ensure_task_contract_loaded!
        contract ||= TaskContract.current
        relative = repository_relative(path, root: repo_root)
        return unless relative == "OPENBSD" || relative&.start_with?("OPENBSD/")
        return "RTFM_FIRST requires an active TaskContract with openbsd_preflight" unless contract

        preflight = contract.openbsd_preflight
        return "RTFM_FIRST requires complete openbsd_preflight evidence before editing #{relative}" unless preflight
        unless preflight.fetch("scope").any? { |entry| TaskContract.covers?(relative, scope: [entry]) }
          return "RTFM_FIRST preflight does not cover edit target #{relative}"
        end
        absolute = File.expand_path(path.to_s, repo_root)
        if File.file?(absolute) && !preflight.fetch("source_reads").any? { |row| row.fetch("path") == relative }
          return "RTFM_FIRST requires a complete source-read receipt for existing target #{relative}"
        end
        source_staleness(preflight, root: repo_root)
      end

      def refusal_for_command(command:, contract: nil, repo_root: Master::REPO_ROOT)
        ensure_task_contract_loaded!
        contract ||= TaskContract.current
        text = command.to_s.strip
        return if text.empty? || bootstrap_command?(text)

        argv = Shellwords.shellsplit(text)
        tokens = argv.flat_map { |token| token.include?(" ") ? Shellwords.shellsplit(token) : [token] }
        if (target = openbsd_write_target(text, argv))
          reason = refusal_for_path(path: target, contract:, repo_root:)
          return reason if reason
        end
        command_manuals = COMMAND_MANUALS.filter_map do |name, page|
          page if tokens.any? { |token| File.basename(token) == name }
        end.uniq
        remote = openbsd_ssh_command?(argv)
        openbsd_script = tokens.any? { |token| token.match?(%r{(?:\A|/)OPENBSD/(?:bin|sbin)/}) } && !openbsd_read_only_command?(tokens)
        local_openbsd = RUBY_PLATFORM.match?(/openbsd/i)
        return unless remote || openbsd_script || (local_openbsd && command_manuals.any?)
        return "RTFM_FIRST requires an active TaskContract with openbsd_preflight before native use" unless contract

        preflight = contract.openbsd_preflight
        return "RTFM_FIRST requires complete target-release manuals before this native operation" unless preflight
        declared = Array(preflight.fetch("native_interfaces"))
        missing = command_manuals - declared
        return "RTFM_FIRST missing declared manual interface(s): #{missing.join(', ')}" unless missing.empty?
        if (remote || openbsd_script) && declared.empty?
          return "RTFM_FIRST requires native interfaces and complete manuals to be enumerated"
        end
        source_staleness(preflight, root: repo_root)
      rescue ArgumentError => error
        "RTFM_FIRST cannot parse operation argv for manual preflight: #{error.message}"
      end

      READ_ONLY_OPENBSD_COMMANDS = %w[
        cat head tail grep egrep fgrep rg less more man file stat wc
        sha256 sha512 md5 od hexdump strings echo printf pwd
      ].freeze
      WRITE_OPENBSD_COMMANDS = %w[
        cp mv install tee touch rm mkdir rmdir chmod chown chgrp ln truncate dd
      ].freeze

      def openbsd_write_target(command, argv)
        tokens = Array(argv).map(&:to_s)
        redirects = []
        tokens.each_with_index do |token, index|
          if %w[> >> >| >&].include?(token)
            redirects << tokens[index + 1].to_s
          elsif token.match?(/\A\d*(?:>>?|>\|)/)
            target = token.sub(/\A\d*(?:>>?|>\|)/, "")
            redirects << target unless target.empty?
          elsif token.match?(/\A&>>?/)
            target = token.sub(/\A&>>?/, "")
            redirects << target unless target.empty?
          end
        end
        redirect = redirects.find { |target| target.include?("OPENBSD/") }
        return redirect if redirect

        mentions = command.to_s.scan(
          %r{(?<![A-Za-z0-9_])(?:/[^\s"';&|()]+)?OPENBSD/[^\s"';&|)]+}
        ).map { |path| path.sub(/[),;]+\z/, "") }.uniq
        return if mentions.empty?
        return mentions.first if tokens.any? { |token| WRITE_OPENBSD_COMMANDS.include?(File.basename(token)) }
        return mentions.first if tokens.any? { |token| token == "-i" || token.start_with?("-i") && token.length > 2 }

        return if openbsd_read_only_command?(tokens)
        mentions.first
      end

      def openbsd_read_only_command?(tokens)
        executable = File.basename(tokens.first.to_s)
        return true if READ_ONLY_OPENBSD_COMMANDS.include?(executable)
        executable == "git" && %w[status diff show log ls-files].include?(tokens[1].to_s)
      end

      def openbsd_ssh_command?(argv)
        return false unless File.basename(Array(argv).first.to_s) == "ssh"

        index = 1
        while index < argv.length
          token = argv[index].to_s
          if token == "--"
            index += 1
            break
          elsif SSH_OPTIONS_WITH_VALUE.include?(token)
            index += 2
          elsif token.start_with?("-")
            index += 1
          else
            break
          end
        end
        destination = argv[index].to_s.split("@").last
        destination.match?(/\A(?:vm23|brgen\.no|www\.brgen\.no|server4|server4\.openbsd\.amsterdam|www\.openbsd\.amsterdam|[A-Za-z0-9.-]+\.openbsd\.amsterdam)\z/i)
      end

      def bootstrap_command?(command)
        argv = Shellwords.shellsplit(command)
        return true if File.basename(argv.first.to_s) == "man"
        return false unless File.basename(argv.first.to_s) == "ssh"

        index = 1
        while index < argv.length
          token = argv[index]
          if token == "--"
            index += 1
            break
          elsif SSH_OPTIONS_WITH_VALUE.include?(token)
            index += 2
          elsif token.start_with?("-")
            index += 1
          else
            break
          end
        end
        remote = argv[(index + 1)..] || []
        remote = Shellwords.shellsplit(remote.join(" ")) if remote.length == 1
        first = File.basename(remote.first.to_s)
        return true if first == "man"
        return true if first == "hostname" && remote.length == 1
        first == "uname" && (remote.include?("-srm") || remote.include?("-v"))
      rescue ArgumentError
        false
      end
    end
  end
end
