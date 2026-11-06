# frozen_string_literal: true

# Stands where pub4's MASTER/lib/ground/swallow.rb stood. pub4's wrote each
# swallowed error to .master/swallowed_errors.jsonl; imported Laws must not
# write outside World, so Master::Ground::Swallow (lib/master.rb) keeps the
# rows in memory for the census instead. Hand-written; the port never
# replaces it.
require_relative "../master"
