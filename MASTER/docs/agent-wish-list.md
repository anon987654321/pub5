# An agent's wish list for this tree

Written 2026-11-09 by the GLM agent that ran this checkout's container
`/fix` against the operator's 2026-11-08 transcript. The mandate was to
leave nothing behind as backlog: every wish below that a repository can
grant is already granted on the same push, with the test that holds it.
What remains is what a repository cannot grant itself, and each of those
rows names its next concrete act rather than a TODO.

## Answered, with receipts

| The friction, as I lived it | The wish | Where it now lives |
| --- | --- | --- |
| The container had no `ruby`, no `apt` rights and no `yaml.h`; the same hand-compiled libyaml + Ruby 3.3 recipe was walked twice, once per session, from tribal memory | One command that turns any rootless host into a working dev host, and a contract line so the next agent never hand-compiles again | `bin/dev-bootstrap` (POSIX sh, idempotent, resumable, honours `PUB5_RUBY`, refuses to need root — test/test_bin_scripts.rb); the "Working alone in this repo" section of AGENTS.md now says `dev-bootstrap`, not "compile one" |
| The transcript's `voice0: audio playback failed - /usr/bin/afplay` reached the terminal while `tts-socket` kept answering "local speech/playback ready"; the operator heard nothing and no instrument could say which mouth, if any, spoke | A doctor check that speaks one real utterance and records `player=`, `engine=`, the outcome, and the first failure line of a degraded chain — and says skip, with the reason, where no ear can exist | `check_voice_utterance` in `bin/doctor` (tri-state, INCONCLUSIVE by construction), `Speech.last_engine` as the receipt's engine evidence (test/test_doctor.rb, test/voice/test_speech.rb); the open row in docs/session-2026-11-08.md is closed with the container's own skip line recorded |
| The layers duration test anchored on a requested 4.0 s while mp3 lands on frame boundaries; the container's ffmpeg build padded differently and the test read as a failure that wasn't the chain's doing | Expectations anchored on what the encoder actually wrote, not on the number the request asked for | the assertion now measures the source duration first and charges the chain only its declared breath and pause (test/voice/test_speech.rb) |
| A fresh sandbox flipped the executable bit on six thousand files; a naive `git add -A` would have committed pure umask noise, and nothing in the tree warned about it | The quirk named where agents actually read, with the one-line cure | AGENTS.md, "Working alone in this repo": mode-only diffs are the sandbox's umask; `git config core.fileMode false` silences them |
| The transcript's refusal read `audio playback failed - /usr/bin/afplay` and could not tell whether anything else had been tried; `play` already recorded every rung it walked, but the test-utterance refusal printed only the last one | A failed chain's refusal names the whole ladder it walked | `Playback.speak_now` now reads the recorded ladder into its refusal (test/voice/test_voice_support.rb) |
| A production-DNA brief interpolated Ruby Ranges as `53..56% swing`; prose that reads like a debugger dump | Ranges read the way a person says them | `ProductionDna.brief` renders `min-max` (test/voice/test_voice_support.rb) |
| The transcript's model denied capabilities the runtime had and couldn't say what surface it owned; a later transcript row left "open row 1/2" citations scattered in code comments after the rows closed | Comments that cite a doc row must not outlive the row's state | citations now read "the transcript's capability/identity row" (lib/review/agent/prompt_builder.rb, lib/voice/personality_prompt_builder.rb) |

## The pattern I wish every future check follows

`bin/doctor`'s `Check` struct is the single most transferable idea in this
tree for agent-and-human trust: a check has three answers, and the third
one — *unmeasured, and why* — is the difference between an instrument and
a lie. `voice-utterance` could have printed `ok` on a headless container
by testing nothing; instead it prints

    voice-utterance, skip
    sound through a speaker cannot be verified from a pipe or CI run;
    INCONCLUSIVE by construction

and the exit code agrees that a host without ears is not a sick host.
Anything added to this tree that measures the world should answer the
same three ways.

## What I still wish for — by design, not backlog

1. **The Mac half of the ear receipt.** The check exists; only a host
   with audio hardware can complete it. Next concrete act: run
   `bin/doctor` on the Mac and read the `voice-utterance` line. That is
   the check operating, not a task for this repository.
2. **A lane the agent actually serves, exercised as the operator
   experiences it.** The PTY conversation stage (lib/fix/conversation_probe.rb)
   already rides every lane and grades what a reply reads like; the
   honest next step is an operator-run pass on the lanes that carry real
   traffic, so the rubric grades the same model the operator hears.

## The one-sentence version

What made this tree hard for me was never the code — it was the missing
first hour: no Ruby, no ear, six thousand phantom mode diffs — and every
one of those is now a command, a check, or a contract line, so the next
agent starts where I ended.
