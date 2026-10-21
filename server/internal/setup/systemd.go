package setup

// The Linux background service (for example on an NVIDIA Jetson): a systemd user service. Like the macOS
// LaunchAgent it runs with the user's account, so installing and upgrading need no administrator password.
// Only "linger" needs one, once, during the setup: with it the user's services start at boot, without anyone
// logging in, and keep running when the SSH session ends.

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/simonescoca/the.vault/server/internal/config"
)

// UnitName is the systemd user service name.
const UnitName = "thevault-server.service"

const notRootLinux = "esegui il comando con il tuo utente, senza sudo: il server gira con il tuo account"

func unitPath() string {
	dir, err := os.UserConfigDir() // $XDG_CONFIG_HOME, or ~/.config
	if err != nil {
		home, _ := os.UserHomeDir()
		dir = filepath.Join(home, ".config")
	}
	return filepath.Join(dir, "systemd", "user", UnitName)
}

// execArg quotes one argument of ExecStart= (systemd.service(5)): backslashes and quotes are escaped,
// "%" would start a specifier and "$" an environment variable.
func execArg(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `"`, `\"`, "%", "%%", "$", "$$")
	return `"` + r.Replace(s) + `"`
}

// Unit renders the systemd user service definition.
func Unit(bin, dataDir string) string {
	logFile := strings.ReplaceAll(LogPath(dataDir), "%", "%%")
	return `[Unit]
Description=The Vault server
# Never stop restarting it (like KeepAlive on macOS).
StartLimitIntervalSec=0

[Service]
ExecStart=` + execArg(bin) + ` serve --data ` + execArg(dataDir) + `
Restart=always
RestartSec=10
UMask=0077
NoNewPrivileges=yes
StandardOutput=append:` + logFile + `
StandardError=append:` + logFile + `

[Install]
WantedBy=default.target
`
}

func currentUser() string {
	if u, err := user.Current(); err == nil && u.Username != "" {
		return u.Username
	}
	return os.Getenv("USER")
}

// lingerDir is where systemd marks the users whose services start at boot (loginctl enable-linger).
var lingerDir = "/var/lib/systemd/linger"

func lingering(name string) bool {
	_, err := os.Stat(filepath.Join(lingerDir, name))
	return err == nil
}

// systemctlUser runs 'systemctl --user'. Without XDG_RUNTIME_DIR (for example after 'su') systemctl does not
// find the user's service manager, which with linger runs anyway in /run/user/<uid>.
func systemctlUser(args ...string) (string, error) {
	cmd := exec.Command("systemctl", append([]string{"--user"}, args...)...)
	cmd.Env = os.Environ()
	if os.Getenv("XDG_RUNTIME_DIR") == "" {
		if dir := "/run/user/" + strconv.Itoa(os.Getuid()); dirExists(dir) {
			cmd.Env = append(cmd.Env, "XDG_RUNTIME_DIR="+dir)
		}
	}
	out, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

func dirExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

// noUserManager reports whether systemctl failed because the user's service manager is not reachable.
func noUserManager(out string) bool {
	// "Failed to connect to bus: …" or, in newer versions, "Failed to connect to user scope bus …"
	return strings.Contains(out, "Failed to connect") || strings.Contains(out, "XDG_RUNTIME_DIR")
}

func systemctlError(args []string, out string, err error) error {
	if noUserManager(out) {
		return fmt.Errorf("non trovo i servizi del tuo utente (systemd --user): accedi direttamente come %s, "+
			"con SSH o dal desktop (non con 'sudo' o 'su'), e riprova", currentUser())
	}
	return fmt.Errorf("systemctl --user %s: %v: %s", strings.Join(args, " "), err, out)
}

func installSystemdUnit(cfg *config.Config) error {
	if os.Geteuid() == 0 {
		return errors.New(notRootLinux)
	}
	if _, err := exec.LookPath("systemctl"); err != nil {
		return errors.New("systemd non trovato: avvia a mano con 'thevault-server serve'")
	}
	dataDir, err := filepath.Abs(cfg.DataDir)
	if err != nil {
		return err
	}
	bin := BinPath(dataDir)
	if err := copyExecutable(bin); err != nil {
		return fmt.Errorf("copia del programma: %w", err)
	}
	p := unitPath()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(p, []byte(Unit(bin, dataDir)), 0o644); err != nil {
		return err
	}
	for _, args := range [][]string{{"daemon-reload"}, {"enable", UnitName}, {"restart", UnitName}} {
		if out, err := systemctlUser(args...); err != nil {
			return systemctlError(args, out, err)
		}
	}
	return nil
}

func uninstallSystemdUnit(dataDir string) error {
	_, _ = systemctlUser("disable", "--now", UnitName)
	if err := os.Remove(unitPath()); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	_, _ = systemctlUser("daemon-reload")
	fmt.Println("Avvio automatico rimosso. I dati restano in:", dataDir)
	return nil
}

// enableLinger makes the service start at boot and survive the end of the session (without it the server
// would stop as soon as the SSH session closes). It asks once for the administrator password (sudo).
func enableLinger(w *Wizard) error {
	name := currentUser()
	if lingering(name) {
		w.say("     ✓ Parte da solo a ogni accensione, anche senza fare l'accesso.")
		return nil
	}
	w.say("     Perché parta da solo a ogni accensione e resti attivo quando chiudi la sessione serve un permesso")
	w.say("     di amministratore (una volta sola): se richiesta, inserisci la password di %s.", name)
	cmd := exec.Command("sudo", "loginctl", "enable-linger", name)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, w.Out, w.Out
	if err := cmd.Run(); err != nil || !lingering(name) {
		return fmt.Errorf("permesso non concesso: il server si fermerà quando chiudi la sessione e non ripartirà "+
			"dopo un riavvio. Per sistemare: sudo loginctl enable-linger %s", name)
	}
	w.say("     ✓ Partirà da solo a ogni accensione, anche senza fare l'accesso.")
	return nil
}

// systemdSummary describes the automatic start for 'status' on Linux.
func systemdSummary() string {
	name := currentUser()
	state, _ := systemctlUser("is-enabled", UnitName)
	switch {
	case noUserManager(state):
		return "? non verificabile da questa sessione: accedi come " + name + " con SSH o dal desktop"
	case state != "enabled":
		return "✗ non installato: esegui 'thevault-server setup'"
	case !lingering(name):
		return "⚠ si ferma quando chiudi la sessione e non riparte dopo un riavvio.\n" +
			"                    Per sistemare: sudo loginctl enable-linger " + name
	}
	return "✓ parte da solo a ogni accensione"
}
