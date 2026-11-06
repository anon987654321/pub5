# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/inter_model.rb:7 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 71ad8abafb752685
require_relative "master/law/inter_model"

Law.define(:INTER_MODEL_CONTRACT) do
  path "MASTER/lib/review/council/"
  source "MASTER/data/inter_model.yml - machine-validated peer-model exchanges"
  detect do |line|
    call = line.match(/@agent\.ask(?:_once)?\s*\((.*)\z/)
    call && (
      call[1].match?(/\A\s*prompt\b/) ||
      call[1].match?(/\A\s*<<[-~]?\s*[A-Z_]\w*/) ||
      call[1].match?(/\bprompt\s*:/)
    )
  end
  ask <<~'ASK'.strip
    Does every MASTER-to-model council turn use InterModelContract to construct a structured request envelope,
    attach a SHA-256 artifact reference, validate the returned JSON finding schema, and record a bounded metric
    without persisting raw model text? Invalid output must receive one structured rejection and one retry only.
  ASK
  practice <<~'PRACTICE'.strip
    Treat other models as protocol peers: explicit authority, evidence, bounded artifacts, structured disagreement,
    and no reciprocal persona.
  PRACTICE
  fix <<~'FIX'.strip
    Wrap every council model request with InterModelContract and validate its returned structured findings
    before aggregation.
  FIX
  bad "@agent.ask(prompt)"
  good "@agent.ask(outbound)"
end
