# assistant

Thin wrapper around PiG's stock CLI and TUI. No UI or agent loop is
reimplemented here: `coding/cli.Main` starts the same TUI as `pig`, and PiG owns
sessions, tools, model selection, context accounting, compaction, and providers.

The wrapper adds only:

- `--no-skills`
- `--no-context-files`
- `--no-prompt-templates`
- `--no-tools`, `--exclude-tools '*'`, `--no-mcp`
- `--model ${ASSISTANT_MODEL:-groq/qwen/qwen3.8-27b}` when `--model` is absent
- an inline extension that forces an **empty system prompt**, clears the
  selected tool list again before each run, and clears the startup header,
  removing PiG's pig logo

If you pass `--system-prompt` or `--append-system-prompt`, the empty-prompt hook
is not installed and PiG's normal prompt handling applies. If you pass `--tools`,
none of the no-tools defaults are added and tools work normally.

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
