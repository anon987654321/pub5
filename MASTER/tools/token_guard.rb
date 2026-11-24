#!/usr/bin/env ruby
# frozen_string_literal: true

# Refuse a commit or push whose ADDED lines carry a real-looking credential.
#
# A GitHub PAT was pasted into a chat on 2026-11-23, and the handoff notes record
# the same thing happening before. The runtime redactor scrubs logs; nothing
# stopped a token from being committed. This reads only what a change adds, so
# an old fixture is never re-flagged, and it never prints the token it found.
#
#   token_guard.rb              scan the staged diff        (pre-commit)
#   token_guard.rb --range A..B scan the commits in a range (pre-push)
#
# Obvious placeholders (alphabet runs, repeated characters, EXAMPLE/FAKE) pass,
# which is what the scanner fixtures in this repo use. PUB5_ALLOW_TOKEN_SHAPE=1
# says "I looked, it is not a credential" for the one case this misjudges.

module TokenGuard
  Finding = Data.define(:path, :line, :kind)

  PATTERNS = {
    "GitHub token" => /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b/,
    "GitHub fine-grained token" => /\bgithub_pat_[A-Za-z0-9_]{30,}\b/,
    "Anthropic key" => /\bsk-ant-[A-Za-z0-9_-]{30,}/,
    "API key" => /\bsk-[A-Za-z0-9]{32,}\b/,
    "AWS access key" => /\bAKIA[0-9A-Z]{16}\b/,
    "private key block" => /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/,
  }.freeze

  PLACEHOLDER = /abcdefghijklm|0123456789|(.)\1{7,}|example|fake|dummy|redacted|your[_-]?(?:token|key)|<[^>]+>/i

  module_function

  def placeholder?(text) = text.match?(PLACEHOLDER)

  # diff is unified-diff text; only lines it adds are read.
  def scan(diff)
    path = nil
    line_no = 0
    findings = []
    diff.each_line do |raw|
      case raw
      when /\A\+\+\+ b\/(.*)/ then path = Regexp.last_match(1).strip
      when /\A@@ -\S+ \+(\d+)/ then line_no = Regexp.last_match(1).to_i - 1
      when /\A\+(?!\+\+)/
        line_no += 1
        text = raw[1..]
        PATTERNS.each do |kind, pattern|
          hit = text[pattern]
          findings << Finding.new(path: path.to_s, line: line_no, kind:) if hit && !placeholder?(hit)
        end
      when /\A[ ]/ then line_no += 1
      end
    end
    findings
  end

  def report(findings)
    findings.map { |f| "  #{f.path}:#{f.line}  #{f.kind}" }.join("\n")
  end
end

if $PROGRAM_NAME == __FILE__
  exit 0 if ENV["PUB5_ALLOW_TOKEN_SHAPE"] == "1"

  diff =
    if ARGV.first == "--range"
      IO.popen(["git", "log", "-p", "--format=", "-U0", ARGV.fetch(1)], err: File::NULL, &:read)
    else
      IO.popen(%w[git diff --cached -U0 --no-color], &:read)
    end
  findings = TokenGuard.scan(diff.to_s.dup.force_encoding(Encoding::UTF_8).scrub)
  exit 0 if findings.empty?

  warn ""
  warn "token-guard: REFUSED - #{findings.size} added line(s) look like a real credential:"
  warn TokenGuard.report(findings)
  warn ""
  warn "  Remove it and rotate it if it was ever pasted anywhere. Revoke on GitHub first;"
  warn "  history rewrites do not un-leak a token. If it is a placeholder this misjudged:"
  warn "  PUB5_ALLOW_TOKEN_SHAPE=1 git commit ..."
  warn ""
  exit 1
end
