# pub5 gatekeeper on vm23: install kit

`bin/master gate` (master/commands/gate.rb, master/gate/) is pub5's only
enforcement. There are no GitHub Actions (the account is billing-locked) and no
branch protection (it needs Pro, and every writer pushes from the one
anon987654321 account). Every five minutes it does the following:

- It fetches origin and judges each new first-parent commit on main by
  running that commit's own `bin/check` in a throwaway worktree under
  `tmp/gate/`.
- It records PASS or FAIL in the ledger (`log/ledger.jsonl`, kind `gate`),
  with the author, the writer from the `Writer:` trailer, the failing step
  and the duration.
- While main is red it writes `log/gate/FAILED`, plus `log/gate/<sha>.out`
  holding the full bin/check output.
- It records violations. A violation is a commit on main from an inbox-tier
  writer or from the author anon987654321, or a main that no longer descends
  from the last judged tip (a force-push).
- It merges an `inbox/<writer>` branch only when the branch merged onto main
  passes bin/check and every changed path is inside that writer's trees in
  registry/writers.yml. A branch that fails is left where it is, and the
  ledger records why.
- When `PUB5_GATE_AUTO_REVERT=1` (registry/knobs.yml, off by default) it
  reverts a commit that turned a green main red. The revert is a new commit
  that names the reverted one.

It never force-pushes and never rewrites history. `bin/master gate --status`
prints the last results.

Not yet enforced: the "a different model reviewed it" condition from
AGENTS.md. The gate merges on green and in-tree alone.

The gatekeeper's clone runs the gate code it was cloned at, on purpose. It
does not pull itself, so a bad push to main cannot break its own judge.
Update it by hand with `git -C ~/pub5gate pull --ff-only` after the gate
code itself changes.

## What the operator runs

These steps are written down here, not run: no key, clone or crontab entry
exists until the operator makes it. The box account is `dev`, and the clone
is `/home/dev/pub5gate`.

1. On the box, make a key that only this clone uses, with no passphrase so
   cron can use it. See ssh-keygen(1): `-t ed25519`, `-N ''` for an empty
   passphrase, `-C` for the comment, `-f` for the output file.

       ssh dev@brgen.no 'ssh-keygen -t ed25519 -N "" -C pub5-gate@vm23 -f ~/.ssh/pub5_gate_ed25519'

2. On a machine where `gh` is logged in to anon987654321, register the
   public half as a deploy key with write access. The gate pushes merges and
   reverts to main.

       ssh dev@brgen.no 'cat ~/.ssh/pub5_gate_ed25519.pub' > pub5_gate_ed25519.pub
       gh repo deploy-key add pub5_gate_ed25519.pub --repo anon987654321/pub5 --title "pub5 gate vm23" --allow-write

3. Clone over SSH with that key alone. Give the gate its own committer name,
   which appears on merge and revert commits. Then install the hooks.

       ssh dev@brgen.no 'git clone -c core.sshCommand="ssh -i ~/.ssh/pub5_gate_ed25519 -o IdentitiesOnly=yes" \
           git@github.com:anon987654321/pub5.git ~/pub5gate &&
         cd ~/pub5gate && git config user.name "pub5 gate" && git config user.email gate@brgen.no &&
         mkdir -p log && bin/setup && bin/master gate && bin/master gate --status'

   The first run judges only the current tip. The gate starts from now, not
   from the first commit.

4. Add the cron job with `crontab -e` as dev.
   - crontab(5): a user line has five time fields, then optional flags.
     `-s` runs a single instance at a time and `-n` mails only on a
     non-zero exit. A comment may not share a line with a command or a
     variable.
   - cron(8) runs the job without a login shell. Its default PATH lacks
     /usr/local/bin, where ruby, ruby34 and git live, so set PATH here.
     cron mails any output to MAILTO; the redirect keeps the output in the
     log instead.
   - timeout(1) (in base since OpenBSD 7.0): it sends TERM after 45 minutes,
     then KILL 60 seconds later. TERM lets the gate release its lock; after
     a KILL the lock clears itself after 4 hours.
   - nice(1): `-n 10` keeps the 1 GB box's Rails apps ahead of bin/check.

       PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
       MAILTO=dev
       */5 * * * * -ns cd /home/dev/pub5gate && nice -n 10 timeout -k 60 45m bin/master gate >> log/gate.log 2>&1

5. Rotate the cron log. As root, add this line to /etc/newsyslog.conf.
   OpenBSD has no newsyslog.conf(5); the format is in newsyslog(8). The
   fields are: owner:group, mode, 7 archives, a 256 KB size trigger, no time
   trigger (`*`), and gzip (`Z`). The final `""` sends no signal, because
   the gate is not a daemon.

       /home/dev/pub5gate/log/gate.log	dev:dev	640	7	256	*	Z	""

   Do not add log/ledger.jsonl here. It is the append-only record of which
   SHAs were judged, so rotating it away would make the gate judge them
   again.

## Operating it

- `bin/master gate --status` prints the last five verdicts, whether main is
  red, the last decision for each inbox branch, and the last violations.
- `cat ~/pub5gate/log/gate/FAILED` exists only while main is red, and names
  the commit that turned it red.
- `PUB5_GATE_AUTO_REVERT=1` before `bin/master gate` in the crontab line
  turns on auto-revert.
- If a run was killed with KILL and you do not want to wait four hours for
  the lock to clear, remove it with
  `git -C ~/pub5gate update-ref -d refs/gate/lock`.
- To uninstall: remove the crontab line, the newsyslog line, the clone and
  the deploy key (`gh repo deploy-key list` and `gh repo deploy-key delete`
  in the anon987654321 session).
