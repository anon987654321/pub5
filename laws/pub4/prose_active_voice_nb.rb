# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/prose.rb:127 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c359bcdb02e3a7f4
require_relative "master/law/prose"

Law::Prose::CONFIG.slice("nb").each do |code, language|
  reads = language["reads"]
  written_in = Law::Prose::SCOPES[code]
  keep = Law::Prose.any(language["keep"])
  leeches = Law::Prose.words(language["leeches"])
  qualifiers = language["fixtures"]["qualifiers"]
  shape = language["passive"]
  hidden = /\b#{shape['auxiliary']}\s+#{shape['participle']}\s+#{shape['agent']}\s+\w/
  passive = language["fixtures"]["passive"]
  Law.define(language["ids"]["passive"].to_sym) do
    source "Strunk, Elements of Style (1918) Rule 10 - use the active voice"
    path written_in if written_in
    reads_comments true
    detect do |line|
      said = Law::Prose.said(line, reads)
      next false unless said

      said.match?(hidden)
    end
    fix "Recast active: 'the bug was fixed by X' -> 'X fixed the bug'."
    bad passive["bad"]
    good passive["good"]
  end
end
