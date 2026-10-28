# assistant

Minimal terminal harness on top of PiG's `coding` SDK. PiG owns the agent loop,
tool dispatch, session log, context accounting, provider auth, and compaction;
this package only supplies the TUI and a strict, empty starting state.

Disabled at construction:

- skills
- context files (`AGENTS.md`, `CLAUDE.md`)
- prompt templates
- extensions and MCP

The system prompt is an empty `ai.OrderedSections`, so PiG does not fall back to
its built-in coding prompt.

## Build

Builds run in GitHub Actions; do not build on the desktop.

```sh
gh workflow run assistant.yml
gh run watch
gh run download <run-id> -n assistant-linux-amd64 -D bin
```

The artifact contains `assistant`.

## Run

```sh
export GROQ_API_KEY='...'
./bin/assistant -model groq/qwen/qwen3.8-27b
```

Flags: `-cwd`, `-system`, `-session-dir`, `-no-session`.

Built-in PiG tools stay active (`read`, `bash`, `edit`, `write`, `grep`,
`find`, `ls`). Sessions are JSONL under
`~/.local/state/caelestia-assistant/sessions`.

In the TUI: `enter` send, `esc` cancel, `ctrl+c` cancel/quit, `ctrl+d` quit,
`/tools`, `/session`, `/new`, `/quit`.
