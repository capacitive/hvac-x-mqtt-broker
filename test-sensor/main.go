package main

import (
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	mqtt "github.com/eclipse/paho.mqtt.golang"
	"github.com/joho/godotenv"
	"github.com/kelseyhightower/envconfig"
)

type Config struct {
	BrokerURL string        `envconfig:"BROKER_URL" default:"tcp://localhost:1883"`
	ClientID  string        `envconfig:"CLIENT_ID" default:"test-sail-sensor"`
	Topic     string        `envconfig:"TOPIC" default:"starcaf/contrl/sensor/hvac/sail/attributes"`
	Interval  time.Duration `envconfig:"INTERVAL" default:"100ms"`
}

type SensorPayload struct {
	FanSensor string `json:"fan-sensor"`
}

type model struct {
	client    mqtt.Client
	config    Config
	state     string
	autoMode  bool
	input     string
	logs      []string
	connected bool
	quitting  bool
}

type tickMsg time.Time
type logMsg string

var (
	// Star Trek color scheme
	primaryColor   = lipgloss.Color("#00D4FF") // LCARS blue
	secondaryColor = lipgloss.Color("#FF9900") // LCARS orange
	accentColor    = lipgloss.Color("#CC99CC") // LCARS purple
	successColor   = lipgloss.Color("#99FF99") // Green
	warningColor   = lipgloss.Color("#FFCC00") // Yellow
	errorColor     = lipgloss.Color("#FF6666") // Red
	bgColor        = lipgloss.Color("#000000") // Black

	// Styles
	headerStyle = lipgloss.NewStyle().
			Foreground(primaryColor).
			Background(bgColor).
			Bold(true).
			Padding(0, 1).
			Border(lipgloss.RoundedBorder()).
			BorderForeground(primaryColor)

	statusStyle = lipgloss.NewStyle().
			Foreground(secondaryColor).
			Background(bgColor).
			Padding(0, 1).
			Border(lipgloss.RoundedBorder()).
			BorderForeground(secondaryColor)

	logStyle = lipgloss.NewStyle().
			Foreground(accentColor).
			Background(bgColor).
			Padding(1).
			Border(lipgloss.RoundedBorder()).
			BorderForeground(accentColor).
			Height(8)

	inputStyle = lipgloss.NewStyle().
			Foreground(primaryColor).
			Background(bgColor).
			Padding(0, 1).
			Border(lipgloss.RoundedBorder()).
			BorderForeground(primaryColor)

	commandStyle = lipgloss.NewStyle().
			Foreground(warningColor).
			Background(bgColor).
			Padding(0, 1)
)

func main() {
	godotenv.Load()
	var cfg Config
	if err := envconfig.Process("", &cfg); err != nil {
		log.Fatal(err)
	}

	// Connect to MQTT broker
	opts := mqtt.NewClientOptions()
	opts.AddBroker(cfg.BrokerURL)
	opts.SetClientID(cfg.ClientID)

	client := mqtt.NewClient(opts)

	m := model{
		client:    client,
		config:    cfg,
		state:     "OFF",
		autoMode:  false,
		logs:      []string{"STARFLEET SENSOR ARRAY INITIALIZING..."},
		connected: false,
	}

	// Connect to broker
	if token := client.Connect(); token.Wait() && token.Error() != nil {
		m.logs = append(m.logs, fmt.Sprintf("CONNECTION FAILED: %v", token.Error()))
	} else {
		m.connected = true
		m.logs = append(m.logs, "SENSOR ARRAY ONLINE - READY FOR OPERATIONS")
	}

	p := tea.NewProgram(&m, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		log.Fatal(err)
	}
}

func (m *model) Init() tea.Cmd {
	return tea.Batch(
		tickCmd(m.config.Interval),
		tea.EnterAltScreen,
	)
}

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if m.quitting {
			return m, tea.Quit
		}

		switch msg.String() {
		case "ctrl+c", "q":
			m.quitting = true
			m.client.Disconnect(250)
			return m, tea.Quit

		case "enter":
			return m.handleCommand()

		case "backspace":
			if len(m.input) > 0 {
				m.input = m.input[:len(m.input)-1]
			}

		default:
			m.input += msg.String()
		}

	case tickMsg:
		if m.autoMode && m.connected {
			if m.state == "ON" {
				m.publishState("OFF")
			} else {
				m.publishState("ON")
			}
		}
		return m, tickCmd(m.config.Interval)

	case logMsg:
		m.logs = append(m.logs, string(msg))
		if len(m.logs) > 6 {
			m.logs = m.logs[1:]
		}
	}

	return m, nil
}

func (m *model) handleCommand() (tea.Model, tea.Cmd) {
	cmd := strings.TrimSpace(strings.ToLower(m.input))
	m.input = ""

	switch cmd {
	case "on":
		m.autoMode = false
		m.publishState("ON")
		return m, m.logCmd("MANUAL MODE: SENSOR ACTIVATED")

	case "off":
		m.autoMode = false
		m.publishState("OFF")
		return m, m.logCmd("MANUAL MODE: SENSOR DEACTIVATED")

	case "auto":
		m.autoMode = !m.autoMode
		if m.autoMode {
			return m, m.logCmd("AUTO MODE: RAPID SUCCESSION ENGAGED")
		}
		return m, m.logCmd("AUTO MODE: DISENGAGED")

	case "stop":
		m.autoMode = false
		return m, m.logCmd("AUTO MODE: EMERGENCY STOP")

	case "status":
		status := fmt.Sprintf("SENSOR: %s | MODE: %s | CONNECTION: %s",
			m.state, m.getMode(), m.getConnectionStatus())
		return m, m.logCmd(status)

	case "help":
		return m, m.logCmd("COMMANDS: on, off, auto, stop, status, help, quit")

	case "quit":
		m.quitting = true
		m.client.Disconnect(250)
		return m, tea.Quit

	default:
		if cmd != "" {
			return m, m.logCmd("UNKNOWN COMMAND - TYPE 'help' FOR ASSISTANCE")
		}
	}

	return m, nil
}

func (m *model) publishState(state string) {
	if !m.connected {
		return
	}

	m.state = state
	payload := SensorPayload{FanSensor: state}
	data, _ := json.Marshal(payload)

	token := m.client.Publish(m.config.Topic, 0, false, data)
	token.Wait()
}

func (m *model) logCmd(msg string) tea.Cmd {
	return func() tea.Msg {
		return logMsg(msg)
	}
}

func (m *model) getMode() string {
	if m.autoMode {
		return "AUTO"
	}
	return "MANUAL"
}

func (m *model) getConnectionStatus() string {
	if m.connected {
		return "ONLINE"
	}
	return "OFFLINE"
}

func (m *model) View() string {
	if m.quitting {
		return "SENSOR ARRAY SHUTTING DOWN...\n"
	}

	// Header
	header := headerStyle.Render("⭐ STARFLEET SENSOR CONTROL INTERFACE ⭐")

	// Status panel
	statusContent := fmt.Sprintf(
		"SENSOR STATE: %s\nOPERATION MODE: %s\nCONNECTION: %s\nBROKER: %s\nINTERVAL: %v",
		m.state, m.getMode(), m.getConnectionStatus(), m.config.BrokerURL, m.config.Interval,
	)
	status := statusStyle.Render(statusContent)

	// Logs panel
	logContent := strings.Join(m.logs, "\n")
	logs := logStyle.Render(logContent)

	// Commands panel
	commands := commandStyle.Render(
		"AVAILABLE COMMANDS:\n" +
			"on     - Activate sensor\n" +
			"off    - Deactivate sensor\n" +
			"auto   - Toggle auto mode\n" +
			"stop   - Stop auto mode\n" +
			"status - Show status\n" +
			"help   - Show commands\n" +
			"quit   - Exit system",
	)

	// Input panel
	inputContent := fmt.Sprintf("COMMAND INPUT: %s█", m.input)
	input := inputStyle.Render(inputContent)

	// Layout
	top := lipgloss.JoinHorizontal(lipgloss.Top, status, " ", commands)
	middle := logs
	bottom := input

	return lipgloss.JoinVertical(
		lipgloss.Left,
		header,
		"",
		top,
		"",
		middle,
		"",
		bottom,
		"",
		"Press Ctrl+C or 'q' to quit",
	)
}

func tickCmd(interval time.Duration) tea.Cmd {
	return tea.Tick(interval, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}
