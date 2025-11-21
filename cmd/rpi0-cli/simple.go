package cmd

import (
	"bufio"
	"fmt"
	cmd "hvac-x-hub-min/cmd/filesystem"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/mcuadros/go-defaults"
)

func main() {
	fmt.Println("RPi Zero Buildroot Structure Builder")
	fmt.Println()

	// Get target directory from user
	reader := bufio.NewReader(os.Stdin)
	fmt.Print("Enter target directory path: ")
	input, err := reader.ReadString('\n')
	if err != nil {
		fmt.Printf("Error reading input: %v\n", err)
		os.Exit(1)
	}

	targetDir := strings.TrimSpace(input)
	if targetDir == "" {
		fmt.Println("Error: directory path cannot be empty")
		os.Exit(1)
	}

	// Check if structure already exists
	target, _ := filepath.Abs(targetDir)
	if _, err := os.Stat(filepath.Join(target, "buildroot")); err == nil {
		fmt.Printf("✓ Directory structure already exists at %s\n", target)
		return
	}

	// Create directory structure
	fmt.Println("Creating directory structure...")
	if err := buildStructure(targetDir); err != nil {
		fmt.Printf("✗ Error: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("✓ Build complete at %s!\n", target)
}

func buildStructure(targetDir string) error {
	target, _ := filepath.Abs(targetDir)
	repoRoot, _ := filepath.Abs(filepath.Join("..", ".."))

	// Create target directory
	if err := os.MkdirAll(target, 0755); err != nil {
		return err
	}

	// Get the filesystem structure
	fs := cmd.NewOutTreeFS()
	defaults.SetDefaults(fs)

	// Create root files
	rootFiles := []string{fs.Configin, fs.ExternalDesc, fs.ExternalMk}
	for _, filename := range rootFiles {
		path := filepath.Join(target, filename)
		if err := os.WriteFile(path, []byte("# "+filename+"\n"), 0644); err != nil {
			return err
		}
	}

	// Create configs and package directories
	for _, dir := range []string{fs.Configs, fs.Package} {
		if err := os.MkdirAll(filepath.Join(target, dir), 0755); err != nil {
			return err
		}
	}

	// Create board directory structure
	boardPath := filepath.Join(target, fs.BoardDir.Name)

	// Create board/hvacx subdirectory with patches and rootfs_overlay
	hvacxPath := filepath.Join(boardPath, fs.ProjectDir.Name)
	for _, subdir := range []string{fs.ProjectDir.Patches, fs.ProjectDir.RootFsOverlay} {
		if err := os.MkdirAll(filepath.Join(hvacxPath, subdir), 0755); err != nil {
			return err
		}
	}

	// Create board/common subdirectory with patches and rootfs_overlay
	commonPath := filepath.Join(boardPath, fs.CommmonDir.Name)
	for _, subdir := range []string{fs.CommmonDir.Patches, fs.CommmonDir.RootFsOverlay} {
		if err := os.MkdirAll(filepath.Join(commonPath, subdir), 0755); err != nil {
			return err
		}
	}

	// Add buildroot as git submodule
	relPath, _ := filepath.Rel(repoRoot, filepath.Join(target, "buildroot"))
	cmd := exec.Command("git", "submodule", "add",
		"https://gitlab.com/buildroot.org/buildroot.git",
		relPath)
	cmd.Dir = repoRoot

	if output, err := cmd.CombinedOutput(); err != nil {
		// Check if submodule already exists
		if !strings.Contains(string(output), "already exists") {
			return fmt.Errorf("git submodule add failed: %v\n%s", err, output)
		}
	}

	return nil
}
