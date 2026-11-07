#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "photograph/idea_picture"
require_relative "photograph/selfie_series"

if $PROGRAM_NAME == __FILE__
  options = { film: false, duration: 5, subject: ENV.fetch("STUDIO_PHOTOGRAPH_SUBJECT", "ragnhild") }
  OptionParser.new do |parser|
    parser.on("--film", "also render the short film") { options[:film] = true }
    parser.on("--duration N", Integer, "film duration in seconds") { |value| options[:duration] = value }
    parser.on("--subject NAME", "subject directory under STUDIO/replicate/lora") { |value| options[:subject] = value }
    parser.on("--selfie-series", "render a bounded selfie series for --subject") { options[:series] = true }
    parser.on("--count N", Integer, "series length, 1..24") { |value| options[:count] = value }
  end.parse!

  result =
    if options[:series]
      Studio::Visual::SelfieSeries.new(subject: options[:subject]).run(count: options[:count] || 12)
    else
      prompt = ARGV.join(" ").strip
      abort "usage: ruby STUDIO/photograph.rb [--selfie-series] [--film] PROMPT" if prompt.empty?

      Studio::Visual::IdeaPicture.new(subject: options[:subject]).write(prompt, film: options[:film], duration: options[:duration])
    end
  puts JSON.generate(result)
end
