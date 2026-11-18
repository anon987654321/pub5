#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/operator/polish_lens"

Operator::PolishLens.run(json: ARGV.include?("--json"), candidates: ARGV.include?("--candidates"))
