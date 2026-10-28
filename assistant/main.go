// Command assistant runs PiG's stock terminal UI with a few fixed defaults.
//
// It does not implement a UI or an agent loop. PiG's coding CLI owns the TUI,
// sessions, tools, model picker, context accounting, compaction, and providers.
// This wrapper only supplies:
//
//   - no skills, context files, or prompt templates;
//   - only the web_search tool by default; PiG's prebuilt tools are not selected;
//   - a short default system prompt, unless the caller supplies one;
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

const defaultSystemPrompt = "You are Loio, a personal assistant. Answer briefly and focus on the main point. Use the available tools when they help complete the user's request; do not claim tools or capabilities you do not have. When you use web_search, cite the source URLs."

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
	if !hasArg(args, "--tools", "-t") && !hasArg(args, "--no-tools", "-nt") {
		defaults = append(defaults, "--tools", webSearchToolName, "--no-mcp")
	}
	if !hasSystemPrompt {
		defaults = append(defaults, "--system-prompt", defaultSystemPrompt)
	}

	opts := &cli.MainOptions{
		ExtensionFactories: []extension.InlineExtension{
			extension.NamedInlineExtension{
				Name:    "assistant-web-search",
				Factory: extensionFactory,
				Hidden:  true,
			},
		},
	}

	cli.Main(append(defaults, args...), opts)
}

// extensionFactory registers the web search tool and clears PiG's startup header.
func extensionFactory(api extension.API) error {
	api.RegisterTool(webSearchTool())
	api.OnBeforeProviderRequest(rewriteDeveloperRole)
	return configureHeader(api)
}

// rewriteDeveloperRole maps the OpenAI-compatible developer role back to system.
// Groq's Qwen chat template rejects developer messages, while PiG emits that
// role for reasoning models with developer-role compatibility.
func rewriteDeveloperRole(_ context.Context, event extension.BeforeProviderRequestEvent) (any, error) {
	raw, err := json.Marshal(event.Payload)
	if err != nil {
		return nil, nil
	}
	var payload map[string]any
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil, nil
	}
	changed := false
	if messages, ok := payload["messages"].([]any); ok {
		for _, rawMessage := range messages {
			message, ok := rawMessage.(map[string]any)
			if !ok || message["role"] != "developer" {
				continue
			}
			message["role"] = "system"
			changed = true
		}
	}
	if !changed {
		return nil, nil
	}
	rewritten, err := json.Marshal(payload)
	if err != nil {
		return nil, nil
	}
	return json.RawMessage(rewritten), nil
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
