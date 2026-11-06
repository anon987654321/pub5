# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/project_context.yml operator_master_resembles_openbsd by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: cd792e61c72c09c2
require_relative "master/lib/master"

Law.define(:OPERATOR_MASTER_RESEMBLES_OPENBSD) do
  source "pub4 MASTER/data/project_context.yml operator_master_resembles_openbsd"
  practice "Correctness by default through restriction, continuous auditing, small\ntrusted cores, least privilege, one canonical implementation per operation,\nand never reporting an unmeasured result as a pass (INCONCLUSIVE or\nBLOCKED instead). Prefer fewer, stricter Laws with real fixtures over more\nguidance; delete contradictory or dead machinery; terse dmesg-style output.\nThe operator's earlier decisions stand where they differ: renders stay\nreplaceable, work lands straight on main."
end
