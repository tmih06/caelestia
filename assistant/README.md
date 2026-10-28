# assistant

Terminal harness on top of PiG's `coding` SDK. PiG owns the agent loop, tool
dispatch, JSONL sessions, context accounting, compaction, and provider auth.
This package supplies the TUI and a strict starting state.

## Starting state

- no skills
- no context files (`AGENTS.md`, `CLAUDE.md`)
- no prompt templates
- no extensions or MCP
- **empty system prompt by default**

`ResourceLoader: coding.NoResources` and `SystemPromptSections: ai.OrderedSections{}`
prevent PiG from falling back to its coding prompt.

## System prompt

Resolution order:

1. `-system "text"`
2. `-system-file path`
3. `~/.config/caelestia-assistant/system.md` if it exists
4. empty

In the TUI:

```
/system                 show prompt and path
/system set <text>      replace live
/system clear           clear live
/system reload          re-read the file
```

The file is read at startup and on `/system reload`; `/new` uses the current
prompt.

## Models and providers

`/model` opens a picker; typing filters, `enter` switches, `esc` cancels. The
selection is saved to `~/.local/state/caelestia-assistant/model` and used on the
next launch. Providers come from PiG's registry and appear when their key is set:

```sh
GROQ_API_KEY=...        # groq/...
OPENAI_API_KEY=...      # openai/...
OPENROUTER_API_KEY=...  # openrouter/...
ANTHROPIC_API_KEY=...   # anthropic/...
```

Builds run in GitHub Actions; do not build on this machine.

```sh
gh workflow run assistant.yml
gh run watch
gh run download <run-id> -n assistant-linux-amd64 -D bin
```

## Run

```sh
export GROQ_API_KEY='...'
./bin/assistant -model groq/qwen/qwen3.8-27b
```

Flags: `-model`, `-system`, `-system-file`, `-cwd`, `-session-dir`,
`-no-session`.

Keys: `enter` send, `ctrl+j` newline, `esc` cancel/close, `ctrl+c` cancel then
quit, `pgup/pgdn` scroll, `?` help.

Tools stay active (`read`, `bash`, `edit`, `write`, `grep`, `find`, `ls`).
Sessions are JSONL under `~/.local/state/caelestia-assistant/sessions`.
