# frozen_string_literal: true

require "open3"
require "json"
require "shellwords"
require "rbconfig"
require "bundler"
require_relative "../boot/paths"
require_relative "../result"
require_relative "exec"

module Master
  module Io
    # Single Open3 entrypoint for MASTER/tools/*.rb scripts (replicate, postpro, …).
    module ScriptDispatch
      module_function

      # Public tool names resolve to one canonical entrypoint. STUDIO owns the
      # whole provider boundary. LoRA generation uses the photograph entrypoint
      # plus a subject profile; data and weights stay under STUDIO/lora.
      # The repo/ and research/ rows name tools whose canonical entrypoint is
      # nested below their family directory; the legacy root shims are gone.
      TOOL_ENTRYPOINTS = {
        "replicate" => File.join("replicate", "client.rb"),
        "lora" => "photograph.rb",
        "runs" => File.join("repo", "runs.rb"),
        "repo_inventory" => File.join("repo", "repo_inventory.rb"),
        "sprawl_plan" => File.join("repo", "sprawl_plan.rb"),
        "cognition_benchmark" => File.join("research", "cognition_benchmark.rb"),
        "llm_challenges" => File.join("research", "llm_challenges.rb"),
        "llm_trajectory" => File.join("research", "llm_trajectory.rb"),
      }.freeze

      # The STUDIO tools each expose `api '<json>'`: one request in, one JSON
      # response out. These are their CLI entrypoints (the file that answers
      # "api"), which differ from the render entrypoint in TOOL_ENTRYPOINTS for
      # lora and replicate.
      API_ENTRYPOINTS = {
        "dilla" => File.join("dilla", "dilla.rb"),
        "postpro" => File.join("postpro", "postpro.rb"),
        "lora" => File.join("lora", "lora.rb"),
        "replicate" => File.join("replicate", "replicate.rb"),
        "photograph" => "photograph.rb",
      }.freeze

      def run(root:, tool:, arg: "", env: {})
        name = tool.to_s
        requested_root = File.expand_path(root.to_s.empty? ? Dir.pwd : root)
        script = script_path(requested_root, name)
        return Result.err("#{tool}: missing tool entrypoint #{script}", category: :validation) unless File.file?(script)

        argv = Shellwords.split(arg.to_s)
        cmd = env.empty? ? [RbConfig.ruby] : [env.transform_keys(&:to_s).transform_values(&:to_s), RbConfig.ruby]
        out, status = Master::Io::Exec.capture2e(*cmd, script, *argv, chdir: working_directory(requested_root, script))
        return Result.ok(out.strip) if status.success?

        Result.err("#{tool}: #{failure_detail(status)}\n#{out.strip}", category: :infrastructure)
      rescue ArgumentError => e
        Result.err("#{tool}: bad arguments: #{e.message}", category: :validation)
      rescue StandardError => e
        Result.err("#{tool}: #{e.class}: #{e.message}", category: :infrastructure)
      end

      # Call a STUDIO tool's JSON API and return its result. This is the typed
      # boundary: MASTER passes an action and its arguments and reads a Hash
      # back, rather than composing flags and parsing human output.
      #
      #   ScriptDispatch.call(tool: "lora", action: "subjects")
      #   ScriptDispatch.call(tool: "postpro", action: "grade",
      #                       params: { "input" => src, "output" => dst, "preset" => "cinematic" })
      #
      # The request travels on stdin, so a large prompt needs no shell quoting.
      # A non-ok response, a missing entrypoint, a failed parse and a non-zero
      # exit are each an Err, so a caller checks ok? exactly as with run.
      def call(tool:, action:, params: {}, root: MasterPaths.repo, timeout: nil)
        name = tool.to_s
        script = api_script_path(File.expand_path(root.to_s.empty? ? Dir.pwd : root), name)
        return Result.err("#{tool}: missing API entrypoint", category: :validation) unless script && File.file?(script)

        request = JSON.generate(params.merge("action" => action.to_s))
        options = { chdir: working_directory(File.expand_path(root.to_s), script), stdin_data: request }
        options[:timeout] = timeout if timeout
        out, status = Master::Io::Exec.capture2e(RbConfig.ruby, script, "api", **options)
        parse_api_response(tool, out, status)
      rescue ArgumentError => e
        Result.err("#{tool}: bad arguments: #{e.message}", category: :validation)
      rescue StandardError => e
        Result.err("#{tool}: #{e.class}: #{e.message}", category: :infrastructure)
      end

      def api_script_path(requested_root, tool)
        relative = API_ENTRYPOINTS[tool]
        roots = [requested_root, MasterPaths.repo, MasterPaths.root].uniq
        candidates = roots.flat_map do |candidate|
          if relative
            [File.join(candidate, "STUDIO", relative)]
          else
            # An unlisted tool answers the API from its conventional entrypoint.
            [File.join(candidate, "STUDIO", tool, "#{tool}.rb"), File.join(candidate, "STUDIO", "#{tool}.rb")]
          end
        end
        candidates.find { |path| File.file?(path) }
      end

      # The tool prints exactly one JSON object; boot chatter, if any, rides
      # under "output" inside it. A line that does not parse means the boundary
      # broke, and that is an Err rather than a silent pass.
      def parse_api_response(tool, out, status)
        line = out.to_s.lines.map(&:strip).reject(&:empty?).last
        payload = line && JSON.parse(line)
        return Result.err("#{tool}: no JSON response (#{failure_detail(status)})", category: :infrastructure) unless payload.is_a?(Hash)
        return Result.ok(payload["result"]) if payload["ok"]

        Result.err("#{tool}: #{payload['error']}", category: :validation)
      rescue JSON::ParserError
        Result.err("#{tool}: unparseable API response: #{out.to_s.strip[0, 300]}", category: :infrastructure)
      end

      def failure_detail(status)
        if status.signaled?
          signal = status.termsig
          "terminated by signal #{Signal.list.key(signal) || signal}"
        elsif status.exited?
          "exit=#{status.exitstatus}"
        else
          "ended without a normal exit status (#{status})"
        end
      end

      # Resolve known Studio tools first; explicit aliases name tools whose
      # canonical entrypoint is nested below their provider tree. Other
      # registered tools retain the existing MASTER/tools and workspace tool
      # layouts. Every candidate is built from a fixed root and a single name.
      def script_path(requested_root, tool)
        name = tool.to_s
        return File.join(requested_root, "MASTER", "tools", "invalid.rb") unless name.match?(/\A[a-zA-Z0-9_-]+\z/)

        roots = [requested_root, MasterPaths.repo, MasterPaths.root].uniq
        entrypoint = TOOL_ENTRYPOINTS.fetch(name) { File.join(name, "#{name}.rb") }
        studio_candidates = roots.map { |candidate| File.join(candidate, "STUDIO", entrypoint) }
        studio = studio_candidates.find { |candidate| File.file?(candidate) }
        return studio if studio

        master_candidates = roots.flat_map do |candidate|
          [
            File.join(candidate, "MASTER", "tools", "#{name}.rb"),
            File.join(candidate, "tools", "#{name}.rb"),
            File.join(candidate, "tools", name, "#{name}.rb"),
            File.join(candidate, "MASTER", "tools", entrypoint),
          ]
        end
        master_candidates.find { |candidate| File.file?(candidate) } || studio_candidates.first
      end

      def working_directory(requested_root, script)
        [requested_root, MasterPaths.repo, MasterPaths.root].uniq.each do |candidate|
          studio_root = File.join(candidate, "STUDIO")
          next unless script.start_with?(studio_root + File::SEPARATOR)

          relative = script.delete_prefix(studio_root + File::SEPARATOR)
          return File.dirname(script) if relative.include?(File::SEPARATOR)
          return candidate
        end

        return requested_root if File.directory?(requested_root)

        MasterPaths.repo
      end
    end
  end
end
