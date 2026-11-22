#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/operator/polish_lens"
require_relative "../lib/operator/polish_apply"

def opt(name)
  i = ARGV.index(name)
  i ? ARGV[i + 1].to_s.split(",") : nil
end

if ARGV.include?("--reject")
  Operator::PolishLens.apply(only: opt("--only"), reject: opt("--reject"))
elsif ARGV.include?("--apply")
  Operator::PolishLens.apply(only: opt("--only"), dry_run: ARGV.include?("--dry-run"))
else
  Operator::PolishLens.run(json: ARGV.include?("--json"), candidates: ARGV.include?("--candidates"))
end
