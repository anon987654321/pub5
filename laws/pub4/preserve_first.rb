# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:56 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9b6d9cb103541c32
require_relative "master/law/practice"

Law.define(:PRESERVE_FIRST) do
  source "MASTER constitution (soul.yml absolute.rules)"
  ask "Does this code edit proceed before the complete target source and relevant dependencies, callers, loaders, configuration, tests and public contracts have been read and understood?"
  practice <<~TEXT
    never rewrite working code from a snippet. read the complete current target
    and its dependency/caller/test/configuration contract before writing, using
    content hashes and a fresh reference map as evidence. A cached excerpt,
    assumed caller list or graph that failed to read a source is not complete
    understanding. If relevant context is missing or exceeds the safe context
    budget, block only the affected repair rather than guessing; continue every
    independent in-scope task. Preserve user intent, data, security, privacy and
    public contracts, not a defective implementation. Improve or retire that
    implementation when evidence justifies the change, and prove the result.
  TEXT
  fix "Read the entire target and its relevant dependencies before editing; preserve behavior and prove the change."
  bad  "edits a forty-line excerpt without reading the complete source or its callers"
  good "reads the whole source, traces dependency and caller files, then changes only the justified lines"
end
