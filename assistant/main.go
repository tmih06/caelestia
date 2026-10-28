// Command assistant is a minimal terminal harness built on PiG's coding SDK.
//
// It keeps PiG's agent loop, session log, context management, tool dispatch and
// provider plumbing, and replaces only the surface: a small Bubble Tea TUI.
//
// Skills, context files (AGENTS.md/CLAUDE.md), prompt templates, extensions and
// MCP are disabled, and the system prompt is empty.
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
	"strings"
	"time"

	"github.com/MichaelKinsy/PiG/agent"
	"github.com/MichaelKinsy/PiG/ai"
	"github.com/MichaelKinsy/PiG/coding"
	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	userStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("62")).Bold(true)
	toolStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("214"))
	dimStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
	errStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("196"))
)

type config struct {
	model      string
	system     string
	cwd        string
	sessionDir string
	noSession  bool
}

func main() {
	var cfg config
	flag.StringVar(&cfg.model, "model", "groq/qwen/qwen3.8-27b", "provider/model spec")
	flag.StringVar(&cfg.system, "system", "", "custom system prompt (default: none)")
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

	m := newModel(h)
	p := tea.NewProgram(m, tea.WithAltScreen(), tea.WithMouseCellMotion())
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "assistant:", err)
		os.Exit(1)
	}
}

type harness struct {
	services *coding.AgentSessionServices
	runtime  *coding.Runtime
	session  *coding.Session
	model    *ai.Model
	start    coding.SessionStartOptions
	cwd      string
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

	model, err := coding.BuildModel(cfg.model, services)
	if err != nil {
		runtime.Close()
		services.Close()
		return nil, fmt.Errorf("build model %q (is GROQ_API_KEY set?): %w", cfg.model, err)
	}

	sessionDir := cfg.sessionDir
	if sessionDir == "" {
		sessionDir = filepath.Join(stateHome(), "caelestia-assistant", "sessions")
	}
	if !cfg.noSession {
		if err := os.MkdirAll(sessionDir, 0o700); err != nil {
			runtime.Close()
			services.Close()
			return nil, err
		}
	}

	start := coding.SessionStartOptions{
		Model:      model,
		SessionDir: sessionDir,
		NoSession:  cfg.noSession,
		// No resource loader: nothing is discovered, expanded or rendered.
		ResourceLoader:     coding.NoResources,
		SkipExtensionTools: true,
	}
	if cfg.system != "" {
		start.SystemPrompt = cfg.system
	} else {
		// A non-nil empty section list takes the structured path, so PiG does
		// not fall back to its built-in coding prompt.
		start.SystemPromptSections = ai.OrderedSections{}
	}

	session, err := runtime.New(start)
	if err != nil {
		runtime.Close()
		services.Close()
		return nil, err
	}

	return &harness{services: services, runtime: runtime, session: session, model: model, start: start, cwd: cwd}, nil
}

func (h *harness) newSession() (*coding.Session, error) {
	return h.runtime.New(h.start)
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

func stateHome() string {
	if dir := os.Getenv("XDG_STATE_HOME"); dir != "" {
		return dir
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "state")
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
	isError  bool
}

type deltaMsg string
type eventMsg struct{ event agent.AgentEvent }
type eventClosedMsg struct{}
type turnDoneMsg struct{ err error }
type tickMsg time.Time

type model struct {
	h      *harness
	vp     viewport.Model
	input  textinput.Model
	events <-chan agent.AgentEvent

	items     []item
	running   bool
	started   time.Time
	cancel    context.CancelFunc
	width     int
	height    int
	sessionID string
	err       error
}

func newModel(h *harness) model {
	ti := textinput.New()
	ti.Placeholder = "ask, or run a command…"
	ti.Prompt = "› "
	ti.Focus()
	ti.CharLimit = 4000

	vp := viewport.New(0, 0)
	vp.MouseWheelEnabled = true

	return model{
		h:         h,
		vp:        vp,
		input:     ti,
		events:    h.session.Events(),
		sessionID: h.session.ID(),
	}
}

func (m model) Init() tea.Cmd {
	return tea.Batch(textinput.Blink, waitForEvent(m.events))
}

func waitForEvent(ch <-chan agent.AgentEvent) tea.Cmd {
	return func() tea.Msg {
		ev, ok := <-ch
		if !ok {
			return eventClosedMsg{}
		}
		return eventMsg{ev}
	}
}

func tick() tea.Cmd {
	return tea.Tick(200*time.Millisecond, func(t time.Time) tea.Msg { return tickMsg(t) })
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		m.vp.Width = msg.Width
		m.vp.Height = max(1, msg.Height-3)
		m.input.Width = max(1, msg.Width-4)
		m.refreshView()
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			if m.running {
				m.cancel()
				return m, nil
			}
			return m, tea.Quit
		case "esc":
			if m.running {
				m.cancel()
			}
			return m, nil
		case "ctrl+d":
			return m, tea.Quit
		case "enter":
			if m.running {
				return m, nil
			}
			text := strings.TrimSpace(m.input.Value())
			if text == "" {
				return m, nil
			}
			m.input.SetValue("")
			if strings.HasPrefix(text, "/") {
				return m.command(text)
			}
			return m.send(text)
		}

	case deltaMsg:
		m.appendDelta(string(msg))
		return m, waitForEvent(m.events)

	case eventMsg:
		m.handleEvent(msg.event)
		return m, waitForEvent(m.events)

	case eventClosedMsg:
		return m, nil

	case tickMsg:
		if m.running {
			return m, tick()
		}
		return m, nil

	case turnDoneMsg:
		m.running = false
		m.cancel = nil
		if msg.err != nil && !errors.Is(msg.err, context.Canceled) {
			m.err = msg.err
			m.addSystem("error: " + msg.err.Error())
		}
		m.refreshView()
		return m, nil
	}

	var cmd tea.Cmd
	m.input, cmd = m.input.Update(msg)
	return m, cmd
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
			m.setToolOutput(e.ToolCallID, text, false)
		}
	case agent.ToolExecutionEndEvent:
		text := resultText(e.Result)
		if text == "" && e.IsError {
			text = "failed"
		}
		m.setToolOutput(e.ToolCallID, text, e.IsError)
	case agent.AgentEndEvent:
		m.refreshView()
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

func (m *model) setToolOutput(id, text string, isError bool) {
	for i := len(m.items) - 1; i >= 0; i-- {
		if m.items[i].kind == kindTool && m.items[i].toolID == id {
			m.items[i].output = text
			m.items[i].isError = isError
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
	m.err = nil

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
	switch strings.Fields(text)[0] {
	case "/quit", "/exit":
		return m, tea.Quit
	case "/help":
		m.addSystem("enter send · esc cancel · ctrl+c cancel/quit · ctrl+d quit\n/tools  /session  /new  /quit")
		return m, nil
	case "/tools":
		m.addSystem("tools: " + strings.Join(m.h.session.ActiveToolNames(), ", "))
		return m, nil
	case "/session":
		m.addSystem(fmt.Sprintf("session %s\n%s", m.sessionID, m.h.session.Path()))
		return m, nil
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
		return m, nil
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
		return dimStyle.Render("PiG harness · empty system prompt · no skills · no context files\n\nType a request, or /help.")
	}
	var blocks []string
	for _, it := range m.items {
		switch it.kind {
		case kindUser:
			blocks = append(blocks, userStyle.Render("› ")+it.text)
		case kindAssistant:
			blocks = append(blocks, it.text)
		case kindTool:
			head := toolStyle.Render("● " + it.toolName)
			if it.args != "" && it.args != "{}" {
				head += " " + dimStyle.Render(it.args)
			}
			body := truncate(it.output, 4000)
			if it.isError {
				body = errStyle.Render(body)
			}
			if body != "" {
				blocks = append(blocks, head+"\n"+indent(body, "  "))
			} else {
				blocks = append(blocks, head)
			}
		case kindSystem:
			blocks = append(blocks, dimStyle.Render(it.text))
		}
	}
	return strings.Join(blocks, "\n\n")
}

func (m model) View() string {
	status := dimStyle.Render(fmt.Sprintf("%s · %s · %s", m.h.model.ID, shortID(m.sessionID), m.cwd()))
	if m.running {
		status = dimStyle.Render(fmt.Sprintf("running %s · %s · %s · esc to cancel",
			time.Since(m.started).Round(time.Millisecond), m.h.model.ID, shortID(m.sessionID)))
	}
	return lipgloss.JoinVertical(lipgloss.Left, m.vp.View(), m.input.View(), status)
}

func (m model) cwd() string {
	if m.h.cwd == "" {
		return ""
	}
	if home, err := os.UserHomeDir(); err == nil {
		if rel, err := filepath.Rel(home, m.h.cwd); err == nil && !strings.HasPrefix(rel, "..") {
			return "~/" + rel
		}
	}
	return m.h.cwd
}

func compactJSON(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var buf bytes.Buffer
	if err := json.Compact(&buf, raw); err != nil {
		return truncate(string(raw), 120)
	}
	return truncate(buf.String(), 120)
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
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

func indent(s, prefix string) string {
	lines := strings.Split(s, "\n")
	for i := range lines {
		lines[i] = prefix + lines[i]
	}
	return strings.Join(lines, "\n")
}
