# frozen_string_literal: true

module Master
  module Fix
    class SurfaceEvidence
      # The runtime surface receipt: language parser probes (Ruby, ERB,
      # JavaScript, shell) plus safe Rails application boot probes, run under a
      # shared deadline and never through a shell.
      private

      RUBY_SYNTAX_PROBE = <<~'RUBY'.freeze
        ARGV.each do |path|
          begin
            if defined?(RubyVM::InstructionSequence)
              RubyVM::InstructionSequence.compile_file(path)
            elsif !require("ripper") || !Ripper.sexp(File.read(path))
              raise SyntaxError, "parse failed"
            end
          rescue StandardError, ScriptError => error
            warn "#{path}: #{error.class}: #{error.message}"
            exit 1
          end
        end
      RUBY
      ERB_SYNTAX_PROBE = <<~'RUBY'.freeze
        require "erb"
        ARGV.each do |path|
          begin
            source = ERB.new(File.read(path), trim_mode: "-").src
            if defined?(RubyVM::InstructionSequence)
              RubyVM::InstructionSequence.compile(source, path)
            elsif !require("ripper") || !Ripper.sexp(source)
              raise SyntaxError, "parse failed"
            end
          rescue StandardError, ScriptError => error
            warn "#{path}: #{error.class}: #{error.message}"
            exit 1
          end
        end
      RUBY
      private_constant :RUBY_SYNTAX_PROBE, :ERB_SYNTAX_PROBE

      def runtime_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)
        runtime_paths = runtime_paths_for(RUNTIME_EXTENSIONS)
        return receipt("not_applicable", reason: "target contains no supported runtime source files") if runtime_paths.empty?
        unless @run_expensive
          return receipt("inconclusive", reason: "runtime probes deferred until a clean scanner candidate pass",
            evidence: { "source_sha256" => source["digest"] })
        end

        results = runtime_probe_outcomes(command_deadline(RUNTIME_TIMEOUT))
        runtime_receipt_result(source, results)
      rescue StandardError => e
        receipt("inconclusive", reason: "runtime probe failed: #{error_text(e)}")
      end

      def runtime_paths_for(extensions)
        @plan.sources.map(&:path).select { |path| extensions.include?(File.extname(path).downcase) }
      end

      def runtime_probe_outcomes(deadline)
        failures = []
        unavailable = []
        checked = Hash.new(0)
        runtime_ruby_probe(runtime_paths_for(%w[.rb .rake .gemspec]), deadline, checked, failures, unavailable)
        runtime_erb_probe(runtime_paths_for([".erb"]), deadline, checked, failures, unavailable)
        runtime_javascript_probe(deadline, checked, failures, unavailable)
        shell_groups = runtime_shell_groups
        runtime_shell_probes(shell_groups, deadline, checked, failures, unavailable)
        boot = rails_runtime_probes(deadline)
        failures.concat(boot[:failures])
        unavailable.concat(boot[:unavailable])
        { failures:, unavailable:, checked:, boot:, shell_groups: }
      end

      def runtime_ruby_probe(paths, deadline, checked, failures, unavailable)
        return if paths.empty?

        command = [RbConfig.ruby, "-e", RUBY_SYNTAX_PROBE, *paths.map { |path| File.expand_path(path, @root) }]
        outcome = execute_command(command, chdir: @root, deadline:)
        checked["ruby"] = paths.size
        if outcome["status"] == "failed"
          failures << outcome.merge("language" => "ruby")
        elsif outcome["status"] == "inconclusive"
          unavailable << "Ruby syntax probe unavailable or timed out"
        end
      end

      def runtime_erb_probe(paths, deadline, checked, failures, unavailable)
        return if paths.empty?
        return unavailable << "ERB syntax probe exceeded runtime budget" unless deadline_remaining(deadline).positive?

        outcome = execute_command(
          [RbConfig.ruby, "-e", ERB_SYNTAX_PROBE, *paths.map { |path| File.expand_path(path, @root) }],
          chdir: @root, deadline:
        )
        checked["erb"] = paths.size
        if outcome["status"] == "failed"
          failures << outcome.merge("language" => "erb")
        elsif outcome["status"] == "inconclusive"
          unavailable << "ERB probe unavailable or timed out"
        end
      end

      def runtime_javascript_probe(deadline, checked, failures, unavailable)
        typed_paths = runtime_paths_for(%w[.jsx .ts .tsx])
        unless typed_paths.empty?
          unavailable << "#{typed_paths.size} TypeScript/JSX file(s) need a project-aware parser; Node --check is not evidence for these formats"
        end
        paths = runtime_paths_for(%w[.js .mjs .cjs])
        return if paths.empty?

        node = executable_path("node")
        return unavailable << "#{paths.size} JavaScript file(s) found but Node.js is unavailable" unless node

        runtime_javascript_file_probes(paths, node, deadline, checked, failures, unavailable)
      end

      def runtime_javascript_file_probes(paths, node, deadline, checked, failures, unavailable)
        paths.each do |path|
          break if deadline_remaining(deadline) <= 0

          outcome = execute_command([node, "--check", File.expand_path(path, @root)], chdir: @root, deadline:)
          checked["javascript"] += 1
          if outcome["status"] == "failed"
            failures << outcome.merge("language" => "javascript", "file" => path)
          elsif outcome["status"] == "inconclusive"
            unavailable << "#{path}: JavaScript parser unavailable or timed out"
          end
        end
        if checked["javascript"] < paths.size
          unavailable << "#{paths.size - checked["javascript"]} JavaScript file(s) not parsed before budget"
        end
      end

      def runtime_shell_groups
        {
          "sh" => %w[.sh .bash],
          "ksh" => [".ksh"],
          "zsh" => [".zsh"],
        }
      end

      def runtime_shell_probes(groups, deadline, checked, failures, unavailable)
        groups.each do |shell, extensions|
          runtime_shell_probe(shell, extensions, deadline, checked, failures, unavailable)
        end
      end

      def runtime_shell_probe(shell, extensions, deadline, checked, failures, unavailable)
        paths = runtime_paths_for(extensions)
        return if paths.empty?

        executable = executable_path(shell)
        unless executable
          unavailable << "#{paths.size} #{shell} script(s) found but #{shell} is unavailable"
          return
        end
        runtime_shell_file_probes(shell, executable, paths, deadline, checked, failures, unavailable)
      end

      def runtime_shell_file_probes(shell, executable, paths, deadline, checked, failures, unavailable)
        paths.each do |path|
          break if deadline_remaining(deadline) <= 0

          outcome = execute_command([executable, "-n", File.expand_path(path, @root)], chdir: @root, deadline:)
          checked[shell] += 1
          if outcome["status"] == "failed"
            failures << outcome.merge("language" => shell, "file" => path)
          elsif outcome["status"] == "inconclusive"
            unavailable << "#{path}: #{shell} parser unavailable or timed out"
          end
        end
        unavailable << "#{paths.size - checked[shell]} #{shell} script(s) not parsed before budget" if checked[shell] < paths.size
      end

      def runtime_receipt_result(source, results)
        details = runtime_receipt_details(source, results)
        return receipt("violation_found", reason: "one or more runtime syntax or boot probes failed",
          evidence: details, findings: results[:failures].first(20)) if results[:failures].any?
        return receipt("inconclusive", reason: results[:unavailable].first(4).join("; "), evidence: details) if results[:unavailable].any?

        receipt("assessed_clean", evidence: details, counts: {
          "ruby" => results[:checked]["ruby"],
          "erb" => results[:checked]["erb"],
          "javascript" => results[:checked]["javascript"],
          "shell" => results[:shell_groups].keys.sum { |key| results[:checked][key] },
          "rails_boots" => results[:boot][:checked].size,
        })
      end

      def runtime_receipt_details(source, results)
        {
          "method" => "language parser checks plus safe Rails application boot probes where applicable",
          "source_sha256" => source["digest"],
          "checked" => results[:checked],
          "rails_boots" => results[:boot][:checked],
          "failures" => results[:failures].first(20).map { |row| row.slice("language", "file", "status", "exit_status", "message") },
          "unavailable" => results[:unavailable].first(20),
        }
      end

      def rails_runtime_probes(deadline)
        return { failures: [], unavailable: [], checked: [] } unless rails_target?
        return { failures: [], unavailable: ["Rails boot probes deferred until a clean scanner candidate pass"], checked: [] } unless @run_expensive

        rails_runtime_probe_results(deadline)
      end

      def rails_runtime_probe_results(deadline)
        failures = []
        unavailable = []
        checked = []
        rails_runtime_app_targets(unavailable).each do |name, app_dir|
          rails_app_boot_probe(name, app_dir, deadline, checked, failures, unavailable)
        end
        { failures:, unavailable:, checked: }
      end

      def rails_runtime_app_targets(unavailable)
        app_names = if @target_label == "RAILS" || @target_label == "RAILS/__shared" || @target_label.start_with?("RAILS/__shared/")
                      %w[amber brgen bsdports]
                    else
                      [target_app_name]
                    end
        app_names.filter_map do |name|
          app_dir = app_dir(name)
          runner = File.join(app_dir, "bin", "rails")
          if File.directory?(app_dir) && File.file?(runner) && !File.symlink?(runner)
            [name, app_dir]
          else
            unavailable << "#{name}: Rails app directory or bin/rails launcher is unavailable"
            nil
          end
        end
      end

      def rails_app_boot_probe(name, app_dir, deadline, checked, failures, unavailable)
        if deadline_remaining(deadline) <= 0
          unavailable << "Rails app boot budget exhausted before #{name}" unless checked.include?(name)
          return
        end

        row = execute_command(
          [RbConfig.ruby, "bin/rails", "runner", "puts Rails.application.routes.routes.size"],
          chdir: app_dir, env: { "RAILS_ENV" => "test" }, deadline:,
        )
        checked << name
        if row["status"] == "failed"
          failures << row.merge("app" => name)
        elsif row["status"] == "inconclusive"
          unavailable << "#{name}: Rails boot probe timed out or was unavailable"
        end
      end

      def executable_path(name)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |directory| File.join(directory, name) }.
          find { |candidate| File.file?(candidate) && File.executable?(candidate) }
      end
    end
  end
end
