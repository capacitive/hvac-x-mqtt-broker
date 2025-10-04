package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type Device struct {
	Name      string // e.g., sdb
	Path      string // /dev/sdb
	Vendor    string
	Model     string
	SizeB     uint64
	USB       bool
	Removable bool
}

func humanBytes(n uint64) string {
	const (
		KB = 1024
		MB = 1024 * KB
		GB = 1024 * MB
		TB = 1024 * GB
	)
	switch {
	case n >= TB:
		return fmt.Sprintf("%.1f TB", float64(n)/float64(TB))
	case n >= GB:
		return fmt.Sprintf("%.1f GB", float64(n)/float64(GB))
	case n >= MB:
		return fmt.Sprintf("%.1f MB", float64(n)/float64(MB))
	case n >= KB:
		return fmt.Sprintf("%.1f KB", float64(n)/float64(KB))
	default:
		return fmt.Sprintf("%d B", n)
	}
}

func readFirstLine(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

func isUSB(sysPath string) bool {
	// Heuristic: if the device syspath contains "/usb", consider it USB-attached
	// e.g., /sys/block/sdb/device/..../usbX
	p := filepath.Join(sysPath, "device")
	for i := 0; i < 6; i++ { // walk up a few parents
		if strings.Contains(p, "/usb") {
			return true
		}
		pp := filepath.Join(p, "..")
		abs, err := filepath.EvalSymlinks(pp)
		if err != nil {
			break
		}
		p = abs
	}
	return false
}

func listBlockDevices() ([]Device, error) {
	sysBlock := "/sys/block"
	entries, err := os.ReadDir(sysBlock)
	if err != nil {
		return nil, err
	}
	var devs []Device
	for _, e := range entries {
		name := e.Name()
		// consider sdX only; skip loop, sr, nvme, dm-*
		if len(name) < 3 || !strings.HasPrefix(name, "sd") {
			continue
		}
		sysPath := filepath.Join(sysBlock, name)
		// skip partitions (those exist under /sys/block/sdX/sdX1, but e here are top-level)
		rem, err := readFirstLine(filepath.Join(sysPath, "removable"))
		if err != nil || strings.TrimSpace(rem) != "1" {
			continue
		}
		usb := isUSB(sysPath)
		if !usb {
			// likely internal SATA/SCSI removable (rare) — skip
			continue
		}
		sectorsStr, err := readFirstLine(filepath.Join(sysPath, "size"))
		if err != nil {
			sectorsStr = "0"
		}
		sectors, _ := strconv.ParseUint(strings.TrimSpace(sectorsStr), 10, 64)
		// sector size is typically 512 bytes
		sizeB := sectors * 512
		vendor, _ := readFirstLine(filepath.Join(sysPath, "device", "vendor"))
		model, _ := readFirstLine(filepath.Join(sysPath, "device", "model"))
		devs = append(devs, Device{
			Name:      name,
			Path:      "/dev/" + name,
			Vendor:    strings.TrimSpace(vendor),
			Model:     strings.TrimSpace(model),
			SizeB:     sizeB,
			USB:       usb,
			Removable: true,
		})
	}
	// sort for stable order
	sort.Slice(devs, func(i, j int) bool { return devs[i].Name < devs[j].Name })
	return devs, nil
}

func render(devs []Device) string {
	var b strings.Builder
	b.WriteString("\x1b[2J\x1b[H")
	b.WriteString("USB removable block devices (SD/microSD readers)\n")
	b.WriteString("Select a device index and press Enter. Press q to quit.\n\n")
	if len(devs) == 0 {
		b.WriteString("(waiting for devices...)\n")
		return b.String()
	}
	for i, d := range devs {
		b.WriteString(fmt.Sprintf("[%d] %-8s  %-18s  %-22s  %s\n",
			i, d.Path, d.Vendor, d.Model, humanBytes(d.SizeB)))
	}
	b.WriteString("\n")
	b.WriteString("Tip: Insert or remove a reader; the list updates automatically.\n")
	return b.String()
}

func equalSets(a, b []Device) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i].Name != b[i].Name || a[i].SizeB != b[i].SizeB || a[i].Vendor != b[i].Vendor || a[i].Model != b[i].Model {
			return false
		}
	}
	return true
}

func readLineNonEmpty(r *bufio.Reader) (string, error) {
	for {
		line, err := r.ReadString('\n')
		if err != nil {
			return "", err
		}
		line = strings.TrimSpace(line)
		if line != "" {
			return line, nil
		}
	}
}

func main() {
	// UI goes to stderr; final selection (device path) prints to stdout only
	out := bufio.NewWriter(os.Stderr)
	defer out.Flush()

	var last []Device
	// initial render
	devs, _ := listBlockDevices()
	fmt.Fprint(out, render(devs))
	last = devs

	// background updater
	updated := make(chan []Device, 1)
	stop := make(chan struct{})
	go func() {
		for {
			select {
			case <-stop:
				return
			default:
			}
			time.Sleep(700 * time.Millisecond)
			d, err := listBlockDevices()
			if err == nil && !equalSets(d, last) {
				updated <- d
				last = d
			}
		}
	}()

	// input reader
	inputCh := make(chan string, 1)
	go func() {
		scanner := bufio.NewScanner(os.Stdin)
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if line != "" {
				inputCh <- line
			}
		}
		close(inputCh)
	}()

	for {
		select {
		case d := <-updated:
			fmt.Fprint(out, render(d))
		case line, ok := <-inputCh:
			if !ok {
				close(stop)
				return
			}
			if line == "q" || line == "Q" {
				close(stop)
				return
			}
			idx, convErr := strconv.Atoi(line)
			if convErr != nil {
				fmt.Fprintln(out, "Please enter a numeric index or 'q' to quit.")
				continue
			}
			curr, _ := listBlockDevices()
			if idx < 0 || idx >= len(curr) {
				fmt.Fprintln(out, "Index out of range. Try again.")
				continue
			}
			choice := curr[idx]
			fmt.Fprintf(out, "\nYou selected %s (%s %s, %s).\n", choice.Path, choice.Vendor, choice.Model, humanBytes(choice.SizeB))
			fmt.Fprint(out, "WARNING: This will erase all data on the device. Type YES to confirm: ")
			_ = out.Flush()
			confScanner := bufio.NewScanner(os.Stdin)
			if !confScanner.Scan() {
				continue
			}
			confirm := strings.TrimSpace(confScanner.Text())
			if confirm != "YES" {
				fmt.Fprintln(out, "Aborted selection.")
				continue
			}
			fmt.Println(choice.Path)
			close(stop)
			return
		default:
			time.Sleep(100 * time.Millisecond)
		}
	}
}
