# frozen_string_literal: true
require "yaml"
require "digest"

module OpenBSD
  class Rehearsal
    Result = Struct.new(:path, :status, :detail, keyword_init: true)

    def initialize(root:)
      @root = File.realpath(root)
    end

    def verify_sources
      manifest = YAML.safe_load_file(File.join(@root, "openbsd", "provenance.yml"), aliases: false)
      Array(manifest.fetch("preserved_sources")).map do |source|
        path = File.join(@root, source.fetch("path"))
        unless File.file?(path)
          next Result.new(path: source.fetch("path"), status: "FAIL", detail: "missing preserved source")
        end
        bytes = File.binread(path)
        actual = Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0#{bytes}")
        status = actual == source.fetch("source_blob") ? "PASS" : "FAIL"
        Result.new(path: source.fetch("path"), status: status, detail: "source blob identity #{status.downcase}")
      end
    end

    def live_status
      host = YAML.safe_load_file(File.join(@root, "registry", "hosts.yml"), aliases: false).fetch("hosts").fetch("vm23")
      ["BLOCKED", Array(host.fetch("required_observations"))]
    end
  end
end
