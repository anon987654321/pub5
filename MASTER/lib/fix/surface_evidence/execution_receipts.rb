# frozen_string_literal: true

module Master
  module Fix
    class SurfaceEvidence
      # Receipt builders for the surfaces that exercise other processes or
      # manifests: target-scoped test runners and the local deployment
      # contract, plus the eligibility checks and manifest helpers they share.
      private

      def target_has_tests?(inventory)
        if @target_label == "RAILS/__shared" || @target_label.start_with?("RAILS/__shared/")
          return %w[amber brgen bsdports].any? do |name|
            File.directory?(File.join(@root, "RAILS", name, "test"))
          end
        end

        inventory["records"].any? do |path, type, _size|
          type == "file" && (
            path.match?(%r{(?:\A|/)(?:test|tests|spec)(?:/|\z)}) ||
              File.basename(path).match?(/(?:_test|_spec)\.(?:rb|js|ts|jsx|tsx|mjs)\z/)
          )
        end
      end

      def target_has_deployment?
        rails_target? || @target_label == "OPENBSD" || @target_label.start_with?("OPENBSD/") ||
          @plan.sources.any? do |source|
            File.basename(source.path).match?(/\A(?:Procfile|Dockerfile|compose\.ya?ml|.*deploy.*|.*\.service)\z/i) ||
              source.path.match?(%r{(?:deploy|deployment|helm|terraform|k8s)/})
          end
      end

      def deployment_surface?
        target_has_deployment?
      end

      def test_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)
        return receipt("not_applicable", reason: "target contains no test or spec files") unless target_has_tests?(inventory)
        return test_deferred_receipt(source) unless @run_expensive

        commands = test_commands(inventory)
        return receipt("inconclusive", reason: "test files exist but no safe target-specific runner was discovered") if commands.empty?

        outcomes = run_test_commands(commands)
        failed = outcomes.select { |row| row["status"] == "failed" }
        inconclusive = outcomes.select { |row| row["status"] == "inconclusive" }
        evidence = test_evidence(source, outcomes)
        return test_failed_receipt(evidence, failed) if failed.any?
        return test_inconclusive_receipt(evidence, inconclusive) if inconclusive.any?

        receipt("assessed_clean", evidence:, counts: { "commands" => outcomes.size })
      rescue StandardError => e
        receipt("inconclusive", reason: "test runner unavailable: #{error_text(e)}")
      end

      def test_deferred_receipt(source)
        receipt("inconclusive", reason: "test execution deferred until a clean scanner candidate pass",
          evidence: { "source_sha256" => source["digest"] })
      end

      def run_test_commands(commands)
        deadline = command_deadline(TEST_TIMEOUT)
        commands.map do |definition|
          command = execute_command(
            definition.fetch(:argv),
            chdir: definition.fetch(:chdir),
            env: definition.fetch(:env, {}),
            deadline:,
          )
          command.merge("label" => definition.fetch(:label))
        end
      end

      def test_evidence(source, outcomes)
        {
          "method" => "target-specific test runner; no shell command interpolation",
          "source_sha256" => source["digest"],
          "commands" => outcomes.map { |row| row.slice("label", "status", "exit_status", "timed_out", "duration_ms", "stdout_sha256", "stderr_sha256", "message") },
        }
      end

      def test_failed_receipt(evidence, failed)
        receipt("violation_found", reason: "one or more test runners failed", evidence:, findings: failed.first(20))
      end

      def test_inconclusive_receipt(evidence, inconclusive)
        receipt("inconclusive", reason: "one or more test runners timed out or were unavailable", evidence:, findings: inconclusive.first(20))
      end

      def deployment_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)
        return receipt("not_applicable", reason: "target has no local deployment contract") unless deployment_surface?

        manifests = []
        problems = []
        collect_rails_apps_contract(manifests, problems)
        collect_openbsd_inventory_contract(manifests, problems)
        collect_master_web_contract(manifests, problems)
        deployment_summary_receipt(problems, manifests, source)
      rescue StandardError => e
        receipt("inconclusive", reason: "deployment contract probe failed: #{error_text(e)}")
      end

      def collect_rails_apps_contract(manifests, problems)
        return unless @tree == "RAILS" || @target_label.start_with?("OPENBSD")

        apps_path = File.join(@root, "RAILS", "apps.yml")
        unless File.file?(apps_path) && !File.symlink?(apps_path)
          problems << "RAILS/apps.yml is missing or symlinked"
          return
        end

        begin
          validate_rails_deploy_apps(YAML.safe_load_file(apps_path).fetch("apps"), manifests, problems)
        rescue StandardError => e
          problems << "RAILS/apps.yml: #{error_text(e)}"
        end
      end

      def validate_rails_deploy_apps(apps, manifests, problems)
        selected_apps(apps.keys).each do |name|
          metadata = apps.fetch(name)
          script = metadata["deploy_script"].to_s
          deploy_root = metadata["deploy_root"].to_s
          validate_repo_path(script, "deploy script", problems)
          validate_repo_path(deploy_root, "deploy root", problems)
          script_path = File.expand_path(script, @root)
          root_path = File.expand_path(deploy_root, @root)
          validate_deploy_app_paths(name, script_path, root_path, problems)
          manifests << { "app" => name, "deploy_script" => script, "deploy_root" => deploy_root }
        end
      end

      def validate_deploy_app_paths(name, script_path, root_path, problems)
        problems << "#{name}: deploy script is missing or not a regular file" unless File.file?(script_path) && !File.symlink?(script_path)
        problems << "#{name}: deploy root is missing or not a directory" unless File.directory?(root_path) && !File.symlink?(root_path)
        problems << "#{name}: deploy script is not executable" if File.file?(script_path) && !File.executable?(script_path)
      end

      def collect_openbsd_inventory_contract(manifests, problems)
        return unless @target_label == "OPENBSD" || @target_label.start_with?("OPENBSD/")

        collect_openbsd_inventory_manifest(manifests, problems)
        vps_script = File.join(@root, "OPENBSD", "mirror", "bin", "vps-deploy")
        problems << "OPENBSD/bin/vps-deploy is missing or not executable" unless File.file?(vps_script) && !File.symlink?(vps_script) && File.executable?(vps_script)
      end

      def collect_openbsd_inventory_manifest(manifests, problems)
        inventory_path = File.join(@root, "OPENBSD", "deploy_inventory.json")
        unless File.file?(inventory_path) && !File.symlink?(inventory_path)
          problems << "OPENBSD/deploy_inventory.json is missing or symlinked"
          return
        end

        begin
          openbsd_inventory_findings(inventory_path, manifests, problems)
        rescue StandardError => e
          problems << "OPENBSD/deploy_inventory.json: #{error_text(e)}"
        end
      end

      def openbsd_inventory_findings(inventory_path, manifests, problems)
        data = JSON.parse(File.read(inventory_path, encoding: "UTF-8"))
        apps = Array(data["apps"])
        rails_apps = YAML.safe_load_file(File.join(@root, "RAILS", "apps.yml")).fetch("apps")
        inventory_by_name = apps.to_h { |row| [row.fetch("name"), row] }
        openbsd_inventory_schema_findings(data, apps, rails_apps, problems)
        validate_openbsd_inventory_apps(inventory_by_name, rails_apps, problems)
        manifests << { "inventory" => "OPENBSD/deploy_inventory.json", "apps" => apps.size }
      end

      def openbsd_inventory_schema_findings(data, apps, rails_apps, problems)
        return unless @target_label == "OPENBSD"

        inventory_names = apps.map { |row| row["name"].to_s }.sort
        problems << "OPENBSD deployment inventory names differ from RAILS/apps.yml" unless inventory_names == rails_apps.keys.map(&:to_s).sort
        problems << "OPENBSD deploy inventory schema is unsupported" unless data["schema"].to_i == 1
        problems << "OPENBSD deploy inventory generated_from is not RAILS/apps.yml" unless data["generated_from"].to_s == "RAILS/apps.yml"
      end

      def validate_openbsd_inventory_apps(inventory_by_name, rails_apps, problems)
        selected_apps(rails_apps.keys).each do |name|
          row = inventory_by_name[name]
          problems << "OPENBSD deploy inventory is missing #{name}" unless row
          next unless row

          metadata = rails_apps.fetch(name)
          %w[domain port].each do |key|
            problems << "#{name}: deploy inventory #{key} differs from RAILS/apps.yml" unless row[key].to_s == metadata[key].to_s
          end
        end
      end

      def collect_master_web_contract(manifests, problems)
        return unless @target_label == "MASTER/web" || @target_label.start_with?("MASTER/web/")

        master_web_inventory_findings(manifests, problems)
        vps_script = File.join(@root, "OPENBSD", "mirror", "bin", "vps-deploy")
        problems << "OPENBSD/bin/vps-deploy is missing or not executable" unless File.file?(vps_script) && !File.symlink?(vps_script) && File.executable?(vps_script)
      end

      def master_web_inventory_findings(manifests, problems)
        inventory_path = File.join(@root, "OPENBSD", "deploy_inventory.json")
        unless File.file?(inventory_path) && !File.symlink?(inventory_path)
          problems << "OPENBSD/deploy_inventory.json is missing or symlinked"
          return
        end

        begin
          found, manifest = master_inventory_findings(inventory_path)
          problems.concat(found)
          manifests << manifest if manifest
        rescue StandardError => e
          problems << "OPENBSD master manifest: #{error_text(e)}"
        end
      end

      def deployment_summary_receipt(problems, manifests, source)
        if problems.any?
          receipt("violation_found", reason: "deployment contract mismatch: #{problems.first(4).join("; ")}",
            findings: problems.first(30), evidence: { "manifests" => manifests })
        else
          receipt("assessed_clean", evidence: {
            "method" => "local deployment manifest, repository-contained script/root, and inventory parity checks",
            "manifests" => manifests,
            "source_sha256" => source["digest"],
            "live_deployment" => "not_measured; no deploy or remote mutation was performed",
          }, counts: { "manifest_entries" => manifests.size })
        end
      end

      def validate_repo_path(value, name, problems)
        text = value.to_s
        return unless text.empty? || text.start_with?("/") || text.split("/").include?("..")
          problems << "#{name} path is not repository-relative: #{text.inspect}"

      end

      # master's row in the deploy inventory must carry apps.yml's domain and port.
      def master_inventory_findings(inventory_path)
        row = master_inventory_row(inventory_path)
        metadata = YAML.safe_load_file(File.join(@root, "RAILS", "apps.yml")).dig("apps", "master")
        return [["OPENBSD deploy inventory has no master app"], nil] unless row.is_a?(Hash)
        return [["RAILS/apps.yml has no master app"], nil] unless metadata.is_a?(Hash)

        drift = %w[domain port].reject { |key| row[key].to_s == metadata[key].to_s }
        [drift.map { |key| "master: deploy inventory #{key} differs from RAILS/apps.yml" }, { "master" => row }]
      end

      def master_inventory_row(inventory_path)
        apps = Array(JSON.parse(File.read(inventory_path, encoding: "UTF-8"))["apps"])
        apps.find { |app| app["name"] == "master" }&.slice("name", "domain", "port")
      end

      def selected_apps(app_names)
        label = @target_label
        return app_names.map(&:to_s) if label == "RAILS" || label == "OPENBSD" ||
          label == "RAILS/__shared" || label.start_with?("RAILS/__shared/") ||
          label.start_with?("OPENBSD/")

        name = rails_target? && label != "RAILS" ? target_app_name : nil
        name && app_names.map(&:to_s).include?(name) ? [name] : []
      end
    end
  end
end
