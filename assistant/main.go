// Command assistant is a terminal harness built on PiG's coding SDK.
//
// PiG owns the agent loop, tool dispatch, JSONL sessions, context accounting,
// compaction and provider auth. This command supplies the surface: a Bubble Tea
// TUI with streaming text, tool cards, a model picker and system-prompt control.
//
// Skills, context files (AGENTS.md/CLAUDE.md), prompt templates, extensions and
// MCP are disabled at construction. The system prompt is empty unless a file or
// flag supplies one.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/MichaelKinsy/PiG/agent"
	"github.com/MichaelKinsy/PiG/ai"
	"github.com/MichaelKinsy/PiG/coding"
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	accent    = lipgloss.Color("62")
	toolColor = lipgloss.Color("214")
	dimColor  = lipgloss.Color("240")
	errorRed  = lipgloss.Color("196")
	okGreen   = lipgloss.Color("78")

	userStyle = lipgloss.NewStyle().Foreground(accent).Bold(true)
	toolStyle = lipgloss.NewStyle().Foreground(toolColor).Bold(true)
	dimStyle  = lipgloss.NewStyle().Foreground(dimColor)
	errStyle  = lipgloss.NewStyle().Foreground(errorRed)
	okStyle   = lipgloss.NewStyle().Foreground(okGreen)
	headStyle = lipgloss.NewStyle().Bold(true).Foreground(accent)
)

type config struct {
	model      string
	system     string
	systemFile string
	cwd        string
	sessionDir string
	noSession  bool
}

func main() {
	var cfg config
	flag.StringVar(&cfg.model, "model", "", "provider/model spec (default: saved model or groq/qwen/qwen3.8-27b)")
	flag.StringVar(&cfg.system, "system", "", "inline system prompt (default: system.md or none)")
	flag.StringVar(&cfg.systemFile, "system-file", "", "system prompt file")
	flag.StringVar(&cfg.cwd, "cwd", "", "working directory (default: current)")
	flag.StringVar(&cfg.sessionDir, "session-dir", "", "session log directory")
	flag.BoolVar(&cfg.noSession, "no-session", false, "disable session persistence")
	flag.Parse()

	h, err := newHarness(cfg)
	if err != nil {
		fmt.Fprintln(os.Stderr, "assistant:", err)
		os.Exit(1)
	}
	defer h.Close()

	p := tea.NewProgram(newModel(h), tea.WithAltScreen(), tea.WithMouseCellMotion())
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "assistant:", err)
		os.Exit(1)
	}
}

type harness struct {
	services   *coding.AgentSessionServices
	runtime    *coding.Runtime
	session    *coding.Session
	model      *ai.Model
	start      coding.SessionStartOptions
	cwd        string
	stateDir   string
	systemText string
	systemPath string
}

func newHarness(cfg config) (*harness, error) {
	cwd := cfg.cwd
	if cwd == "" {
		var err error
		if cwd, err = os.Getwd(); err != nil {
			return nil, err
		}
	}
	if abs, err := filepath.Abs(cwd); err == nil {
		cwd = abs
	}

	stateDir := filepath.Join(stateHome(), "caelestia-assistant")
	systemText, systemPath, err := loadSystem(cfg)
	if err != nil {
		return nil, err
	}

	agentDir := coding.DefaultAgentDir()
	services, err := coding.CreateAgentSessionServices(coding.CreateAgentSessionServicesOptions{
		CWD:      cwd,
		AgentDir: agentDir,
		ResourceLoaderOptions: &coding.DefaultResourceLoaderOptions{
			CWD:               cwd,
			AgentDir:          agentDir,
			NoSkills:          true,
			NoContextFiles:    true,
			NoPromptTemplates: true,
			NoExtensions:      true,
		},
	})
	if err != nil {
		return nil, err
	}

	runtime, err := coding.NewRuntime(coding.RuntimeOptions{Services: services})
	if err != nil {
		services.Close()
		return nil, err
	}

	spec := cfg.model
	if spec == "" {
		if saved, err := os.ReadFile(filepath.Join(stateDir, "model")); err == nil {
			spec = strings.TrimSpace(string(saved))
		}
	}
	if spec == "" {
		spec = "groq/qwen/qwen3.8-27b"
	}

	model, err := coding.BuildModel(spec, services)
	if err != nil {
		runtime.Close()
		services.Close()
		return nil, fmt.Errorf("build model %q: %w", spec, err)
	}

	sessionDir := cfg.sessionDir
	if sessionDir == "" {
		sessionDir = filepath.Join(stateDir, "sessions")
	}
	if !cfg.noSession {
		if err := os.MkdirAll(sessionDir, 0o700); err != nil {
			runtime.Close()
			services.Close()
			return nil, err
		}
	}

	start := coding.SessionStartOptions{
		Model:                model,
		SessionDir:           sessionDir,
		NoSession:            cfg.noSession,
		ResourceLoader:       coding.NoResources,
		SkipExtensionTools:   true,
		SystemPromptSections: promptSections(systemText),
	}
	session, err := runtime.New(start)
	if err != nil {
		runtime.Close()
		services.Close()
		return nil, err
	}

	return &harness{
		services: services, runtime: runtime, session: session, model: model,
		start: start, cwd: cwd, stateDir: stateDir,
		systemText: systemText, systemPath: systemPath,
	}, nil
}

func (h *harness) newSession() (*coding.Session, error) {
	return h.runtime.New(h.start)
}

func (h *harness) applySystem(text string) {
	h.systemText = text
	h.start.SystemPrompt = ""
	h.start.SystemPromptSections = promptSections(text)
	h.session.SetSystemPromptSections(h.start.SystemPromptSections)
}

func (h *harness) Close() {
	if h.session != nil {
		_ = h.session.Close()
	}
	if h.runtime != nil {
		_ = h.runtime.Close()
	}
	if h.services != nil {
		h.services.Close()
	}
}

func promptSections(text string) ai.OrderedSections {
	if strings.TrimSpace(text) == "" {
		return ai.OrderedSections{}
	}
	value := text
	return ai.OrderedSections{{Name: "preamble", Value: &value}}
}

func loadSystem(cfg config) (string, string, error) {
	if cfg.system != "" {
		return cfg.system, "", nil
	}
	explicit := cfg.systemFile != ""
	path := cfg.systemFile
	if path == "" {
		path = filepath.Join(configHome(), "caelestia-assistant", "system.md")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) && !explicit {
			return "", path, nil
		}
		return "", path, err
	}
	return strings.TrimSpace(string(data)), path, nil
}

func stateHome() string {
	if dir := os.Getenv("XDG_STATE_HOME"); dir != "" {
		return dir
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "state")
}

func configHome() string {
	if dir := os.Getenv("XDG_CONFIG_HOME"); dir != "" {
		return dir
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config")
}

type itemKind int

const (
	kindUser itemKind = iota
	kindAssistant
	kindTool
	kindSystem
)

type item struct {
	kind     itemKind
	text     string
	toolID   string
	toolName string
	args     string
	output   string
	durMs    int64
	isError  bool
}

type screen int

const (
	screenChat screen = iota
	screenHelp
	screenModels
)

type deltaMsg string
type eventMsg struct{ event agent.AgentEvent }
type eventClosedMsg struct{}
type turnDoneMsg struct{ err error }
type modelsMsg struct {
	models []*ai.Model
	err    error
}
type tickMsg time.Time

type model struct {
	h      *harness
	vp     viewport.Model
	input  textarea.Model
	events <-chan agent.AgentEvent

	items   []item
	running bool
	started time.Time
	frame   int
	cancel  context.CancelFunc

	screen   screen
	models   []*ai.Model
	modelQ   string
	cursor   int
	offset   int
	modelErr error

	width     int
	height    int
	sessionID string
}

func newModel(h *harness) model {
	ta := textarea.New()
	ta.Placeholder = "Message…"
	ta.Prompt = "› "
	ta.ShowLineNumbers = false
	ta.CharLimit = 8000
	ta.SetHeight(3)
	ta.KeyMap.InsertNewline.SetKeys("ctrl+j")
	ta.Focus()

	vp := viewport.New(0, 0)
	vp.MouseWheelEnabled = true

	return model{
		h:         h,
		vp:        vp,
		input:     ta,
		events:    h.session.Events(),
		sessionID: h.session.ID(),
	}
}

func (m model) Init() tea.Cmd {
	return tea.Batch(textarea.Blink, waitForEvent(m.events), loadModels(m.h))
}

func loadModels(h *harness) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
		defer cancel()
		models, err := h.services.ModelRuntime().GetAvailable(ctx)
		if len(models) == 0 {
			models = h.services.ModelRuntime().GetModels()
		}
		return modelsMsg{models: models, err: err}
	}
}

func waitForEvent(ch <-chan agent.AgentEvent) tea.Cmd {
	return func() tea.Msg {
		ev, ok := <-ch
		if !ok {
			return eventClosedMsg{}
		}
		return eventMsg{event: ev}
	}
}

func tick() tea.Cmd {
	return tea.Tick(100*time.Millisecond, func(t time.Time) tea.Msg { return tickMsg(t) })
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		m.vp.Width = max(1, msg.Width-2)
		m.vp.Height = max(1, msg.Height-7)
		m.input.SetWidth(max(1, msg.Width-6))
		m.refreshView()
		return m, nil

	case tea.MouseMsg:
		if m.screen == screenChat {
			var cmd tea.Cmd
			m.vp, cmd = m.vp.Update(msg)
			return m, cmd
		}
		return m, nil

	case tea.KeyMsg:
		if m.screen == screenHelp {
			switch msg.String() {
			case "esc", "enter", "?", "q":
				m.screen = screenChat
			}
			return m, nil
		}
		if m.screen == screenModels {
			return m.updateModels(msg)
		}
		switch msg.String() {
		case "ctrl+c":
			if m.running {
				m.cancel()
				return m, nil
			}
			return m, tea.Quit
		case "ctrl+d":
			return m, tea.Quit
		case "esc":
			if m.running {
				m.cancel()
			}
			return m, nil
		case "enter":
			if m.running {
				return m, nil
			}
			text := strings.TrimSpace(m.input.Value())
			if text == "" {
				return m, nil
			}
			m.input.SetValue("")
			m.input.SetHeight(3)
			if strings.HasPrefix(text, "/") {
				return m.command(text)
			}
			return m.send(text)
		case "?":
			if !m.running && strings.TrimSpace(m.input.Value()) == "" {
				m.screen = screenHelp
				return m, nil
			}
		case "pgup", "pgdown":
			var cmd tea.Cmd
			m.vp, cmd = m.vp.Update(msg)
			return m, cmd
		}

	case deltaMsg:
		m.appendDelta(string(msg))
		return m, waitForEvent(m.events)

	case eventMsg:
		m.handleEvent(msg.event)
		return m, waitForEvent(m.events)

	case eventClosedMsg:
		return m, nil

	case modelsMsg:
		m.models = sortModels(msg.models)
		if msg.err != nil && len(m.models) == 0 {
			m.modelErr = msg.err
		}
		return m, nil

	case tickMsg:
		if m.running {
			m.frame++
			return m, tick()
		}
		return m, nil

	case turnDoneMsg:
		m.running = false
		m.cancel = nil
		if msg.err != nil && !errors.Is(msg.err, context.Canceled) {
			m.addSystem("error: " + msg.err.Error())
		}
		m.refreshView()
		return m, nil
	}

	var cmd tea.Cmd
	m.input, cmd = m.input.Update(msg)
	return m, cmd
}

func (m model) updateModels(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	items := m.filteredModels()
	switch msg.String() {
	case "esc":
		m.screen = screenChat
		return m, nil
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
	case "down", "j":
		if m.cursor < len(items)-1 {
			m.cursor++
		}
	case "pgup":
		m.cursor = max(0, m.cursor-10)
	case "pgdown":
		m.cursor = min(len(items)-1, m.cursor+10)
	case "home":
		m.cursor = 0
	case "end":
		m.cursor = max(0, len(items)-1)
	case "backspace":
		if m.modelQ != "" {
			m.modelQ = m.modelQ[:len(m.modelQ)-1]
			m.cursor = 0
		}
	case "ctrl+u":
		m.modelQ = ""
		m.cursor = 0
	case "enter":
		if len(items) == 0 {
			return m, nil
		}
		chosen := items[m.cursor]
		if err := m.h.session.SetModel(chosen); err != nil {
			m.screen = screenChat
			m.addSystem("model: " + err.Error())
			return m, nil
		}
		m.h.model = chosen
		m.h.start.Model = chosen
		saveModel(m.h.stateDir, modelSpec(chosen))
		m.screen = screenChat
		m.addSystem("model → " + modelSpec(chosen))
		m.refreshView()
		return m, nil
	default:
		if msg.Type == tea.KeyRunes {
			m.modelQ += string(msg.Runes)
			m.cursor = 0
		}
	}
	m.clampPicker()
	return m, nil
}

func (m *model) clampPicker() {
	items := m.filteredModels()
	if m.cursor >= len(items) {
		m.cursor = max(0, len(items)-1)
	}
	visible := m.pickerRows()
	if m.cursor < m.offset {
		m.offset = m.cursor
	}
	if m.cursor >= m.offset+visible {
		m.offset = m.cursor - visible + 1
	}
	if m.offset < 0 {
		m.offset = 0
	}
}

func (m model) pickerRows() int {
	return max(1, m.height-8)
}

func (m *model) handleEvent(ev agent.AgentEvent) {
	switch e := ev.(type) {
	case agent.MessageUpdateEvent:
		if d, ok := e.AssistantMessageEvent.(ai.TextDeltaEvent); ok {
			m.appendDelta(d.Delta)
		}
	case agent.ToolExecutionStartEvent:
		m.items = append(m.items, item{
			kind:     kindTool,
			toolID:   e.ToolCallID,
			toolName: e.ToolName,
			args:     compactJSON(e.Args),
		})
		m.refreshView()
	case agent.ToolExecutionUpdateEvent:
		if text := resultText(e.PartialResult); text != "" {
			m.setToolOutput(e.ToolCallID, text, false, 0)
		}
	case agent.ToolExecutionEndEvent:
		text := resultText(e.Result)
		if text == "" && e.IsError {
			text = "failed"
		}
		dur := int64(0)
		if e.DurationMs != nil {
			dur = *e.DurationMs
		}
		m.setToolOutput(e.ToolCallID, text, e.IsError, dur)
	}
}

func (m *model) appendDelta(delta string) {
	if delta == "" {
		return
	}
	if n := len(m.items); n > 0 && m.items[n-1].kind == kindAssistant {
		m.items[n-1].text += delta
	} else {
		m.items = append(m.items, item{kind: kindAssistant, text: delta})
	}
	m.refreshView()
}

func (m *model) setToolOutput(id, text string, isError bool, dur int64) {
	for i := len(m.items) - 1; i >= 0; i-- {
		if m.items[i].kind == kindTool && m.items[i].toolID == id {
			m.items[i].output = text
			m.items[i].isError = isError
			if dur > 0 {
				m.items[i].durMs = dur
			}
			m.refreshView()
			return
		}
	}
}

func (m *model) addSystem(text string) {
	m.items = append(m.items, item{kind: kindSystem, text: text})
	m.refreshView()
}

func (m model) send(text string) (tea.Model, tea.Cmd) {
	m.items = append(m.items, item{kind: kindUser, text: text})
	m.running = true
	m.started = time.Now()
	m.frame = 0

	ctx, cancel := context.WithCancel(context.Background())
	m.cancel = cancel
	session := m.h.session
	m.refreshView()

	cmd := func() tea.Msg {
		_, err := session.Send(ctx, text)
		return turnDoneMsg{err: err}
	}
	return m, tea.Batch(cmd, tick())
}

func (m model) command(text string) (tea.Model, tea.Cmd) {
	fields := strings.Fields(text)
	cmd := fields[0]
	rest := strings.TrimSpace(strings.TrimPrefix(text, cmd))

	switch cmd {
	case "/quit", "/exit":
		return m, tea.Quit
	case "/help":
		m.screen = screenHelp
		return m, nil
	case "/model":
		m.modelQ = rest
		m.cursor = 0
		m.offset = 0
		m.screen = screenModels
		return m, nil
	case "/tools":
		m.addSystem("tools: " + strings.Join(m.h.session.ActiveToolNames(), ", "))
	case "/session":
		m.addSystem(fmt.Sprintf("session %s\n%s", m.sessionID, m.h.session.Path()))
	case "/system":
		m.commandSystem(rest)
	case "/new":
		old := m.h.session
		session, err := m.h.newSession()
		if err != nil {
			m.addSystem("error: " + err.Error())
			return m, nil
		}
		_ = old.Close()
		m.h.session = session
		m.events = session.Events()
		m.sessionID = session.ID()
		m.items = nil
		m.addSystem("new session " + m.sessionID)
		return m, waitForEvent(m.events)
	default:
		m.addSystem("unknown command: " + text)
	}
	return m, nil
}

func (m *model) commandSystem(arg string) {
	switch {
	case arg == "":
		if strings.TrimSpace(m.h.systemText) == "" {
			m.addSystem("system prompt: (empty)")
		} else {
			m.addSystem("system prompt:\n" + truncate(m.h.systemText, 4000))
		}
		if m.h.systemPath != "" {
			m.addSystem("file: " + m.h.systemPath)
		}
	case arg == "clear":
		m.h.applySystem("")
		m.addSystem("system prompt cleared")
	case arg == "reload":
		if m.h.systemPath == "" {
			m.addSystem("no system prompt file")
			return
		}
		text, _, err := loadSystem(config{systemFile: m.h.systemPath})
		if err != nil {
			m.addSystem("error: " + err.Error())
			return
		}
		m.h.applySystem(text)
		m.addSystem("system prompt reloaded")
	case strings.HasPrefix(arg, "set "):
		m.h.applySystem(strings.TrimSpace(strings.TrimPrefix(arg, "set ")))
		m.addSystem("system prompt updated")
	default:
		m.addSystem("usage: /system | /system set <text> | /system clear | /system reload")
	}
}

func (m *model) refreshView() {
	wasBottom := m.vp.AtBottom()
	m.vp.SetContent(m.transcript())
	if wasBottom {
		m.vp.GotoBottom()
	}
}

func (m model) transcript() string {
	if len(m.items) == 0 {
		return dimStyle.Render("PiG harness · no skills · no context files · system prompt: "+promptState(m.h)) +
			"\n\n" + dimStyle.Render("Type a request, or /help.")
	}
	width := max(20, m.vp.Width)
	var blocks []string
	for _, it := range m.items {
		switch it.kind {
		case kindUser:
			blocks = append(blocks, userStyle.Render("› ")+wrapText(it.text, width-2))
		case kindAssistant:
			blocks = append(blocks, wrapText(it.text, width))
		case kindTool:
			blocks = append(blocks, m.renderTool(it, width))
		case kindSystem:
			blocks = append(blocks, dimStyle.Render(wrapText(it.text, width)))
		}
	}
	return strings.Join(blocks, "\n\n")
}

func (m model) renderTool(it item, width int) string {
	title := toolStyle.Render(it.toolName)
	if it.durMs > 0 {
		title += dimStyle.Render(fmt.Sprintf(" %dms", it.durMs))
	}
	if it.args != "" && it.args != "{}" {
		title += dimStyle.Render(" " + truncate(it.args, max(20, width-20)))
	}
	body := strings.TrimRight(it.output, "\n")
	if body != "" {
		body = wrapText(body, max(20, width-6))
		body = "\n" + clipLines(body, max(20, width-6), 12)
		if it.isError {
			body = errStyle.Render(body)
		}
	}
	style := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(dimColor).
		Padding(0, 1)
	if it.isError {
		style = style.BorderForeground(errorRed)
	}
	return style.Render(title + body)
}

func (m model) headerView() string {
	left := headStyle.Render("assistant")
	modelPart := lipgloss.NewStyle().Foreground(toolColor).Render(modelSpec(m.h.model))
	parts := []string{left, modelPart}
	if ctx := contextLabel(m.h.session); ctx != "" {
		parts = append(parts, dimStyle.Render(ctx))
	}
	parts = append(parts, dimStyle.Render("sess "+shortID(m.sessionID)))
	return strings.Join(parts, dimStyle.Render("  ·  "))
}

func (m model) statusView() string {
	if m.screen == screenModels {
		return dimStyle.Render("type to filter · ↑↓ select · enter switch · ctrl+u clear · esc cancel")
	}
	if m.screen == screenHelp {
		return dimStyle.Render("esc close")
	}
	if m.running {
		frames := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
		spin := frames[m.frame%len(frames)]
		return dimStyle.Render(fmt.Sprintf("%s %s · esc cancel · ctrl+c cancel", spin, time.Since(m.started).Round(time.Millisecond)))
	}
	return dimStyle.Render("enter send · ctrl+j newline · /model · /system · ? help")
}

func (m model) inputView() string {
	style := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(dimColor).
		Padding(0, 1)
	return style.Width(max(1, m.width-2)).Render(m.input.View())
}

func (m model) helpView() string {
	text := strings.Join([]string{
		headStyle.Render("assistant"),
		"",
		dimStyle.Render("PiG agent loop · tools · sessions · compaction"),
		dimStyle.Render("no skills · no context files · prompt: " + promptState(m.h)),
		"",
		headStyle.Render("Keys"),
		"enter        send",
		"ctrl+j       newline",
		"esc          cancel / close",
		"ctrl+c       cancel, then quit",
		"pgup/pgdn    scroll",
		"?            help",
		"",
		headStyle.Render("Commands"),
		"/model [q]   switch provider/model",
		"/system      show prompt",
		"/system set <text>",
		"/system clear",
		"/system reload",
		"/tools       active tools",
		"/session     session id and log",
		"/new         new session",
		"/quit",
		"",
		dimStyle.Render("system file: " + displayPath(m.h.systemPath)),
		dimStyle.Render("providers:  GROQ_API_KEY, OPENAI_API_KEY, OPENROUTER_API_KEY, …"),
	}, "\n")
	return lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(accent).
		Padding(1, 2).
		Width(max(40, m.width-4)).
		Height(max(10, m.height-4)).
		Render(text)
}

func (m *model) modelsView() string {
	items := m.filteredModels()
	rows := m.pickerRows()
	if m.offset > len(items)-rows {
		m.offset = max(0, len(items)-rows)
	}
	header := headStyle.Render("Models")
	if m.modelQ != "" {
		header += dimStyle.Render("  filter: " + m.modelQ)
	}
	if len(items) == 0 {
		msg := "No models available. Export a provider key (GROQ_API_KEY, OPENAI_API_KEY, OPENROUTER_API_KEY) and reopen /model."
		return lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(accent).
			Padding(1, 2).Width(max(40, m.width-4)).Height(max(10, m.height-4)).
			Render(header + "\n\n" + dimStyle.Render(msg))
	}

	start := min(m.offset, max(0, len(items)-1))
	end := min(len(items), start+rows)
	var lines []string
	lines = append(lines, header, "")
	for i := start; i < end; i++ {
		mod := items[i]
		spec := modelSpec(mod)
		meta := fmt.Sprintf("%dK ctx", mod.Capabilities.ContextWindow/1000)
		if mod.Capabilities.ContextWindow <= 0 {
			meta = ""
		}
		if i == m.cursor {
			lines = append(lines, userStyle.Render("▸ "+spec)+dimStyle.Render("  "+meta))
		} else {
			lines = append(lines, "  "+spec+dimStyle.Render("  "+meta))
		}
	}
	lines = append(lines, "", dimStyle.Render(fmt.Sprintf("%d/%d", m.cursor+1, len(items))))
	return lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(accent).
		Padding(1, 2).
		Width(max(40, m.width-4)).
		Height(max(10, m.height-4)).
		Render(strings.Join(lines, "\n"))
}

func (m model) View() string {
	header := m.headerView()
	status := m.statusView()
	switch m.screen {
	case screenHelp:
		return lipgloss.JoinVertical(lipgloss.Left, header, m.helpView(), status)
	case screenModels:
		return lipgloss.JoinVertical(lipgloss.Left, header, m.modelsView(), status)
	default:
		return lipgloss.JoinVertical(lipgloss.Left, header, m.vp.View(), m.inputView(), status)
	}
}

func (m model) filteredModels() []*ai.Model {
	q := strings.ToLower(strings.TrimSpace(m.modelQ))
	if q == "" {
		return m.models
	}
	out := make([]*ai.Model, 0, len(m.models))
	for _, mod := range m.models {
		if strings.Contains(strings.ToLower(modelSpec(mod)), q) {
			out = append(out, mod)
		}
	}
	return out
}

func sortModels(models []*ai.Model) []*ai.Model {
	seen := make(map[string]bool, len(models))
	out := make([]*ai.Model, 0, len(models))
	for _, mod := range models {
		if mod == nil {
			continue
		}
		spec := modelSpec(mod)
		if seen[spec] {
			continue
		}
		seen[spec] = true
		out = append(out, mod)
	}
	sort.SliceStable(out, func(i, j int) bool {
		return modelSpec(out[i]) < modelSpec(out[j])
	})
	return out
}

func modelSpec(m *ai.Model) string {
	if m == nil {
		return ""
	}
	provider := m.ProviderMeta.ProviderID
	if provider == "" {
		return m.ID
	}
	return provider + "/" + m.ID
}

func saveModel(dir, spec string) {
	if dir == "" || spec == "" {
		return
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return
	}
	_ = os.WriteFile(filepath.Join(dir, "model"), []byte(spec+"\n"), 0o600)
}

func contextLabel(s *coding.Session) string {
	usage := s.ContextUsage()
	if usage == nil || usage.Percent == nil {
		return ""
	}
	return fmt.Sprintf("%.0f%% ctx", *usage.Percent)
}

func promptState(h *harness) string {
	if strings.TrimSpace(h.systemText) == "" {
		return "empty"
	}
	return fmt.Sprintf("%d chars", len(h.systemText))
}

func displayPath(path string) string {
	if path == "" {
		return "(none)"
	}
	if home, err := os.UserHomeDir(); err == nil {
		if rel, err := filepath.Rel(home, path); err == nil && !strings.HasPrefix(rel, "..") {
			return "~/" + rel
		}
	}
	return path
}

func compactJSON(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var buf bytes.Buffer
	if err := json.Compact(&buf, raw); err != nil {
		return truncate(string(raw), 160)
	}
	return truncate(buf.String(), 160)
}

func resultText(r agent.AgentToolResult) string {
	var b strings.Builder
	for _, c := range r.Content {
		if t, ok := c.(ai.TextContent); ok {
			b.WriteString(t.Text)
		}
	}
	return strings.TrimSpace(b.String())
}

func shortID(id string) string {
	if len(id) > 8 {
		return id[:8]
	}
	return id
}

func truncate(s string, n int) string {
	if n <= 0 || len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

func wrapText(s string, width int) string {
	if width < 1 {
		return s
	}
	var out []string
	for _, para := range strings.Split(s, "\n") {
		if strings.TrimSpace(para) == "" {
			out = append(out, "")
			continue
		}
		words := strings.Fields(para)
		line := ""
		for _, word := range words {
			switch {
			case line == "":
				line = word
			case len(line)+1+len(word) <= width:
				line += " " + word
			default:
				out = append(out, line)
				line = word
			}
		}
		if line != "" {
			out = append(out, line)
		}
	}
	return strings.Join(out, "\n")
}

func clipLines(s string, width, maxLines int) string {
	lines := strings.Split(s, "\n")
	if len(lines) > maxLines {
		lines = append(lines[:maxLines], dimStyle.Render("…"))
	}
	for i, line := range lines {
		if len(line) > width {
			lines[i] = line[:width] + "…"
		}
	}
	return strings.Join(lines, "\n")
}
