# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name    = "master"
  # Release version is canonical at the pub5 root; soul.yml remains the
  # constitutional revision and is intentionally independent.
  spec.version = File.read(File.join(__dir__, "..", "VERSION"), encoding: "UTF-8").strip
  spec.authors = ["dev"]
  spec.summary = "Constitutional AI agent"

  # The gem:build_proof task builds this gemspec and checks the package
  # manifest. Keep the file list scoped to paths this tree actually owns;
  # Dir[] silently omits paths that are missing.
  spec.files         = Dir["lib/**/*.rb", "bin/*", "data/**/*", "plugins/**/*"]
  spec.require_paths = ["lib"]
  spec.bindir        = "bin"
  spec.executables = ["master"]

  spec.required_ruby_version = ">= 3.3"

  spec.add_dependency "zeitwerk",   "~> 2.7"
  spec.add_dependency "ruby_llm", "~> 2.1.0"
  spec.add_dependency "mcp", "~> 1.6"
  spec.add_dependency "event_stream_parser", ">= 1.0"
  spec.add_dependency "faraday", ">= 2.0"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "pastel",     "~> 0.8"
  spec.add_dependency "diffy",      "~> 3.4"
  spec.add_dependency "ferrum",     "~> 0.15"
end
