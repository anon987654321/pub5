# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:963 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6f0af357a701ea3d
require_relative "master/law/universal"

Law.define(:COMPLETE_MEDIATION) do
  source "Saltzer & Schroeder - complete mediation; OpenBSD privilege boundaries"
  ask "Does every privileged filesystem, network, process, service, data or deployment operation pass through the narrow authority check at the point of use?"
  practice "A prior authorization is not a capability. Revalidate at every trust boundary and do not let callers bypass the fixed privileged broker."
  fix "Mediate every access where identity, object, state or policy can change; bind authority to the exact resource and operation; and keep privileged helpers closed to arbitrary commands or caller-supplied paths."
  bad <<~'X'
    authorized = policy.allow?(user); 100.times { perform if authorized }
  X
  good <<~'X'
    100.times { perform if policy.allow?(user) }
  X
end
