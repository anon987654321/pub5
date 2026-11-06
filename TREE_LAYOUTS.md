# Tree layouts, considered and chosen (2026-11-06)

Proposals for the five trees' layouts inside pub5, then the cherry-pick.
Grounded in pub4 at commit e42dc7006c (MASTER: lib 881 files / checks 521 /
tools 157 / data 95 / law 32 / plugins 73 / web 314 / test 871; RAILS:
__shared + brgen + five brgen_* engine dirs + amber + bsdports + master +
master_web + mrdamascy + __other + shell deploy scripts + apps.yml; OPENBSD:
host-path mirror etc/ usr/ var/ + bin 45 + checks 14 + lib 22 + data 4 +
test 50; STUDIO: dilla 35 + postpro 234 + replicate 606 + photograph +
top-level helper *.rb; BPLANS: an archive, deliberately not a tree - PLAN.md
§3 keeps its content as text). The port target stays 2,700-3,300 files from
about 6,000; every layout below is judged by PLAN.md's rule - same
behaviour, less code - and by one question: does a file's home say what it
governs?

## MASTER - four considered

- **M1. Kernel + plugins** `master/{bin,core,plugins,law,checks,tools,data,test}`
  - The PLAN shape literally: `core/` under 5k lines with capability
    refusals proven per verb; fix, review, cli and io (today ~92k lines in
    lib/) arrive as `plugins/`. Pro: the 5k line budget has a wall it lives
    behind; the plugin boundary is the only place growth can happen.
    Con: the boundary needs a Law or it rots - pub4's plugins/ already
    exists (73 files) and lib/ still grew around it.
- **M2. One gem** `master/` Gemfile + gemspec + `lib/master/**` like pub4's
  shape, core flattened inside lib/
  - Pro: mechanically familiar, `bin/master` unchanged. Con: it is pub4's
    layout again - the 881-file lib/ came from this shape, and a flattened
    core loses the 5k wall.
- **M3. Command-first** `master/bin/{master,operator}` + `master/cmd/**/*.rb`
  - Pro: matches the CLI contract row (command, exit code, output shape)
    and makes every verb's home obvious. Con: a cmd/ tree is a second
    sprawl risk; verbs that share code need lib/ anyway, so cmd/ becomes
    thin wrappers over unreviewed lib/.
- **M4. Registry-led** `master/{registry,core,law,checks,tools,data}`
  - Pro: the cross-cutting registries (PLAN: apps, laws, models, knobs,
    tokens, commands, paths, writers, backlog) live where both MASTER and
    the other trees read them. Con: registry/ is not MASTER's alone, so
    nesting it under master/ misnames its ownership.

**Chosen - M1 with M4's correction**, plus the web face as a plugin:

```
master/
  bin/master  bin/operator
  core/       <5k lines, capability refusals per verb (M1)
  plugins/    fix, review, io, web (the redesigned MASTER web face), studio-glue
  law/        the one Law engine; laws.yml reads from registry/
  checks/     the contract instruments (route contracts, golden screenshots,
              law fixtures, cli contracts, round-trips)
  tools/      maintainer tools (record/check, ratchets, law_fixtures)
  data/       soul.yml byte for byte; knobs, models, scan profiles
  test/
```

`registry/` sits at pub5's top level, not under master/ (M4's point, M1's
home for code). The web face is a plugin, not `web/` - it is content, not
kernel, and dropping it to a plugin is the plan's "redesign: MASTER web
face" made structural.

## RAILS - four considered

- **R1. TODO row verbatim** `rails/{shared,bsdports,mrdamascy,amber,brgen}`
  with each brgen engine under `brgen/engines/`
  - Pro: exactly what pub4 TODO.md's Phase 3 row already states; engines
    move with the app that owns them instead of five sibling `brgen_*`
    dirs. Con: none structural - the cost is the rename itself, and the
    rename is where fallout hides (tests and unread config name paths).
- **R2. Apps + engines split** `rails/apps/*` + `rails/engines/*`
  - Pro: a rails/ top level with two meanings, not six. Con: engines are
    not shared - each is one vertical of one app - so the second dir
    misstates ownership and the TODO row would need rewriting.
- **R3. Mechanical rename only** keep pub4's flat six-ish siblings,
  `__shared` becomes `shared`, nothing else moves
  - Pro: cheapest, lowest fallout risk. Con: keeps the shape that
    produced the sprawl; the TODO row's promise ("each brgen engine under
    brgen/engines/") is dropped, and the port contract says the shape is
    part of the decision.
- **R4. Workspace layout** R1 plus moving the cross-tree facts out:
  `apps.yml` domain facts and ports become `registry/apps.yml` reads
  - Pro: one registry instead of RAILS/apps.yml + OPENBSD/data/domain_inventory.yml
    + relayd.conf's host list agreeing by convention (three sources that
    have already disagreed once - the oshlo.no keypair).
    Con: registry coupling must wait for Phase 5, or rails reads a file
    MASTER last owns; in practice apps.yml keeps publishing domain facts
    until the registry reads land.

**Chosen - R1 (= the TODO row) + R4's registry direction, sequenced**:
port as R1 with `rails/apps.yml` carried unchanged; the registry reads
become a Phase 5 change when MASTER lands and can own them. Build order
(decided 2026-11-06): **brgen and its verticals first, then amber, then
bsdports, then mrdamascy** - brgen is the main app, so the shared engine,
the brgen core and its five engines are the port's first RAILS proof, and
the smaller apps follow through the same gate. `__other` (static brand
exports) is retired upstream and does not come over. The screenshot_*.png
corpus and visual_completion.yml do not come over - the golden screenshots
are the machine-checked successor. The `_*.sh` deploy scripts fold into
OPENBSD's one deploy tool (Phase 2); they are deploy behaviour, not app
behaviour.

## OPENBSD - three considered

- **O1. Host-path mirror kept** everything as pub4: `etc/`, `usr/local/bin/`,
  `var/nsd/` mirror vm23's paths, configs edited in place
  - Pro: `cp` deploys stay possible; paths match the box. Con: this is the
    tree PLAN §3 redesigns ("OPENBSD inventory, generated from one
    registry") - the relayd.conf keypair list and pf's rate rules are typed
    facts that already diverged from the live box once (relayd's oshlo
    line was live for months before the repo carried it).
- **O2. Registry-generated** `openbsd/{lib/,etc/ (generated),proven/,check/}`
  + top-level `registry/` apps facts + one Ruby deploy tool
  - Pro: the plan's Phase 2 row verbatim: one registry generates relayd,
    rc.d and pf; the proven configs kept verbatim as byte-equality fixtures
    (§3's "keep verbatim") make every generator change a reviewable diff.
    Con: the generated shape must reproduce comments that carry proven
    wisdom, so "generated" means registry rows own the comment prose too.
- **O3. Deploy/host split** `openbsd/{deploy,host,checks}`
  - Pro: separates Mac-side tooling from box-side files. Con: three dirs
    for a 100-150 file tree is ceremony; the host files are the generated
    output and need no second home.

**Chosen - O2**, sequenced in rows:

```
openbsd/
  lib/            renderer + deploy library (pure Ruby)
  etc/            generated output: relayd.conf, pf.conf, rc.d/*
  proven/         pub4's configs verbatim, byte-equality fixtures (§3)
  check/          diff-check of generated vs proven; drift names, never skips
  registry reads  apps.yml (from top-level registry/): ports, hosts, keypairs
```

Row order within Phase 2: relayd + pf first (pure data), rc.d second (the
per-app scripts' proven comment blocks move into the renderer's templates),
then the one deploy tool that ships a Mac-built artifact, then the §7.2
rehearsal. NSD zones already have one generator (dns.yml) and come over
with it.

## STUDIO - three considered

- **S1. One CLI + engine dirs** `studio/{bin/studio,dilla,postpro,replicate}`
  - Pro: the TODO Phase 4 row asks for exactly this ("dilla and postpro
    behind one CLI"); dilla.rb + data/*.json move byte for byte (§3 keep
    verbatim) inside unchanged dirs. Con: bin/studio vs a master plugin is
    a real question - STUDIO is operator tooling, so it stays its own tree
    with its own entrypoint; MASTER calls it through the registry's
    commands list, not by reaching in.
- **S2. Pub4 shape + one entrypoint** keep dilla/, postpro/ exactly, add
  bin/studio stub delegating to the existing top-level helpers
  - Pro: zero movement. Con: the top-level *.rb helpers (subprocess.rb,
    output_paths.rb, test_runner.rb) stay unowned; replicate/ (606 files)
    keeps no boundary against postpro/.
- **S3. Command dirs** `studio/{cmd/dilla,cmd/postpro,cmd/replicate}` +
  shared lib/
  - Pro: matches M3's instinct. Con: same objection as M3 - the engines
    are the code, cmd/ would be wrappers; and dilla's contract test
    (output byte-for-byte on fixtures) pins dilla.rb where it is.

**Chosen - S1 with S2's non-negotiable inside it**: dilla/ keeps dilla.rb,
data/ and its contract test byte for byte; postpro/ and replicate/ are the
port's biggest drop candidates (refinements, stale generators) and get
sized before they move; photograph/ folds under postpro/. The one CLI is
`studio/bin/studio`, listed in registry/commands.yml so MASTER may invoke
it without knowing its tree.

## BPLANS - four considered (none is a tree)

- **B1. Text only, where the decisions live** content stays in PLAN.md §3
  and pub4's archive; no pub5 tree
  - Pro: the standing decision ("do not add BPLANS as a tree") taken
    exactly; zero maintenance. Con: the content is not searchable as
    backlog data until Phase 5.
- **B2. Plain-text dir** `bplans/*.md` split per plan document
  - Pro: readable. Con: creates the tree the decision refuses, and a tree
    of prose is TODO.md's mistake repeated at smaller scale.
- **B3. Single markdown reference** `docs/bplans.md`
  - Pro: one path, still text. Con: same objection as B2 with extra
    ceremony; docs/ was on the Drop list (docs/history).
- **B4. Backlog data** quote the content into `registry/backlog.yml` rows in
  Phase 5, when TODO.md and TREE_CONTRACTS.md become machines' data
  - Pro: BPLANS items become checkable rows, matching the Drop list's
    treatment of TODO.md. Con: nothing yet - this is the destination.
- **Chosen - B1 now, B4 at Phase 5.** BPLANS content is preserved as text
  (PLAN.md §3 keeps it), no tree ever appears, and when registry/backlog.yml
  lands in Phase 5 its rows are generated from the archived text. Should
  any future work need a BPLANS document, it is copied as text into the
  commit, never as a standing directory.

## The composite pub5 tree (what was chosen, together)

```
pub5/
  AGENTS.md  README.md  PLAN.md  TREE_LAYOUTS.md
  registry/            apps.yml, laws.yml, knobs.yml, models.yml, tokens.yml,
                       commands.yml, paths.yml, writers.yml, backlog.yml
  openbsd/             lib/  etc/ (generated)  proven/  check/  bin/deploy
  rails/               shared/  brgen/  brgen/engines/{dating,maps,marketplace,messenger,radio}
                       amber/  bsdports/  mrdamascy/  (build order: brgen first,
                       then amber, bsdports, mrdamascy; apps.yml carried until
                       its reads move to registry/ in Phase 5)
  studio/              bin/studio  dilla/ (byte for byte)  postpro/  replicate/
  master/              bin/{master,operator}  core/  plugins/  law/  checks/
                       tools/  data/  test/
  test/                cross-tree suites (the one test command recurses)
```

Two sequencing notes the composite obeys: `registry/` entries land beside
the phase that can own them (apps.yml's facts at Phase 2, laws.yml byte
for byte at Phase 5, backlog.yml at Phase 5); and `master/` is written
last - until then, AGENTS.md governs and its rules already say so.
