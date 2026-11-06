# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:912 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5a4797768c716806
require_relative "master/law/universal"

Law.define(:LEAST_PRIVILEGE) do
  source "Saltzer & Schroeder - least privilege; OpenBSD pledge(2) and unveil(2)"
  ask "Does a process, service, job, deploy phase or agent retain ambient filesystem, network, syscall, credential or tool authority beyond the exact operation that needs it?"
  practice "Grant the minimum capability for the minimum duration. OpenBSD's pledge/unveil model is the reference: narrow the syscall and filesystem surface at the boundary, then only remove authority as execution advances."
  fix "Name the exact files, syscalls, network destinations, identities and actions required; deny everything else; enter the narrowest viable pledge/unveil stage after setup; never widen a sealed stage; and discard temporary credentials and handles when their phase ends."
  bad <<~'X'
    client = AdminClient.new; client.delete_all
  X
  good <<~'X'
    client = UserReadClient.new
  X
end
