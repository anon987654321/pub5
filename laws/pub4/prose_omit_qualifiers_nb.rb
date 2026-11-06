# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/prose.rb:100 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f1a8d03f26450d3f
require_relative "master/law/prose"

Law::Prose::CONFIG.slice("nb").each do |code, language|
  reads = language["reads"]
  written_in = Law::Prose::SCOPES[code]
  keep = Law::Prose.any(language["keep"])
  leeches = Law::Prose.words(language["leeches"])
  qualifiers = language["fixtures"]["qualifiers"]
  Law.define(language["ids"]["qualifiers"].to_sym) do
    source "Strunk, Elements of Style (1918) - the leech words"
    path written_in if written_in
    reads_comments true
    detect do |line|
      said = Law::Prose.said(line, reads)
      next false unless said
      next false if said.match?(keep)

      said.match?(leeches)
    end
    fix "Delete the qualifier; let the verb or noun carry the weight."
    bad qualifiers["bad"]
    good qualifiers["good"]
  end
  shape = language["passive"]
  hidden = /\b#{shape['auxiliary']}\s+#{shape['participle']}\s+#{shape['agent']}\s+\w/
  passive = language["fixtures"]["passive"]
end
