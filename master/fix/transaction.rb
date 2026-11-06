# frozen_string_literal: true

require "json"

module Fix
  # One repair, all or nothing (PLAN.md section 6.4): the touched bytes are
  # snapshotted, the candidate is written through World#write, and any
  # refusal after that (tests, the commit hook, the visual gate) puts back
  # the exact bytes and appends a line to log/fix_refusals.jsonl.
  #
  # A refusal never leaves the model's edit in the file (pub4 c49347f2d6):
  # the file goes back when it still holds exactly the repair's bytes and
  # HEAD does not already carry them (a commit that landed is delivered work).
  # A file another writer changed since is theirs, and stays.
  class Transaction
    attr_reader :path, :before, :after

    def initialize(world:, path:, refusals:)
      @world = world
      @path = path
      @refusals = refusals
      @before = world.read(path)
      @after = nil
    end

    def apply(text)
      @after = text.b
      @world.write(@path, text)
      self
    end

    # :restored, :left (someone changed it since) or :delivered (HEAD holds it).
    def refuse(stage, reason, **details)
      outcome = put_back
      @refusals.append(:refusal, file: @path, stage: stage.to_s, reason: reason.to_s[0, 600], outcome: outcome.to_s,
                                 **details)
      outcome
    end

    def put_back
      return :untouched unless @after
      return :left unless @world.read(@path).b == @after
      return :delivered if committed?

      @world.write(@path, @before)
      @world.git("reset", "-q", "--", @path)
      :restored
    end

    def committed?
      shown = @world.git("show", "HEAD:#{@path}")
      shown.ok? && shown.out.b == @after
    end
  end

  # Mechanical writes made while observing (whitespace transforms), kept with
  # their bytes so they deliver with the pass like the pass's own repairs
  # (pub4 a024dc8440: they were neither committed nor put back). A file that
  # no longer holds exactly the written bytes is someone else's and is left,
  # named.
  class Writes
    Row = Data.define(:path, :before, :after, :laws)

    def initialize = @rows = {}

    def note(path, before:, after:, laws:) = @rows[path] = Row.new(path:, before: before.b, after: after.b, laws:)

    def rows = @rows.values

    def any? = @rows.any?

    # [ours, left]: the paths that still hold this run's bytes, and the rest.
    def split(world) = rows.partition { |row| world.read(row.path).b == row.after }
  end
end
