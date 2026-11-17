# frozen_string_literal: true

module Master
  module Fix
    class SurfaceEvidence
      # The bounded no-follow target inventory, the FixPlan source manifest and
      # the discovery of safe target-scoped test runner commands from inventory
      # records.
      private

      def inventory_snapshot
        root = File.directory?(@target) ? @target : nil
        return { "status" => "inconclusive", "reason" => "target is not a directory", "records" => [] } unless root

        walk_target_inventory(root)
      rescue StandardError => e
        { "status" => "inconclusive", "reason" => "inventory failed: #{error_text(e)}", "records" => [] }
      end

      def walk_target_inventory(root)
        records = []
        ignored = []
        symlinks = 0
        pending = [root]
        until pending.empty?
          directory = pending.pop
          Dir.children(directory).sort.each do |name|
            record = inventory_record(pending, File.join(directory, name), ignored)
            next unless record

            symlinks += 1 if record[1] == "symlink"
            records << record
            return truncated_inventory(records, ignored, symlinks) if records.size > INVENTORY_CAP
          end
        end
        finished_inventory(records, ignored, symlinks)
      end

      def inventory_record(pending, path, ignored)
        relative_path = relative(path)
        stat = File.lstat(path)
        if stat.symlink?
          [relative_path, "symlink", stat.size]
        elsif stat.directory?
          inventory_directory_record(pending, path, relative_path, ignored)
        elsif stat.file?
          [relative_path, "file", stat.size]
        else
          [relative_path, "other", stat.size]
        end
      end

      def inventory_directory_record(pending, path, relative_path, ignored)
        if ignored_directory?(relative_path)
          ignored << relative_path
          return nil
        end

        pending << path
        [relative_path, "directory", 0]
      end

      def truncated_inventory(records, ignored, symlinks)
        {
          "status" => "inconclusive", "reason" => "target inventory exceeded cap #{INVENTORY_CAP}",
          "records" => records.first(INVENTORY_CAP), "truncated" => true,
          "files" => records.count { |row| row[1] == "file" },
          "directories" => records.count { |row| row[1] == "directory" },
          "symlinks" => symlinks, "ignored_directories" => ignored.first(100),
          "digest" => digest_json(records.first(INVENTORY_CAP)),
        }
      end

      def finished_inventory(records, ignored, symlinks)
        records.sort_by!(&:first)
        {
          "status" => "captured",
          "records" => records,
          "files" => records.count { |row| row[1] == "file" },
          "directories" => records.count { |row| row[1] == "directory" },
          "symlinks" => symlinks,
          "ignored_directories" => ignored.sort,
          "truncated" => false,
          "digest" => digest_json(records),
        }
      end

      def ignored_directory?(relative_path)
        parts = relative_path.split("/")
        nested, single = IGNORED_DIRECTORIES.partition { |entry| entry.include?("/") }
        parts.any? { |part| single.include?(part) } ||
          nested.any? { |entry| parts.each_cons(entry.count("/") + 1).include?(entry.split("/")) }
      end

      def source_manifest
        rows = []
        failures = []
        Array(@plan&.sources).each { |item| collect_source_manifest_row(item, rows, failures) }
        summarize_source_manifest(rows, failures)
      rescue StandardError => e
        { "status" => "inconclusive", "reason" => "source manifest failed: #{error_text(e)}", "digest" => "" }
      end

      def collect_source_manifest_row(item, rows, failures)
        path = File.expand_path(item.path, @root)
        unless File.file?(path) && !File.symlink?(path)
          failures << relative(path)
          return
        end

        before = File.stat(path)
        sha = Digest::SHA256.file(path).hexdigest
        after = File.stat(path)
        if stat_signature(before) != stat_signature(after) || after.size != item.bytes || sha != item.sha256
          failures << relative(path)
          return
        end
        rows << [item.path, sha, after.size]
      rescue StandardError
        failures << item.path
      end

      def summarize_source_manifest(rows, failures)
        rows.sort_by!(&:first)
        digest = digest_json(rows)
        expected = @plan&.source_digest.to_s
        status = failures.empty? && !expected.empty? && digest == expected ? "captured" : "inconclusive"
        {
          "status" => status,
          "digest" => digest,
          "expected_digest" => expected,
          "source_count" => rows.size,
          "failures" => failures.first(30),
          "reason" => status == "captured" ? nil : "FixPlan source bytes or metadata no longer match: #{failures.first(4).join(", ")}",
        }.compact
      end

      def test_commands(inventory)
        paths = inventory["records"].filter_map { |row| row[0] if row[1] == "file" }
        label = @target_label
        return web_test_commands(label, paths) if web_target?
        return master_test_commands(label, paths) if label == "MASTER" || label.start_with?("MASTER/")
        return openbsd_test_commands(label, paths) if label == "OPENBSD" || label.start_with?("OPENBSD/")
        return studio_test_commands(label, paths) if label == "STUDIO" || label.start_with?("STUDIO/")
        return rails_test_commands(label, paths) if label == "RAILS" || label.start_with?("RAILS/")

        []
      end

      def master_test_commands(label, paths)
        tests = paths.any? { |path| path.start_with?("MASTER/test/") || path.start_with?("MASTER/tools/test/") }
        return [] unless tests && File.file?(File.join(@root, "MASTER", "Rakefile"))

        [{ label: "MASTER rake test", argv: [RbConfig.ruby, "-S", "rake", "test"], chdir: File.join(@root, "MASTER") }]
      end

      def openbsd_test_commands(label, paths)
        return [] unless paths.any? { |path| path.start_with?("OPENBSD/test/") } && File.file?(File.join(@root, "OPENBSD", "test", "run_all.rb"))

        [{ label: "OPENBSD test/run_all.rb", argv: [RbConfig.ruby, "test/run_all.rb"], chdir: File.join(@root, "OPENBSD") }]
      end

      def studio_test_commands(label, paths)
        return [] unless paths.any? { |path| path.start_with?("STUDIO/test/") } && File.file?(File.join(@root, "STUDIO", "Rakefile"))

        [{ label: "STUDIO rake test", argv: [RbConfig.ruby, "-S", "rake", "test"], chdir: File.join(@root, "STUDIO") }]
      end

      def rails_test_commands(label, paths)
        commands = []
        rails_root = File.join(@root, "RAILS")
        if label == "RAILS" && paths.any? { |path| path.start_with?("RAILS/test/") } &&
           File.file?(File.join(rails_root, "test", "run_all.rb"))
          commands << { label: "RAILS test/run_all.rb", argv: [RbConfig.ruby, "test/run_all.rb"], chdir: rails_root }
        end

        rails_app_test_targets(label, paths).each do |name, app_dir|
          commands << {
            label: "RAILS #{name} bin/rails test",
            argv: [RbConfig.ruby, "bin/rails", "test"],
            chdir: app_dir,
            env: { "RAILS_ENV" => "test" },
          }
        end
        commands
      end

      # MASTER/web is a Rails app inside MASTER: its suite is bin/rails test, not MASTER's rake.
      def web_test_commands(label, paths)
        argv = [RbConfig.ruby, "bin/rails", "test"]
        rails_app_test_targets(label, paths).map do |_name, app_dir|
          { label: "MASTER/web bin/rails test", argv:, chdir: app_dir, env: { "RAILS_ENV" => "test" } }
        end
      end

      def rails_app_test_targets(label, paths)
        return [] unless rails_target?

        app_names = []
        if label == "RAILS"
          app_names = %w[amber brgen bsdports]
        elsif label == "RAILS/__shared" || label.start_with?("RAILS/__shared/")
          app_names = %w[amber brgen bsdports]
        else
          app_names = [target_app_name]
        end
        app_names.filter_map do |name|
          app_dir = app_dir(name)
          test_path = File.join(app_dir, "test")
          rails_bin = File.join(app_dir, "bin", "rails")
          next unless File.directory?(test_path) && File.file?(rails_bin) && !File.symlink?(rails_bin)
          next unless label == "RAILS" || label == "RAILS/__shared" || label.start_with?("RAILS/__shared/") ||
            paths.any? { |path| path.start_with?("#{relative(app_dir)}/") }

          [name, app_dir]
        end
      end
    end
  end
end
