# frozen_string_literal: true
require "json"
require "yaml"
require "erb"
require "rexml/document"

module Pub5
  module Core
    class ParseGate
      Result = Struct.new(:path, :status, :detail, keyword_init: true)
      SUPPORTED = %w[.rb .yml .yaml .json .erb .svg].freeze

      def initialize(root:)
        @root = File.realpath(root)
      end

      def scan(paths = nil)
        candidates = paths || Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH)
        candidates.select { |path| File.file?(path) && !excluded?(path) }.sort.map { |path| check(path) }
      end

      def run(paths = nil, io: $stdout)
        results = scan(paths)
        counts = results.group_by(&:status).transform_values(&:length)
        results.each { |result| io.puts "#{result.status} #{result.path}: #{result.detail}" if result.status == "FAIL" }
        io.puts "parse0: #{counts.fetch("PASS", 0)} PASS, #{counts.fetch("FAIL", 0)} FAIL, #{counts.fetch("NOT_RUN", 0)} NOT_RUN"
        results.none? { |result| result.status == "FAIL" } ? 0 : 1
      end

      private

      def excluded?(path)
        relative = path.delete_prefix("#{@root}/")
        relative.start_with?(".git/", "vendor/", "tmp/", "node_modules/", "coverage/")
      end

      def check(path)
        ext = File.extname(path)
        unless SUPPORTED.include?(ext)
          detail = ext.empty? ? "no parser for extensionless file" : "no parser for #{ext}"
          return Result.new(path: relative(path), status: "NOT_RUN", detail: detail)
        end
        source = File.read(path)
        case ext
        when ".rb" then RubyVM::InstructionSequence.compile(source, path)
        when ".yml", ".yaml" then YAML.safe_load(source, permitted_classes: [], permitted_symbols: [], aliases: false)
        when ".json" then JSON.parse(source)
        when ".erb" then RubyVM::InstructionSequence.compile("def __pub5_erb_probe__\n#{ERB.new(source).src}\nend", path)
        when ".svg" then REXML::Document.new(source)
        end
        Result.new(path: relative(path), status: "PASS", detail: "parsed")
      rescue StandardError, SyntaxError => e
        Result.new(path: relative(path), status: "FAIL", detail: "#{e.class}: #{e.message.lines.first.to_s.strip}")
      end

      def relative(path)
        path.delete_prefix("#{@root}/")
      end
    end
  end
end
