package cmd

import (
	"fmt"
	cmd "hvac-x-hub-min/cmd/filesystem"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/mcuadros/go-defaults"
)

// Model holds the application state
type model struct {
	step      int
	message   string
	input     string
	targetDir string
	err       error
	quitting  bool
}

// Messages for async operations
type buildCompleteMsg struct{ err error }
type submoduleCheckMsg struct {
	exists bool
	path   string
}

// Init initializes the model
func (m model) Init() tea.Cmd {
	return nil
}

// Update handles messages and state changes
func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if msg.String() == "ctrl+c" {
			m.quitting = true
			return m, tea.Quit
		}

		if m.step == 0 { // Input stage
			switch msg.String() {
			case "enter":
				if m.input == "" {
					m.message = "Please enter a directory path"
					return m, nil
				}
				m.targetDir = m.input
				m.step = 1
				m.message = "Checking existing structure..."
				return m, func() tea.Msg { return checkSubmodule(m.targetDir) }
			case "backspace":
				if len(m.input) > 0 {
					m.input = m.input[:len(m.input)-1]
				}
			default:
				if len(msg.String()) == 1 {
					m.input += msg.String()
				}
			}
		}

	case submoduleCheckMsg:
		if msg.exists {
			m.message = fmt.Sprintf("✓ Directory structure already exists at %s", msg.path)
			m.step = 3
			return m, tea.Quit
		}
		m.step = 2
		m.message = "Creating directory structure..."
		return m, func() tea.Msg { return buildStructure(m.targetDir) }

	case buildCompleteMsg:
		if msg.err != nil {
			m.err = msg.err
			m.message = fmt.Sprintf("✗ Error: %v", msg.err)
		} else {
			m.message = fmt.Sprintf("✓ Build complete at %s!", m.targetDir)
		}
		m.step = 3
		return m, tea.Quit
	}

	return m, nil
}

// View renders the UI
func (m model) View() string {
	if m.quitting {
		return "Aborted.\n"
	}

	s := "RPi Zero Buildroot Structure Builder\n\n"

	if m.step == 0 {
		s += "Enter target directory path: " + m.input + "█\n"
		s += "\nPress Enter to continue, Ctrl+C to quit"
	} else {
		s += m.message + "\n"
		if m.step < 3 {
			s += "\nPress Ctrl+C to quit"
		}
	}

	return s
}

// checkSubmodule checks if structure already exists
func checkSubmodule(targetDir string) submoduleCheckMsg {
	target, _ := filepath.Abs(targetDir)
	if _, err := os.Stat(filepath.Join(target, "buildroot")); err == nil {
		return submoduleCheckMsg{exists: true, path: target}
	}
	return submoduleCheckMsg{exists: false, path: target}
}

// buildStructure creates the directory structure and git submodule
func buildStructure(targetDir string) buildCompleteMsg {
	target, _ := filepath.Abs(targetDir)
	repoRoot, _ := filepath.Abs(filepath.Join("..", ".."))
	if err := os.MkdirAll(target, 0755); err != nil {
		return buildCompleteMsg{err: err}
	}

	// Get the filesystem structure
	fs := cmd.NewOutTreeFS()
	defaults.SetDefaults(fs)

	// Create root files
	rootFiles := []string{fs.Configin, fs.ExternalDesc, fs.ExternalMk}
	for _, filename := range rootFiles {
		path := filepath.Join(target, filename)
		if err := os.WriteFile(path, []byte("# "+filename+"\n"), 0644); err != nil {
			return buildCompleteMsg{err: err}
		}
	}

	// Create configs and package directories
	for _, dir := range []string{fs.Configs, fs.Package} {
		if err := os.MkdirAll(filepath.Join(target, dir), 0755); err != nil {
			return buildCompleteMsg{err: err}
		}
	}

	// Create board directory structure
	boardPath := filepath.Join(target, fs.BoardDir.Name)

	// Create board/hvacx subdirectory with patches and rootfs_overlay
	hvacxPath := filepath.Join(boardPath, fs.ProjectDir.Name)
	for _, subdir := range []string{fs.ProjectDir.Patches, fs.ProjectDir.RootFsOverlay} {
		if err := os.MkdirAll(filepath.Join(hvacxPath, subdir), 0755); err != nil {
			return buildCompleteMsg{err: err}
		}
	}

	// Create board/common subdirectory with patches and rootfs_overlay
	commonPath := filepath.Join(boardPath, fs.CommmonDir.Name)
	for _, subdir := range []string{fs.CommmonDir.Patches, fs.CommmonDir.RootFsOverlay} {
		if err := os.MkdirAll(filepath.Join(commonPath, subdir), 0755); err != nil {
			return buildCompleteMsg{err: err}
		}
	}

	// Add buildroot as git submodule
	// Calculate relative path from repo root to target
	relPath, _ := filepath.Rel(repoRoot, filepath.Join(target, "buildroot"))
	cmd := exec.Command("git", "submodule", "add",
		"https://gitlab.com/buildroot.org/buildroot.git",
		relPath)
	cmd.Dir = repoRoot

	if output, err := cmd.CombinedOutput(); err != nil {
		// Check if submodule already exists
		if !strings.Contains(string(output), "already exists") {
			return buildCompleteMsg{err: fmt.Errorf("git submodule add failed: %v\n%s", err, output)}
		}
	}

	return buildCompleteMsg{err: nil}
}

func main() {
	p := tea.NewProgram(model{step: 0, message: "Enter target directory path:"})
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}
}
