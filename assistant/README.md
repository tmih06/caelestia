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

The tool returns a direct answer when a provider supplies one, plus result
titles, URLs, and snippets. The model is told to answer in at most three short
sentences and cite the URLs.

Providers, in order, all free-tier or free:

| Provider | Setup | Notes |
| --- | --- | --- |
| Tavily | `TAVILY_API_KEY` | returns an `answer` plus results; free tier |
| Brave Search API | `BRAVE_API_KEY` | web results; free tier |
| SearXNG | `ASSISTANT_SEARX_URL=https://…` | self-hosted or trusted instance with JSON enabled |
| Wikipedia | none | always tried; best for factual topics |
| DuckDuckGo Instant Answer | none | last fallback; sparse |

Without a key, Wikipedia and DuckDuckGo still answer many factual questions;
general web/news search needs one of the free API keys above. Results are cached
for five minutes. Tests can override endpoints with `ASSISTANT_TAVILY_URL`,
`ASSISTANT_BRAVE_URL`, `ASSISTANT_WIKI_URL`, and `ASSISTANT_DDG_URL`.

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
