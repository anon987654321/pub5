# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "shellwords"
require "time"

module Master
  module Fix
    # Validated, content-bearing evidence for the OpenBSD RTFM_FIRST law.
    # This is deliberately part of TaskContract: the write and execution
    # boundaries consume the same receipt rather than trusting prompt text.
    module OpenBSDManualPreflight
      MAX_BYTES = 32 * 1024 * 1024
      MAX_SOURCE_READS = 96
      MAX_MANUAL_PAGES = 80
      RECEIPT_RELATIVE_PATH = "MASTER/.master/openbsd_preflight.json".freeze
      MAX_RECEIPT_FILE_BYTES = 68 * 1024 * 1024
      MAX_RECEIPT_AGE_SECONDS = 3_600

      COMMAND_MANUALS = {
        "pfctl" => "pfctl(8)", "rcctl" => "rcctl(8)", "doas" => "doas(1)",
        "ifconfig" => "ifconfig(8)", "route" => "route(8)", "netstat" => "netstat(1)",
        "sysctl" => "sysctl(8)", "pkg_add" => "pkg_add(1)", "pkg_delete" => "pkg_delete(1)",
        "pkg_info" => "pkg_info(1)", "relayd" => "relayd(8)", "httpd" => "httpd(8)",
        "sshd" => "sshd(8)", "smtpd" => "smtpd(8)", "smtpctl" => "smtpctl(8)",
        "rc" => "rc(8)", "syspatch" => "syspatch(8)", "upgrade" => "upgrade(8)",
        "acme-client" => "acme-client(1)", "newsyslog" => "newsyslog(8)",
        "nsd" => "nsd(8)", "nsd-checkconf" => "nsd-checkconf(8)",
        "nsd-checkzone" => "nsd-checkzone(8)", "nsd-control" => "nsd-control(8)",
        "relayctl" => "relayctl(8)", "makemap" => "makemap(8)",
        "cron" => "cron(8)", "zsh" => "zsh(1)", "ruby" => "ruby(1)",
        "git" => "git(1)", "stat" => "stat(1)", "ssh" => "ssh(1)",
        "mount" => "mount(8)", "umount" => "umount(8)", "disklabel" => "disklabel(8)",
        "bioctl" => "bioctl(8)", "installboot" => "installboot(8)", "fsck" => "fsck(8)",
        "useradd" => "useradd(8)", "usermod" => "usermod(8)", "userdel" => "userdel(8)",
        "chown" => "chown(8)", "chmod" => "chmod(1)", "reboot" => "reboot(8)",
        "shutdown" => "shutdown(8)", "halt" => "halt(8)"
      }.freeze

      # rcctl configures rc.conf.local and invokes rc.d scripts. Its safe use
      # depends on the complete rc startup framework, not only rcctl(8).
      RC_FRAMEWORK_MANUALS = %w[
        rcctl(8) rc(8) rc.conf(8) rc.d(8) rc.subr(8) ksh(1)
      ].freeze
      COMMAND_SUPPORT_MANUALS = {
        "rc" => RC_FRAMEWORK_MANUALS,
        "rcctl" => RC_FRAMEWORK_MANUALS,
        "pfctl" => %w[pf(4) pf.conf(5)],
        "relayd" => %w[relayd.conf(5) relayctl(8) pf(4)],
        "httpd" => %w[httpd.conf(5) slowcgi(8)],
        "smtpd" => %w[smtpd.conf(5) smtpctl(8)],
        "acme-client" => %w[acme-client.conf(5)],
        "newsyslog" => %w[newsyslog(8)],
        "nsd" => %w[nsd.conf(5) nsd-checkconf(8) nsd-control(8)],
        "nsd-checkconf" => %w[nsd.conf(5) nsd(8) nsd-control(8)],
        "nsd-checkzone" => %w[nsd.conf(5) nsd(8) nsd-control(8)],
        "nsd-control" => %w[nsd.conf(5) nsd(8) nsd-checkconf(8)]
      }.freeze
      RC_SERVICE_ACTIONS = %w[check configtest reload restart start stop].freeze
      RC_SERVICE_NAME = /\A[A-Za-z0-9_][A-Za-z0-9_.-]*\z/.freeze

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

        uncovered_scope = scope.reject do |entry|
          source_paths.any? { |path| TaskContract.covers?(path, scope: [entry]) }
        end
        unless uncovered_scope.empty?
          raise TaskContract::Invalid, "OpenBSD preflight has no source read inside scope: #{uncovered_scope.join(', ')}"
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
          unless title.match?(/#{Regexp.escape(page)}\s*\(#{Regexp.escape(section)}\)/i)
            raise TaskContract::Invalid, "OpenBSD manual content does not identify #{page_id} in its opening lines"
          end
          if content.bytesize < 128 || content.lines.length < 7
            raise TaskContract::Invalid, "OpenBSD manual content is too short to be a complete read: #{page_id}"
          end
          headings = content.lines.map(&:strip)
          missing_headings = %w[NAME SYNOPSIS DESCRIPTION].reject { |heading| headings.include?(heading) }
          unless missing_headings.empty?
            raise TaskContract::Invalid, "OpenBSD manual content is missing full-page sections for #{page_id}: #{missing_headings.join(', ')}"
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
        all_manual_ids = manual_pages.map { |page| "#{page.fetch("page")}(#{page.fetch("section")})" }
        raise TaskContract::Invalid, "duplicate OpenBSD manual-page receipts" unless all_manual_ids.uniq == all_manual_ids
        manual_ids = all_manual_ids
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

      # A receipt is written only after the agent has completed the read-only
      # discovery step. It lives in ignored runtime state, is bound to the exact
      # checkout HEAD, and is revalidated against live source bytes at admission.
      # This avoids constructing an impossible receipt before /fix has had a
      # chance to read its target and exact-release manuals.
      def contract_with_saved_preflight(contract:, repo_root: Master::REPO_ROOT, receipt_path: nil)
        return contract unless contract
        return contract if contract.openbsd_preflight
        return contract unless contract.scope.any? { |entry| entry == "OPENBSD" || entry.start_with?("OPENBSD/") }

        root = File.realpath(repo_root)
        path = receipt_path || File.join(root, RECEIPT_RELATIVE_PATH)
        return contract unless File.exist?(path) || File.symlink?(path)

        relative = repository_relative(path, root:)
        raise TaskContract::Invalid, "saved OpenBSD preflight must live inside the repository" unless relative
        relative_parent = File.dirname(relative)
        cursor = root
        relative_parent.split("/").each do |segment|
          cursor = File.join(cursor, segment)
          stat = File.lstat(cursor)
          raise TaskContract::Invalid, "saved OpenBSD preflight path contains a symlink" if stat.symlink?
          raise TaskContract::Invalid, "saved OpenBSD preflight parent is not a directory" unless stat.directory?
        end
        stat = File.lstat(path)
        raise TaskContract::Invalid, "saved OpenBSD preflight must be a regular file" unless stat.file?
        raise TaskContract::Invalid, "saved OpenBSD preflight must not be hard-linked" unless stat.nlink == 1
        raise TaskContract::Invalid, "saved OpenBSD preflight exceeds #{MAX_RECEIPT_FILE_BYTES} bytes" if stat.size > MAX_RECEIPT_FILE_BYTES

        payload = JSON.parse(File.binread(path))
        raise TaskContract::Invalid, "saved OpenBSD preflight must be a mapping" unless payload.is_a?(Hash)
        attributes = payload.to_h.transform_keys(&:to_s)
        required = %w[head_sha created_at openbsd_preflight]
        unknown = attributes.keys - required
        missing = required - attributes.keys
        raise TaskContract::Invalid, "saved OpenBSD preflight is missing: #{missing.join(', ')}" unless missing.empty?
        raise TaskContract::Invalid, "saved OpenBSD preflight has unknown fields: #{unknown.join(', ')}" unless unknown.empty?

        head = attributes.fetch("head_sha").to_s
        raise TaskContract::Invalid, "saved OpenBSD preflight HEAD is invalid" unless head.match?(/\A[0-9a-f]{40,64}\z/)
        actual_head = repository_head(root:)
        raise TaskContract::Invalid, "saved OpenBSD preflight belongs to another checkout revision" unless actual_head == head

        created_at = Time.iso8601(attributes.fetch("created_at").to_s)
        age = Time.now.utc - created_at
        if age < -300 || age > MAX_RECEIPT_AGE_SECONDS
          raise TaskContract::Invalid, "saved OpenBSD preflight expired; re-read target identity and manuals"
        end

        task_attributes = contract.to_h.reject { |key, _value| key == "schema" }
        task_attributes["openbsd_preflight"] = attributes.fetch("openbsd_preflight")
        TaskContract.build(task_attributes)
      rescue JSON::ParserError, KeyError, ArgumentError => error
        raise TaskContract::Invalid, "saved OpenBSD preflight is invalid: #{error.message}"
      rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => error
        raise TaskContract::Invalid, "saved OpenBSD preflight cannot be read safely: #{error.class}"
      end

      def repository_head(root: Master::REPO_ROOT)
        output, status = Open3.capture2e("git", "-C", root, "rev-parse", "HEAD")
        raise TaskContract::Invalid, "cannot establish current repository HEAD" unless status.success?
        value = output.to_s.strip
        raise TaskContract::Invalid, "current repository HEAD is invalid" unless value.match?(/\A[0-9a-f]{40,64}\z/)
        value
      rescue SystemCallError => error
        raise TaskContract::Invalid, "cannot establish current repository HEAD: #{error.class}"
      end

      def refusal_for_path(path:, contract: nil, repo_root: Master::REPO_ROOT, receipt_path: nil)
        ensure_task_contract_loaded!
        contract ||= TaskContract.current
        begin
          contract = contract_with_saved_preflight(contract:, repo_root:, receipt_path:)
        rescue TaskContract::Invalid => error
          return "RTFM_FIRST blocked: #{error.message}"
        end
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
        path_manuals = required_path_manuals(relative)
        if path_manuals.nil?
          return "RTFM_FIRST has no reviewed manual/schema map for native target #{relative}; identify its format, owner and validator before editing"
        end
        missing_manuals = path_manuals - Array(preflight.fetch("native_interfaces"))
        unless missing_manuals.empty?
          return "RTFM_FIRST missing required supporting manual page(s) for #{relative}: #{missing_manuals.join(', ')}"
        end
        source_staleness(preflight, root: repo_root)
      end

      def refusal_for_command(command:, contract: nil, repo_root: Master::REPO_ROOT, receipt_path: nil)
        ensure_task_contract_loaded!
        contract ||= TaskContract.current
        text = command.to_s.strip
        return if text.empty? || bootstrap_command?(text)
        begin
          contract = contract_with_saved_preflight(contract:, repo_root:, receipt_path:)
        rescue TaskContract::Invalid => error
          return "RTFM_FIRST blocked: #{error.message}"
        end

        argv = Shellwords.shellsplit(text)
        tokens = argv.flat_map { |token| token.include?(" ") ? Shellwords.shellsplit(token) : [token] }
        if (target = openbsd_write_target(text, argv))
          reason = refusal_for_path(path: target, contract:, repo_root:)
          return reason if reason
        end
        command_names = tokens.map { |token| File.basename(token) }
        command_manuals = COMMAND_MANUALS.filter_map do |name, page|
          page if command_names.include?(name)
        end
        command_manuals.concat(command_names.flat_map { |name| COMMAND_SUPPORT_MANUALS.fetch(name, []) })
        command_manuals.uniq!
        service_sources = rc_service_source_paths(tokens)
        openbsd_sources = openbsd_source_paths(tokens)
        remote = openbsd_ssh_command?(argv)
        openbsd_script = tokens.any? { |token| token.match?(%r{(?:\A|/)OPENBSD/}) } && !openbsd_read_only_command?(tokens)
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
        missing_service_sources = service_source_refusals(service_sources, preflight, root: repo_root)
        return missing_service_sources.first unless missing_service_sources.empty?
        missing_openbsd_sources = source_read_refusals(openbsd_sources, preflight, root: repo_root)
        return missing_openbsd_sources.first unless missing_openbsd_sources.empty?
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

      # Configuration and service files have supporting manual pages in
      # addition to the command page that edits or controls them.
      def required_path_manuals(relative)
        path = relative.to_s.tr("\\", "/")
        return RC_FRAMEWORK_MANUALS if path.match?(%r{\AOPENBSD/etc/rc\.d/[^/]+\z})
        return %w[rc(8) rc.conf(8) rc.d(8) rcctl(8)] if path.match?(%r{\AOPENBSD/etc/rc\.conf(?:\.local)?\z})
        return %w[pf(4) pf.conf(5) pfctl(8)] if path.match?(%r{\AOPENBSD/etc/pf(?:\.stage1)?\.conf\z})
        return %w[relayd.conf(5) relayd(8) relayctl(8) pf(4)] if path == "OPENBSD/etc/relayd.conf"
        return %w[httpd.conf(5) httpd(8) slowcgi(8)] if path == "OPENBSD/etc/httpd.conf"
        return %w[acme-client.conf(5) acme-client(1)] if path == "OPENBSD/etc/acme-client.conf"
        return %w[doas.conf(5) doas(1)] if path == "OPENBSD/etc/doas.conf"
        return %w[login.conf(5) login(1)] if path == "OPENBSD/etc/login.conf"
        return %w[smtpd.conf(5) smtpd(8) smtpctl(8)] if path == "OPENBSD/etc/mail/smtpd.conf"
        return %w[smtpd.conf(5) table(5) smtpd(8) makemap(8)] if %w[OPENBSD/etc/mail/domains OPENBSD/etc/mail/virtuals].include?(path)
        return %w[newsyslog(8)] if path == "OPENBSD/etc/newsyslog.conf"
        return %w[daily(8) cron(8) ksh(1)] if %w[OPENBSD/etc/daily.local OPENBSD/etc/weekly.local].include?(path)
        return %w[crontab(5) cron(8) ksh(1) zsh(1) ruby(1)] if path == "OPENBSD/etc/crontab.vm23"
        return %w[zsh(1)] if path == "OPENBSD/etc/.zshrc"
        return %w[sshd_config(5) sshd(8) ssh(1)] if path == "OPENBSD/etc/ssh/sshd_config"
        return %w[nsd.conf(5) nsd(8) nsd-checkconf(8) nsd-control(8)] if path == "OPENBSD/var/nsd/etc/nsd.conf"
        if path.match?(%r{\AOPENBSD/var/nsd/zones/master/[^/]+\.zone\z})
          return %w[nsd.conf(5) nsd(8) nsd-checkzone(8) nsd-control(8)]
        end
        return nil if path.start_with?("OPENBSD/etc/", "OPENBSD/var/")

        []
      end

      def rc_service_source_paths(tokens)
        paths = []
        tokens.each_with_index do |token, index|
          next unless File.basename(token) == "rcctl"

          tail = tokens[(index + 1)..] || []
          action_index = tail.index { |value| RC_SERVICE_ACTIONS.include?(value) }
          next unless action_index

          services = tail[(action_index + 1)..] || []
          services.each do |service|
            next if service.start_with?("-")
            break unless service.match?(RC_SERVICE_NAME)

            paths << "OPENBSD/etc/rc.d/#{service}"
          end
        end
        tokens.each do |token|
          match = token.match(%r{(?:\A|/)etc/rc\.d/([^/]+)\z})
          paths << "OPENBSD/etc/rc.d/#{match[1]}" if match
        end
        paths.uniq
      end

      def openbsd_source_paths(tokens)
        Array(tokens).filter_map do |token|
          match = token.to_s.match(%r{(?:\A|/)OPENBSD/[A-Za-z0-9_.\/-]+})
          next unless match

          candidate = match[0].sub(/\A.*?(?=OPENBSD\/)/, "")
          candidate = candidate.sub(/[),;]+\z/, "")
          TaskContract.safe_path(candidate)
          candidate if candidate.start_with?("OPENBSD/")
        rescue TaskContract::Invalid
          nil
        end.uniq
      end

      def source_read_refusals(paths, preflight, root:)
        reads = Array(preflight.fetch("source_reads")).map { |row| row.fetch("path") }
        paths.filter_map do |relative|
          absolute = File.expand_path(relative, root)
          unless File.file?(absolute)
            next "RTFM_FIRST has no reviewed repository source for OpenBSD path #{relative}"
          end
          unless reads.include?(relative)
            next "RTFM_FIRST requires a complete source-read receipt for OpenBSD path #{relative}"
          end
          nil
        end
      end

      def service_source_refusals(paths, preflight, root:)
        reads = Array(preflight.fetch("source_reads")).map { |row| row.fetch("path") }
        paths.filter_map do |relative|
          absolute = File.expand_path(relative, root)
          unless File.file?(absolute)
            next "RTFM_FIRST has no reviewed repository source for controlled service #{relative}"
          end
          unless reads.include?(relative)
            next "RTFM_FIRST requires a complete source-read receipt for controlled service #{relative}"
          end

          path_manuals = required_path_manuals(relative)
          if path_manuals.nil?
            next "RTFM_FIRST has no reviewed manual map for controlled service #{relative}"
          end
          missing = path_manuals - Array(preflight.fetch("native_interfaces"))
          unless missing.empty?
            next "RTFM_FIRST missing required supporting manual page(s) for #{relative}: #{missing.join(', ')}"
          end
          nil
        end
      end

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
