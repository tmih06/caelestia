// Command assistant runs PiG's stock terminal UI with a few fixed defaults.
//
// It does not implement a UI or an agent loop. PiG's coding CLI owns the TUI,
// sessions, tools, model picker, context accounting, compaction, and providers.
// This wrapper only supplies:
//
//   - no skills, context files, or prompt templates;
//   - no tools, unless the caller passes --tools;
//   - an inline before_agent_start hook that forces an empty system prompt and
//     an empty tool selection unless the caller supplies them;
//   - a cleared startup header, removing PiG's pig logo;
//   - a default model when the caller passes no --model.
package main

import (
	"context"
	"encoding/json"
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
	toolsExplicit := hasArg(args, "--tools", "-t")
	if !toolsExplicit {
		if !hasArg(args, "--no-tools", "-nt") {
			defaults = append(defaults, "--no-tools")
		}
		if !hasArg(args, "--exclude-tools", "-xt") {
			defaults = append(defaults, "--exclude-tools", "*")
		}
		if !hasArg(args, "--no-mcp") {
			defaults = append(defaults, "--no-mcp")
		}
	}

	opts := &cli.MainOptions{}
	if !hasSystemPrompt {
		opts.ExtensionFactories = []extension.InlineExtension{
			extension.NamedInlineExtension{
				Name:    "assistant-empty-prompt",
				Factory: extensionFactory(!toolsExplicit),
				Hidden:  true,
			},
		}
	}

	cli.Main(append(defaults, args...), opts)
}

// emptySystemPrompt replaces the run's system prompt with an empty string. The
// extension result is authoritative for every run, so PiG's coding prompt,
// context files, and discovered prompt text are not sent.
func extensionFactory(clearTools bool) extension.ExtensionFactory {
	return func(api extension.API) error {
		api.OnBeforeAgentStart(func(ctx context.Context, _ extension.BeforeAgentStartEvent) (extension.BeforeAgentStartEventResult, error) {
			if clearTools {
				extension.SetBeforeAgentStartSelectedTools(ctx, json.RawMessage(`[]`))
			}
			empty := ""
			return extension.BeforeAgentStartEventResult{SystemPrompt: &empty}, nil
		})
		return configureHeader(api)
	}
}

func configureHeader(api extension.API) error {
	api.OnSessionStart(func(ctx context.Context, _ extension.SessionStartEvent) error {
		extCtx := extension.FromContext(ctx)
		if extCtx == nil {
			return nil
		}
		ui, err := extCtx.UI()
		if err != nil {
			return nil
		}
		ui.SetHeader(extension.FrameHeader(nil, 0))
		return nil
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
