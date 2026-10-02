package setup

import (
	"bytes"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/simonescoca/the.vault/server/internal/config"
)

// Label is the launchd service name.
const Label = "it.simonescoca.thevault.server"

// LogPath is where the background service writes its log.
func LogPath(dataDir string) string { return filepath.Join(dataDir, "server.log") }

// BinPath is where setup copies the server program, so the service does not depend on the download folder.
func BinPath(dataDir string) string { return filepath.Join(dataDir, "bin", "thevault-server") }

func plistPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Library", "LaunchAgents", Label+".plist")
}

func xmlEscape(s string) string {
	var b bytes.Buffer
	xml.EscapeText(&b, []byte(s))
	return b.String()
}

// Plist renders the LaunchAgent definition.
func Plist(bin, dataDir string) string {
	return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>` + Label + `</string>
  <key>ProgramArguments</key>
  <array>
    <string>` + xmlEscape(bin) + `</string>
    <string>serve</string>
    <string>--data</string>
    <string>` + xmlEscape(dataDir) + `</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>` + xmlEscape(LogPath(dataDir)) + `</string>
  <key>StandardErrorPath</key>
  <string>` + xmlEscape(LogPath(dataDir)) + `</string>
</dict>
</plist>
`
}

func copyExecutable(dst string) error {
	src, err := os.Executable()
	if err != nil {
		return err
	}
	if src, err = filepath.EvalSymlinks(src); err != nil {
		return err
	}
	if abs, _ := filepath.Abs(dst); abs == src {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o700); err != nil {
		return err
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp := dst + ".new"
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o700)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	if err := out.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, dst)
}

func launchctl(args ...string) (string, error) {
	out, err := exec.Command("launchctl", args...).CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

func guiDomain() string { return "gui/" + strconv.Itoa(os.Getuid()) }

// InstallService copies the program into the data folder and (re)starts it as a LaunchAgent.
func InstallService(cfg *config.Config) error {
	if runtime.GOOS != "darwin" {
		return errors.New("l'avvio automatico è disponibile solo su macOS: avvia a mano con 'thevault-server serve'")
	}
	bin := BinPath(cfg.DataDir)
	if err := copyExecutable(bin); err != nil {
		return fmt.Errorf("copia del programma: %w", err)
	}
	p := plistPath()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(p, []byte(Plist(bin, cfg.DataDir)), 0o644); err != nil {
		return err
	}
	_, _ = launchctl("bootout", guiDomain()+"/"+Label) // not loaded yet: fine
	if out, err := launchctl("bootstrap", guiDomain(), p); err != nil {
		return fmt.Errorf("launchctl bootstrap: %v: %s", err, out)
	}
	_, _ = launchctl("enable", guiDomain()+"/"+Label)
	_, _ = launchctl("kickstart", "-k", guiDomain()+"/"+Label)
	return nil
}

// Uninstall removes the background service. Data and configuration are kept.
func Uninstall(dataDir string) error {
	if runtime.GOOS != "darwin" {
		return errors.New("disponibile solo su macOS")
	}
	_, _ = launchctl("bootout", guiDomain()+"/"+Label)
	if err := os.Remove(plistPath()); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	fmt.Println("Avvio automatico rimosso. I dati restano in:", dataDir)
	return nil
}

func localURL(cfg *config.Config) string {
	host := cfg.Listen
	if strings.HasPrefix(host, ":") {
		host = "127.0.0.1" + host
	}
	return "http://" + host
}

// WaitHealthy waits up to 20 seconds for the local server to answer.
func WaitHealthy(cfg *config.Config) error {
	deadline := time.Now().Add(20 * time.Second)
	var last error
	for time.Now().Before(deadline) {
		if err := checkHealth(localURL(cfg)); err == nil {
			return nil
		} else {
			last = err
		}
		time.Sleep(500 * time.Millisecond)
	}
	return last
}

func checkHealth(base string) error {
	c := &http.Client{Timeout: 5 * time.Second}
	resp, err := c.Get(strings.TrimRight(base, "/") + "/v1/health")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode != 200 || !strings.Contains(string(body), `"thevault"`) {
		return fmt.Errorf("risposta inattesa (%d)", resp.StatusCode)
	}
	return nil
}
