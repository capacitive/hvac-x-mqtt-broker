# Bubble Tea vs Simple: Side-by-Side Comparison

## When to Use Each

### Simple Version (`simple.go`)
Use when:
- Building CLI tools that need to be scriptable
- Want minimal dependencies
- Need to pipe input or run in automation
- Prefer straightforward, linear code flow
- Interview question asks for "console app"

### Bubble Tea Version (`main.go`)
Use when:
- Building interactive TUI applications
- Want real-time feedback and better UX
- Need to handle complex user interactions
- Want to showcase modern Go TUI skills
- Interview question asks for "interactive app"

## Code Complexity

| Aspect | Simple | Bubble Tea |
|--------|--------|------------|
| Lines of Code | ~110 | ~190 |
| Concepts | 3-4 | 6-8 |
| Dependencies | stdlib + 2 | stdlib + 3 |
| Learning Curve | Low | Medium |
| Testability | High | Medium |

## Input Handling

### Simple Version
```go
reader := bufio.NewReader(os.Stdin)
input, err := reader.ReadString('\n')
targetDir := strings.TrimSpace(input)
```
- Blocks until Enter is pressed
- Can be piped: `echo "path" | ./simple`
- Standard Go idioms

### Bubble Tea Version
```go
case "enter":
    m.targetDir = m.input
    return m, checkSubmoduleCmd
case "backspace":
    m.input = m.input[:len(m.input)-1]
default:
    m.input += msg.String()
```
- Character-by-character input
- Real-time visual feedback
- Cannot easily pipe input

## Error Handling

### Simple Version
```go
if err := buildStructure(targetDir); err != nil {
    fmt.Printf("✗ Error: %v\n", err)
    os.Exit(1)
}
```
- Direct, immediate
- Exit on error

### Bubble Tea Version
```go
case buildCompleteMsg:
    if msg.err != nil {
        m.message = fmt.Sprintf("✗ Error: %v", msg.err)
    }
    return m, tea.Quit
```
- Message-based
- Update UI, then quit

## Flow Comparison

### Simple: Linear Flow
```
main() → read input → check existing → build structure → exit
```

### Bubble Tea: Event-Driven Flow
```
Init() → Update(KeyMsg) → Update(checkMsg) → Update(buildMsg) → Quit
   ↓         ↓                    ↓                  ↓
  nil    checkCmd           buildCmd            tea.Quit
```

## Key Takeaway

**Simple** = Scriptable, straightforward, great for automation and interviews  
**Bubble Tea** = Interactive, polished, great for end-user tools and showcasing skills

Both accomplish the same task. Choose based on requirements and context.
