# MASTER skeleton (Ruby)

A working agent skeleton: agent loop + tool registry + pluggable LLM adapter +
conversation memory + semantic (vector) memory + scheduler + sub-agents +
eleven tools. Document generation is intentionally excluded.

## Layout

```
bin/master                   CLI REPL (--db, --no-schedule, --remember)
lib/master.rb                requires
lib/master/agent.rb          the loop: plan -> act -> observe -> answer
lib/master/llm_adapter.rb    OpenAI-compatible client (hosted or local)
lib/master/tool_registry.rb  tool interface + registry + dispatch
lib/master/memory.rb         SQLite conversation memory
lib/master/vector_memory.rb  semantic memory (embeddings + cosine search)
lib/master/schedule_store.rb persisted schedule definitions
lib/master/scheduler.rb      Rufus::Scheduler runtime (cron/every/at)
lib/master/subagents.rb      thread-pooled sub-agents with scoped tools
lib/master/evals.rb          eval framework: Case, Context, Runner, fakes
evals/cases.rb               the canned eval cases
lib/master/tools/
  web_fetch.rb               plain HTTP fetch, HTML stripped
  web_search.rb              Brave Search API
  browser.rb                 headless Chromium via ferrum (optional dep)
  shell.rb                   trusted-use shell execution
  data.rb                    data_inspect via polars (optional dep)
  memory_tools.rb            remember / recall
  schedule_tools.rb          schedule_create / schedule_list / schedule_delete
  dispatch.rb                fan out subtasks to sub-agents
```

```
bin/master-evals             offline eval runner (--live, --json PATH)
test/smoke_test.rb           offline smoke test (needs only the sqlite3 gem)
```

## Run

```sh
bundle install
# local model via Ollama (default):
ollama serve
ollama pull qwen2.5:7b
ollama pull nomic-embed-text      # for remember / recall
bin/master

# or point at any hosted endpoint:
bin/master --base-url https://api.openai.com/v1 \
           --api-key $OPENAI_API_KEY \
           --model gpt-4o-mini
```

Environment:
- `MASTER_LLM_BASE_URL`, `MASTER_LLM_API_KEY`, `MASTER_MODEL` — LLM endpoint
- `MASTER_BRAVE_API_KEY` — enables `web_search` (Brave Search API)
- `MASTER_OLLAMA_URL` — embedder endpoint for semantic memory (default localhost:11434)

Flags: `--db PATH` (one SQLite file holds memory, vectors, schedules),
`--no-schedule`, `--remember` (store each Q&A turn in semantic memory).

Offline test: `ruby test/smoke_test.rb`
(needs only the `sqlite3` gem — covers registry, agent loop, schedule store,
sub-agent scoping, vector memory, and all schedule/memory tools).

## Design decisions

1. **Native function calling, not text parsing.** Tool calls come back
   structured from the model; the loop only handles the JSON plumbing.
2. **Tool failures are data, not exceptions.** `ToolRegistry#dispatch`
   returns `{ error: ... }` so the model can react (retry, choose another
   tool, explain) instead of crashing the run.
3. **One adapter, any backend.** Anything speaking the OpenAI-compatible
   chat protocol works: OpenAI, Ollama, LM Studio, vLLM, Groq.
4. **Memory persists user/assistant turns only.** Tool-call rounds stay
   within a single run; add them to `Memory` if you want full replays.
5. **Sub-agents cannot recurse.** `dispatch_subtasks` is excluded from every
   sub-agent's scoped registry by name.
6. **One SQLite file, three stores.** WAL mode + busy_timeout so the REPL,
   scheduler threads, and sub-agents can share it.
7. **Shell tool is trusted-use only.** Containerize before exposing to
   untrusted input.

## Scheduling

Schedules are persisted and survive restarts; `boot!` reloads them. Formats:
`cron:0 9 * * *`, `every:30m`, `at:2026-12-24 09:00`. A fired job runs
`Agent#run(prompt, thread_id:)` in its own thread and records the result
(truncated) back into the store, visible via `schedule_list`.

## Evals

Run before every change; exit code is non-zero on failure, so it slots into
ci or a pre-commit hook:

```sh
bin/master-evals                      # 6 deterministic offline cases
bin/master-evals --json report.json   # + machine-readable report
bin/master-evals --live               # + live case against a real LLM
```

Offline cases drive the real agent loop with scripted LLM responses and
assert on answers, tool arguments, memory effects, error recovery, step
guards, sub-agent scoping and schedule persistence. Live cases use the
real endpoint (configure via flags or `MASTER_LLM_*` env vars) and check
behaviour heuristically. Extend `evals/cases.rb` as MASTER grows.

## Remaining roadmap

- Vector store upgrade: sqlite-vec or Postgres + pgvector (`neighbor` gem)
  when brute-force cosine outgrows tens of thousands of notes
- Alternative embedders: `transformers.rb` (no server needed) behind the same
  `embed(text) -> Array<Float>` interface
- Fine-tuning (much later): LoRA on an open-weights model via Python tooling
  called from Ruby
