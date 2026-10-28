# assistant

Thin wrapper around PiG's stock CLI and TUI. No UI or agent loop is
reimplemented here: `coding/cli.Main` starts the same TUI as `pig`, and PiG owns
sessions, tools, model selection, context accounting, compaction, and providers.

The wrapper adds only:

- `--no-skills`
- `--no-context-files`
- `--no-prompt-templates`
- `--tools web_search --no-mcp`, so none of PiG's prebuilt tools are selected
- `--model ${ASSISTANT_MODEL:-groq/qwen/qwen3.8-27b}` when `--model` is absent
- an inline extension that registers `web_search`, forces an **empty system
  prompt**, and clears the startup header, removing PiG's pig logo

## web_search

The tool returns source-backed results and the model is told to answer in at
most three sentences and cite URLs. No API key is used or read.

Keyless chain, in order:

| Order | Backend | Notes |
| --- | --- | --- |
| 1 | Parallel public MCP (`search.parallel.ai/mcp`) | structured results with excerpts |
| 2 | Exa public MCP (`mcp.exa.ai/mcp`) | keyless neural search |
| 3 | DuckDuckGo HTML (`html.duckduckgo.com`) | POST frontend; bot challenges fall through |
| 4 | Wikipedia REST | factual fallback |
| 5 | DuckDuckGo Instant Answer | last resort |

Results are cached for five minutes. Endpoints can be overridden for tests with
`ASSISTANT_PARALLEL_MCP_URL`, `ASSISTANT_EXA_MCP_URL`, `ASSISTANT_DDG_URL`,
`ASSISTANT_WIKI_URL`, and `ASSISTANT_DDG_INSTANT_URL`. This mirrors the
credential-free part of omp's search chain.

If you pass `--system-prompt` or `--append-system-prompt`, the empty-prompt hook
is not installed and PiG's normal prompt handling applies. If you pass `--tools`
or `--no-tools`, the wrapper uses your selection instead of the default
`web_search` selection.

## Build

Builds run in GitHub Actions; do not build on this machine.

```sh
gh workflow run assistant.yml
gh run watch
gh run download <run-id> -n assistant-linux-amd64 -D bin
```

## Run

```sh
export GROQ_API_KEY='...'
./bin/assistant
```

Use the stock PiG flags and TUI commands, including `--model`, `--print`,
`/model`, `/resume`, `/new`, `--system-prompt`, and provider keys such as
`OPENAI_API_KEY`, `OPENROUTER_API_KEY`, and `ANTHROPIC_API_KEY`.
