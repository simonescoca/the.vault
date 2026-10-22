package setup

import (
	"bytes"
	"context"
	"encoding/json"
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

	"github.com/simonescoca/the.vault/server/internal/backup"
	"github.com/simonescoca/the.vault/server/internal/config"
	"github.com/simonescoca/the.vault/server/internal/store"
)

// The macOS background service: a LaunchAgent, started when the user logs in and kept alive by launchd.

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

// InstallService copies the program into the data folder and (re)starts it as a background service:
// a LaunchAgent on macOS, a systemd user service on Linux (systemd.go).
func InstallService(cfg *config.Config) error {
	switch runtime.GOOS {
	case "darwin":
		return installLaunchAgent(cfg)
	case "linux":
		return installSystemdUnit(cfg)
	}
	return errors.New("l'avvio automatico è disponibile solo su macOS e Linux: avvia a mano con 'thevault-server serve'")
}

// Uninstall removes the background service. Data and configuration are kept.
func Uninstall(dataDir string) error {
	switch runtime.GOOS {
	case "darwin":
		return uninstallLaunchAgent(dataDir)
	case "linux":
		return uninstallSystemdUnit(dataDir)
	}
	return errors.New("disponibile solo su macOS e Linux")
}

func installLaunchAgent(cfg *config.Config) error {
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

func uninstallLaunchAgent(dataDir string) error {
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

// upgradeWait is how long Upgrade waits for the new version to answer.
var upgradeWait = 30 * time.Second

// Upgrade replaces the installed program with this one and restarts the service; data and settings stay.
// It returns once the new version answers. If it does not, the previous program is put back and restarted.
func Upgrade(cfg *config.Config, version string) error {
	dataDir, err := filepath.Abs(cfg.DataDir)
	if err != nil {
		return err
	}
	bin := BinPath(dataDir)
	prev := bin + ".prev"
	before := schemaVersion(dataDir)
	kept := keepPrevious(bin, prev)
	err = InstallService(cfg)
	if err == nil {
		err = waitVersion(cfg, func(v string) bool { return v == version }, upgradeWait)
	}
	if err == nil || !kept {
		return err
	}
	if schemaVersion(dataDir) > max(before, 0) {
		// The new version already updated the database: the previous one could not use it.
		return fmt.Errorf("%w. La nuova versione ha già aggiornato il database, quindi resta installata: guarda il "+
			"registro (%s). Il backup fatto prima dell'aggiornamento è in %s", err, LogPath(cfg.DataDir), backup.Dir(cfg))
	}
	if rerr := os.Rename(prev, bin); rerr != nil {
		return fmt.Errorf("%w. Non sono riuscito a rimettere la versione precedente: %v", err, rerr)
	}
	restartService()
	if werr := waitVersion(cfg, func(string) bool { return true }, upgradeWait); werr != nil {
		return fmt.Errorf("%w. Ho rimesso la versione precedente, ma non risponde (registro: %s)", err, LogPath(cfg.DataDir))
	}
	v, _ := runningVersion(localURL(cfg))
	return fmt.Errorf("%w. Ho rimesso la versione precedente (%s), che è di nuovo attiva", err, v)
}

// schemaVersion returns the schema of the server database (-1 if there is none or it cannot be read).
func schemaVersion(dataDir string) int {
	st, err := store.OpenNoMigrate(filepath.Join(dataDir, "thevault.db"))
	if err != nil {
		return -1
	}
	defer st.Close()
	v, err := st.SchemaVersion(context.Background())
	if err != nil {
		return -1
	}
	return v
}

// keepPrevious keeps the installed program as prev, to put it back if the new one does not start.
func keepPrevious(bin, prev string) bool {
	self, err := os.Executable()
	if err == nil {
		self, err = filepath.EvalSymlinks(self)
	}
	if err != nil || self == bin {
		return false // upgrading the installed program in place: nothing else to keep
	}
	if _, err := os.Stat(bin); err != nil {
		return false
	}
	_ = os.Remove(prev)
	// A hard link keeps the old file when the new program is renamed over bin.
	return os.Link(bin, prev) == nil
}

// restartService restarts the background service (with whatever program is installed).
func restartService() {
	switch runtime.GOOS {
	case "darwin":
		target := guiDomain() + "/" + Label
		if _, err := launchctl("kickstart", "-k", target); err != nil {
			// Not loaded (e.g. the new version's bootstrap failed): load it again, RunAtLoad starts it.
			_, _ = launchctl("bootstrap", guiDomain(), plistPath())
			_, _ = launchctl("enable", target)
		}
	case "linux":
		_, _ = systemctlUser("restart", UnitName)
	}
}

// waitVersion waits until the local server answers with a version accepted by ok.
func waitVersion(cfg *config.Config, ok func(string) bool, wait time.Duration) error {
	deadline := time.Now().Add(wait)
	for {
		running, err := runningVersion(localURL(cfg))
		if err == nil && ok(running) {
			return nil
		}
		if time.Now().After(deadline) {
			if err != nil {
				return fmt.Errorf("il server non risponde dopo l'aggiornamento: %w (registro: %s)", err, LogPath(cfg.DataDir))
			}
			return fmt.Errorf("risponde ancora la versione %s (registro: %s)", running, LogPath(cfg.DataDir))
		}
		time.Sleep(500 * time.Millisecond)
	}
}

// runningVersion asks the server at base which version it is.
func runningVersion(base string) (string, error) {
	c := &http.Client{Timeout: 5 * time.Second}
	resp, err := c.Get(strings.TrimRight(base, "/") + "/v1/health")
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var h struct {
		Service string `json:"service"`
		Version string `json:"version"`
	}
	if resp.StatusCode != 200 || json.NewDecoder(io.LimitReader(resp.Body, 4096)).Decode(&h) != nil || h.Service != "thevault" {
		return "", fmt.Errorf("risposta inattesa (%d)", resp.StatusCode)
	}
	return h.Version, nil
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
