// Command assistant runs PiG's stock terminal UI with a few fixed defaults.
//
// It does not implement a UI or an agent loop. PiG's coding CLI owns the TUI,
// sessions, tools, model picker, context accounting, compaction, and providers.
// This wrapper only supplies:
//
//   - no skills, context files, or prompt templates;
//   - an inline before_agent_start hook that forces an empty system prompt
//     unless the caller passes --system-prompt or --append-system-prompt;
//   - a default model when the caller passes no --model.
package main

import (
	"context"
	"os"
	"strings"

	"github.com/MichaelKinsy/PiG/coding/cli"
	"github.com/MichaelKinsy/PiG/coding/extension"
)

const defaultModel = "groq/qwen/qwen3.8-27b"

func main() {
	args := os.Args[1:]
	hasSystemPrompt := hasArg(args, "--system-prompt", "--append-system-prompt")

	var defaults []string
	if !hasArg(args, "--no-skills") {
		defaults = append(defaults, "--no-skills")
	}
	if !hasArg(args, "--no-context-files") {
		defaults = append(defaults, "--no-context-files")
	}
	if !hasArg(args, "--no-prompt-templates") {
		defaults = append(defaults, "--no-prompt-templates")
	}
	if !hasArg(args, "--model") {
		model := os.Getenv("ASSISTANT_MODEL")
		if strings.TrimSpace(model) == "" {
			model = defaultModel
		}
		defaults = append(defaults, "--model", model)
	}

	opts := &cli.MainOptions{}
	if !hasSystemPrompt {
		opts.ExtensionFactories = []extension.InlineExtension{
			extension.NamedInlineExtension{
				Name:    "assistant-empty-prompt",
				Factory: emptySystemPrompt,
				Hidden:  true,
			},
		}
	}

	cli.Main(append(defaults, args...), opts)
}

// emptySystemPrompt replaces the run's system prompt with an empty string. The
// extension result is authoritative for every run, so PiG's coding prompt,
// context files, and discovered prompt text are not sent.
func emptySystemPrompt(api extension.API) error {
	api.OnBeforeAgentStart(func(context.Context, extension.BeforeAgentStartEvent) (extension.BeforeAgentStartEventResult, error) {
		empty := ""
		return extension.BeforeAgentStartEventResult{SystemPrompt: &empty}, nil
	})
	return nil
}

func hasArg(args []string, names ...string) bool {
	for _, arg := range args {
		for _, name := range names {
			if arg == name || strings.HasPrefix(arg, name+"=") {
				return true
			}
		}
	}
	return false
}
