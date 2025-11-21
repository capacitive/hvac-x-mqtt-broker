# Console Application Examples

Two versions of a directory structure builder: Bubble Tea (TUI) and Simple (stdin).

## What It Does

Creates a Buildroot external tree directory structure defined in `filesystem.go` at a user-specified path:
- Root files: `Config.in`, `external.desc`, `external.mk`
- Directories: `configs/`, `package/`, `board/`
- Board subdirectories: `board/hvacx/` and `board/common/` with `patches/` and `rootfs_overlay/`
- Git submodule: `buildroot` from GitLab

## Versions

### 1. Bubble Tea Version (`main.go`)
Interactive TUI with inline text input.

### 2. Simple Version (`simple.go`)
Simple stdin input using `bufio.Reader`.

## Simple Version Pattern

The simple version (`simple.go`) demonstrates:
1. **bufio.Reader** for reading user input
2. **Direct function calls** instead of async messages
3. **Simple error handling** with early returns
4. **Linear flow**: input → check → build → done

```go
reader := bufio.NewReader(os.Stdin)
input, err := reader.ReadString('\n')
targetDir := strings.TrimSpace(input)

if err := buildStructure(targetDir); err != nil {
    fmt.Printf("Error: %v\n", err)
    os.Exit(1)
}
```

## Key Bubble Tea Concepts

### 1. Model (State)
```go
type model struct {
    step     int
    message  string
    err      error
    quitting bool
}
```
The model holds all application state.

### 2. Messages (Events)
```go
type buildCompleteMsg struct{ err error }
type submoduleCheckMsg struct{ exists bool }
```
Messages represent events that trigger state changes.

### 3. Core Methods

**Init()** - Returns the initial command to run:
```go
func (m model) Init() tea.Cmd {
    return checkSubmodule
}
```

**Update()** - Handles messages and updates state:
```go
func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
    switch msg := msg.(type) {
    case tea.KeyMsg:
        // Handle keyboard input
    case buildCompleteMsg:
        // Handle async operation completion
    }
    return m, nil
}
```

**View()** - Renders the UI:
```go
func (m model) View() string {
    return "RPi Zero Buildroot Structure Builder\n\n" + m.message
}
```

### 4. Commands (Async Operations)

Commands are functions that return `tea.Msg`:
```go
func checkSubmodule() tea.Msg {
    // Do work...
    return submoduleCheckMsg{exists: true}
}
```

## Build and Run

### Bubble Tea Version
```bash
go build -o builder main.go
./builder
# Enter directory path when prompted
```

### Simple Version
```bash
go build -o simple simple.go
./simple
# Enter directory path when prompted

# Or pipe input:
echo "my-target-dir" | ./simple
```

## Pattern Summary

1. **Model**: Holds state
2. **Message**: Represents events
3. **Init**: Returns initial command
4. **Update**: Processes messages, returns new model + command
5. **View**: Renders current state as string
6. **Commands**: Async operations that return messages

This pattern (MVU - Model-View-Update) is similar to Elm and Redux.
