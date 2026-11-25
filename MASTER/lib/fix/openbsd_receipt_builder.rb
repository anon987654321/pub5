# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"
require "time"
require_relative "task_contract"
require_relative "openbsd_manual_preflight"
require_relative "../io/atomic_write"

module Master
  module Fix
    # Builds the RTFM_FIRST receipt that OpenBSDManualPreflight validates.
    #
    # The receipt is evidence, not judgement: complete bytes of every tracked
    # OPENBSD source and the complete rendered manual of every interface the
    # mirror configures or the operator's remote commands invoke, read from the
    # target host itself. Only the two bootstrap exceptions touch the host
    # (`uname -srm` and `man`), so building it needs no prior receipt. The
    # validator, not this builder, decides admission: the envelope is normalised
    # through the same TaskContract path before it is written.
    module OpenBSDReceiptBuilder
      Preflight = OpenBSDManualPreflight
      SHELL_PAGES = Preflight::SHELL_MANUAL_PAGES
      OVERSTRIKE = /.\x08/m

      module_function

      # reader: ->(remote_command) { [output, ok] } over the operator's SSH.
      # commands: the exact remote command strings the release will send.
      def build(root:, reader:, hostname:, commands: [])
        release, architecture = target_identity(reader)
        pages = required_pages(root:, commands:, reader:)

        preflight = {
          "hostname" => hostname, "os_release" => release, "architecture" => architecture,
          "scope" => ["OPENBSD/**"], "source_reads" => source_reads(root),
          "native_interfaces" => pages,
          "manual_pages" => pages.map { |page| manual_receipt(reader, page) }
        }
        Preflight.normalize(preflight, task_scope: ["OPENBSD/**"])
        head = Preflight.repository_head(root:)
        { "head_sha" => head, "created_at" => Time.now.utc.iso8601, "openbsd_preflight" => preflight }
      end

      def write(envelope, root:)
        path = File.join(File.realpath(root), Preflight::RECEIPT_RELATIVE_PATH)
        Preflight.ensure_runtime_directory!(File.realpath(root))
        Master::Io::AtomicWrite.write_atomic(path, JSON.generate(envelope), mode: 0o600)
        path
      end

      def target_identity(reader)
        output, ok = reader.call("uname -srm")
        name, release, architecture = output.to_s.split
        return [release, architecture] if ok && name == "OpenBSD"

        raise TaskContract::Invalid, "target identity probe failed: #{output.to_s.strip[0, 160]}"
      end

      def source_reads(root)
        tracked(root).map do |path|
          content = File.binread(File.join(root, path)).force_encoding(Encoding::UTF_8)
          { "path" => path, "content" => content, "complete" => true }
        end
      end

      # Regular, non-empty tracked files: the validator refuses symlinks and
      # empty reads, and neither carries configuration the host consumes.
      def tracked(root)
        output, status = Open3.capture2("git", "-C", root, "ls-files", "-z", "--", "OPENBSD")
        raise TaskContract::Invalid, "cannot enumerate tracked OPENBSD sources" unless status.success?

        output.split("\0").select do |path|
          stat = File.lstat(File.join(root, path))
          stat.file? && stat.size.positive?
        end
      end

      # Mirror configuration maps, then every command the release sends, each
      # resolved the way the gate resolves it; shells are always read because
      # remote execution requires a declared shell page.
      def required_pages(root:, commands:, reader:)
        pages = Preflight.mirror_configuration_inventory(root:).flat_map { |entry| Array(entry.fetch("manuals")) }
        pages.concat(SHELL_PAGES)
        commands.each do |command|
          tokens = Shellwords.shellsplit(command)
          Preflight.remote_command_entries(tokens).each do |entry|
            pages.concat(command_pages(entry, root:, tokens:, reader:))
          end
        end
        pages.uniq
      end

      def command_pages(entry, root:, tokens:, reader:)
        name = entry.fetch(:name)
        return [] if Preflight::SHELL_BUILTINS.include?(name)

        sources = Preflight.openbsd_source_paths(tokens)
        script = sources.find { |path| File.basename(path) == File.basename(entry.fetch(:token).to_s) }
        return [Preflight.script_interpreter_manual(script, root:)].compact if script

        page = Preflight::COMMAND_MANUALS[name] || discovered_page(reader, name)
        [page, *Preflight::COMMAND_SUPPORT_MANUALS.fetch(name, [])]
      end

      # A command outside the canonical map is declared by the page the target
      # itself files it under, never by a guessed section.
      def discovered_page(reader, name)
        output, ok = reader.call(Shellwords.join(["man", "-w", name]))
        section = output.to_s.strip[%r{/man([1-9])/[^/\s]+\z}, 1]
        raise TaskContract::Invalid, "target has no manual page for remote command #{name}" unless ok && section

        "#{name}(#{section})"
      end

      def manual_receipt(reader, page_id)
        page, section = page_id.match(/\A(.+)\(([1-9])\)\z/).captures
        location, located = reader.call(Shellwords.join(["man", "-w", section, page]))
        path = location.to_s.lines.map(&:strip).find { |line| line.start_with?("/") }
        raise TaskContract::Invalid, "target has no manual page #{page_id}" unless located && path

        rendered, ok = reader.call(Shellwords.join(["man", section, page]))
        raise TaskContract::Invalid, "target manual #{page_id} could not be read" unless ok

        {
          "page" => page, "section" => section, "source" => "target-local:#{path}",
          "content" => rendered.to_s.gsub(OVERSTRIKE, ""), "complete" => true
        }
      end
    end
  end
end
