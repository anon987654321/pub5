# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require_relative "../../laws/engine"
require_relative "../../master/fix/run"

# What the /fix tests share: a git sandbox, a World over it with /fix's own
# verbs, a Law built without the registry, a run stub and a scripted model.
module FixHelper
  include TestHelper

  FIX_VERBS = Core::Registry.load(:commands).fetch("commands").fetch("fix").fetch("verbs")

  def repo
    sandbox do |root|
      git(root, "init", "-q", "-b", "main")
      git(root, "config", "user.email", "fix@test")
      git(root, "config", "user.name", "fix test")
      put(root, ".gitignore", "tmp/\nlog/\n")
      yield root
    end
  end

  SETUP_GIT = %w[init config add commit log status show rev-parse].freeze

  # Fixture setup goes through World#git like everything else.
  def git(root, *args)
    run = world(root, { git: SETUP_GIT }, protected_paths: []).git(*args)
    raise "git #{args.join(' ')}: #{run.err}" unless run.ok?

    run.out
  end

  def commit_all(root, message = "Seed the fixture")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", message)
  end

  def fix_world(root, protected_paths: ["registry/**"], **options)
    world(root, FIX_VERBS, protected_paths:, name: "fix", **options)
  end

  # A Law the tests own: it flags every line holding `violation`.
  def violation_law(id = :TEST_VIOLATION, autofix: "review")
    builder = Law::Builder.new(id)
    builder.instance_eval do
      detect { |line| line.include?("violation") }
      bad "violation\n"
      good "fine\n"
    end
    builder.build("statement" => "No line says violation.", "autofix" => autofix, "kind" => "lexical",
                  "lifecycle" => "advisory", "severity" => "warning").prove!
  end

  def finding(law, line, file: "a.rb") = Law::Finding.new(law.to_sym, file, line, "", nil)

  # What Repair and ModelGate read of a run.
  class RunStub
    attr_accessor :stopping, :seconds_left
    attr_reader :said, :pulses, :tracked

    def initialize(stopping: nil, seconds_left: 3_600, tracked: [])
      @stopping = stopping
      @seconds_left = seconds_left
      @tracked = tracked
      @said = []
      @pulses = []
    end

    def say(line) = @said << line
    def stop!(reason) = @stopping ||= reason
    def pulse(note = nil) = @pulses << note
    def load_average = nil
  end

  # Answers each ask with the next scripted reply (a String or a lambda of the prompt).
  class ScriptedModel
    attr_reader :prompts, :lane

    def initialize(*replies, lane: "scripted")
      @replies = replies
      @prompts = []
      @lane = lane
      @mutex = Mutex.new
    end

    def ask(prompt, system: nil, task: nil)
      reply = @mutex.synchronize do
        @prompts << prompt
        @replies.size > 1 ? @replies.shift : @replies.first
      end
      text = reply.respond_to?(:call) ? reply.call(prompt) : reply
      Models::Dispatch::Reply.new(text:, model: @lane, tokens_in: prompt.size / 4, tokens_out: text.to_s.size / 4,
                                  cost_usd: nil, seconds: 0.0)
    end
  end

  def fenced(text) = "```ruby\n#{text}```"
end
