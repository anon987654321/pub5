# pub5 agents

This file is the one shared contract for Gemini, GLM, Cursor, Copilot and
Claude working in pub5. It is generated-forward: when MASTER is ported
(Phase 5), `data/soul.yml` and `data/laws.yml` arrive byte for byte and
become the highest sources, per pub4's order. Until then these rules govern.

PLAN.md governs the shape. Its decisions are taken (big-bang cutover,
Roda + Sequel face, inbox branches for lower-trust writers, milestones
M0-M6); the numbered rules govern the port process inside that shape.
Where these rules and PLAN.md disagree, PLAN.md wins and the diff says why.

1. **Lock, then port, never rewrite.** Every behaviour is an executable contract
   recorded in pub4 first (pub4 `MASTER/checks/data/route_contracts/` and
   `MASTER/test/`). If the contract does not have it, porting it is a new
   feature and new features wait.
2. **Same behaviour, less code.** Each ported file is measured against the
   contract it satisfies; a file that satisfies no contract does not belong.
3. **One Ruby version: 3.4.9**, reconciled with vm23, the deploy host
   (OpenBSD 7.8, `brgen.no`). The interpreter exists locally (rbenv 3.4.9)
   and on the host byte for byte; nothing here may require a newer one.
4. **No sed, no coreutils text work.** All file and text operations go
   through pure Ruby, as pub4's Laws demand.
5. **No generated output in git.** `log/`, `tmp/`, `coverage/`, snapshots
   and anything a run produces stay outside the index (`bin/test` and
   `bin/lint` write only there).
6. **The commit hook owns the format.** `.githooks/commit-msg` is live from
   the first commit; set `core.hooksPath .githooks` after cloning
   (`git config core.hooksPath .githooks`). Subject: imperative, plain
   ASCII, at least two words, no trailing punctuation, one line. When
   `registry/writers.yml` lands (PLAN.md §9), the hook also requires a
   `Writer:` trailer that matches it.
7. **BPLANS does not come over.** pub4's BPLANS archive is deliberately not
   a pub4 tree here; PLAN.md §3 keeps its content as text.
8. **pub4 is the archive, never the workspace.** No pub5 commit ever names
   pub4 as its working tree; the first commit of every work stream names the
   pub4 commit it ported from.