# frozen_string_literal: true
require "open3"
require_relative "errors"
require_relative "safe_path"

module Pub5
  module Core
    class World
      def initialize(root:, capabilities:, writer:, http:, adapters: {})
        @root = File.realpath(root)
        @paths = SafePath.new(@root)
        @capabilities = capabilities
        @writer = writer
        @http = http
        @adapters = adapters
      end

      def read(path)
        @capabilities.allow!("read", path: path)
        File.binread(@paths.resolve(path))
      end

      def write(path, bytes)
        @writer.write(path, bytes)
      end

      def exec(command, *args)
        @capabilities.allow!("exec")
        raise Denied, "command not granted: #{command}" unless @capabilities.commands_for("exec").include?(command.to_s)
        Open3.capture3(command.to_s, *args.map(&:to_s), chdir: @root)
      end

      def net(url, headers: {})
        @capabilities.allow!("net")
        @http.get(url, headers: headers)
      end

      def llm(request)
        invoke_adapter!(:llm, request)
      end

      def git(request)
        invoke_adapter!(:git, request)
      end

      def render(request)
        invoke_adapter!(:render, request)
      end

      private

      def invoke_adapter!(key, request)
        @capabilities.allow!(key)
        adapter = @adapters.fetch(key) { raise Unsupported, "#{key} adapter is not configured" }
        adapter.call(request)
      end
    end
  end
end
