package setup

import (
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/simonescoca/the.vault/server/internal/config"
)

func TestUnitQuotesPaths(t *testing.T) {
	u := Unit(`/home/a b/100%$x"y\z/thevault-server`, "/home/a b/.thevault-server")
	for _, want := range []string{
		`ExecStart="/home/a b/100%%$$x\"y\\z/thevault-server" serve --data "/home/a b/.thevault-server"`,
		"Restart=always",
		"StartLimitIntervalSec=0",
		"StandardOutput=append:/home/a b/.thevault-server/server.log",
		"StandardError=append:/home/a b/.thevault-server/server.log",
		"WantedBy=default.target",
	} {
		if !strings.Contains(u, want) {
			t.Errorf("missing %q in:\n%s", want, u)
		}
	}
	if u := Unit("/bin/x", "/data/50%"); !strings.Contains(u, "append:/data/50%%/server.log") {
		t.Errorf("log path not escaped:\n%s", u)
	}
}

// fakeSystemctl puts a 'systemctl' in the PATH that records its arguments (one call per line) and,
// with fail set, answers like systemctl without a user service manager.
func fakeSystemctl(t *testing.T, fail bool) (calls func() []string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("needs a shell")
	}
	dir := t.TempDir()
	log := filepath.Join(dir, "calls")
	script := "#!/bin/sh\necho \"$*\" >> \"$FAKE_SYSTEMCTL_LOG\"\n"
	if fail {
		script += "echo 'Failed to connect to bus: No medium found' >&2\nexit 1\n"
	} else {
		script += "case \"$*\" in *is-enabled*) echo enabled ;; esac\n"
	}
	if err := os.WriteFile(filepath.Join(dir, "systemctl"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("FAKE_SYSTEMCTL_LOG", log)
	return func() []string {
		b, _ := os.ReadFile(log)
		return strings.Split(strings.TrimSpace(string(b)), "\n")
	}
}

func userDirs(t *testing.T) (home string) {
	t.Helper()
	if os.Geteuid() == 0 {
		t.Skip("the Linux service refuses root")
	}
	home = t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	return home
}

func TestInstallAndUninstallSystemdUnit(t *testing.T) {
	home := userDirs(t)
	calls := fakeSystemctl(t, false)
	cfg := config.Default(filepath.Join(home, ".thevault-server"))
	if err := installSystemdUnit(cfg); err != nil {
		t.Fatal(err)
	}
	if st, err := os.Stat(BinPath(cfg.DataDir)); err != nil || st.Mode()&0o100 == 0 {
		t.Fatalf("program not copied: %v", err)
	}
	unit, err := os.ReadFile(unitPath())
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(unitPath(), home) || !strings.Contains(string(unit), `ExecStart="`+BinPath(cfg.DataDir)+`" serve --data "`+cfg.DataDir+`"`) {
		t.Errorf("unit:\n%s", unit)
	}
	want := []string{"--user daemon-reload", "--user enable " + UnitName, "--user restart " + UnitName}
	if got := calls(); strings.Join(got, "|") != strings.Join(want, "|") {
		t.Errorf("systemctl calls: %q", got)
	}
	// New terminals find the command, also on a desktop where ~/.local/bin did not exist at login.
	if target, err := os.Readlink(filepath.Join(home, ".local", "bin", "thevault-server")); err != nil || target != BinPath(cfg.DataDir) {
		t.Errorf("command link: %q %v", target, err)
	}
	if err := installSystemdUnit(cfg); err != nil { // upgrade: same link, no second PATH line
		t.Fatal(err)
	}
	rc, _ := os.ReadFile(filepath.Join(home, ".bashrc"))
	if strings.Count(string(rc), pathMarker) != 1 || !strings.Contains(string(rc), pathLine) {
		t.Errorf(".bashrc:\n%s", rc)
	}
	calls() // the second install's calls are not checked

	if err := uninstallSystemdUnit(cfg.DataDir); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(unitPath()); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("unit still there: %v", err)
	}
	if got := calls(); got[6] != "--user disable --now "+UnitName {
		t.Errorf("systemctl calls: %q", got)
	}
}

func TestSystemdUnitWithoutUserManager(t *testing.T) {
	home := userDirs(t)
	fakeSystemctl(t, true)
	err := installSystemdUnit(config.Default(filepath.Join(home, ".thevault-server")))
	if err == nil || !strings.Contains(err.Error(), "non con 'sudo' o 'su'") {
		t.Fatalf("error: %v", err)
	}
	if s := systemdSummary(); !strings.HasPrefix(s, "? non verificabile") {
		t.Errorf("summary: %s", s)
	}
}

func TestSystemdSummary(t *testing.T) {
	userDirs(t)
	fakeSystemctl(t, false)
	lingerDir = t.TempDir()
	t.Cleanup(func() { lingerDir = "/var/lib/systemd/linger" })
	if s := systemdSummary(); !strings.HasPrefix(s, "⚠") || !strings.Contains(s, "sudo loginctl enable-linger "+currentUser()) {
		t.Errorf("without linger: %s", s)
	}
	if err := os.WriteFile(filepath.Join(lingerDir, currentUser()), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if s := systemdSummary(); !strings.HasPrefix(s, "✓") {
		t.Errorf("with linger: %s", s)
	}
}

func TestUnitPathFollowsXDG(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("XDG_CONFIG_HOME is a Linux convention")
	}
	t.Setenv("XDG_CONFIG_HOME", "/tmp/xdg")
	if p := unitPath(); p != "/tmp/xdg/systemd/user/"+UnitName {
		t.Errorf("unit path: %s", p)
	}
}

func TestWizardOnLinux(t *testing.T) {
	// email, provider (default on Linux: Gmail), a dedicated sender (no default), backup dir (default)
	w, out, installed := newTestWizard(t, "me@icloud.com\n\ncodici.thevault@gmail.com\n\n", nil)
	w.OS = "linux"
	w.ReadPassword = func(string) (string, error) { return " abcd efgh ijkl mnop ", nil } // as Google shows it
	atBoot := 0
	w.StartAtBoot = func(w *Wizard) error { atBoot++; return nil }
	if err := w.Run(); err != nil {
		t.Fatalf("wizard: %v\n%s", err, out)
	}
	cfg, err := config.Load(w.DataDir)
	if err != nil {
		t.Fatal(err)
	}
	home, _ := os.UserHomeDir()
	if cfg.Backup.Dir != filepath.Join(home, "thevault-backup") {
		t.Errorf("backup folder: %s", cfg.Backup.Dir)
	}
	if cfg.SMTP.Host != "smtp.gmail.com" || cfg.SMTP.Username != "codici.thevault@gmail.com" ||
		cfg.SMTP.Password != "abcdefghijklmnop" || cfg.AllowedEmails[0] != "me@icloud.com" {
		t.Errorf("smtp: %+v", cfg.SMTP)
	}
	if *installed != 1 || atBoot != 1 {
		t.Errorf("installed=%d atBoot=%d", *installed, atBoot)
	}
	for _, mac := range []string{"macOS", "Mac mini", "Time Machine"} {
		if strings.Contains(out.String(), mac) {
			t.Errorf("%q in the Linux setup:\n%s", mac, out)
		}
	}
	if !strings.Contains(out.String(), "nuova sessione SSH") || !strings.Contains(out.String(), "casella creata apposta") {
		t.Errorf("missing hints:\n%s", out)
	}
}

func TestWizardOnLinuxWarnsAboutTheMainMailbox(t *testing.T) {
	// email, iCloud, sender = the main email → warning, "no", a dedicated one, backup dir
	w, out, _ := newTestWizard(t, "me@icloud.com\n1\nme@icloud.com\n\nthevault.codici@icloud.com\n\n", nil)
	w.OS = "linux"
	w.StartAtBoot = func(w *Wizard) error { return nil }
	if err := w.Run(); err != nil {
		t.Fatalf("wizard: %v\n%s", err, out)
	}
	cfg, _ := config.Load(w.DataDir)
	if cfg.SMTP.Username != "thevault.codici@icloud.com" || !strings.Contains(out.String(), "È la tua email principale") {
		t.Errorf("sender %s:\n%s", cfg.SMTP.Username, out)
	}
	// Choosing it anyway is allowed, and not asked again the next time.
	w2, out2, _ := newTestWizard(t, "\n\nme@icloud.com\ns\n\n", nil)
	w2.OS, w2.DataDir = "linux", w.DataDir
	w2.StartAtBoot = func(w *Wizard) error { return nil }
	if err := w2.Run(); err != nil {
		t.Fatalf("second run: %v\n%s", err, out2)
	}
	w3, out3, _ := newTestWizard(t, "\n\n\n\n", nil)
	w3.OS, w3.DataDir = "linux", w.DataDir
	w3.StartAtBoot = func(w *Wizard) error { return nil }
	if err := w3.Run(); err != nil {
		t.Fatalf("third run: %v\n%s", err, out3)
	}
	if cfg, _ := config.Load(w.DataDir); cfg.SMTP.Username != "me@icloud.com" || strings.Contains(out3.String(), "È la tua email principale") {
		t.Errorf("sender %s:\n%s", cfg.SMTP.Username, out3)
	}
}

func TestWizardOnLinuxAcceptsAnyBackupFolderAndWarnsWithoutLinger(t *testing.T) {
	// A folder that macOS would refuse is fine on Linux.
	w, out, _ := newTestWizard(t, "me@icloud.com\n\ncodici@gmail.com\n~/Documents/backup\n", nil)
	w.OS = "linux"
	w.StartAtBoot = func(w *Wizard) error { return errors.New("permesso non concesso") }
	if err := w.Run(); err != nil {
		t.Fatalf("wizard: %v\n%s", err, out)
	}
	cfg, _ := config.Load(w.DataDir)
	home, _ := os.UserHomeDir()
	if cfg.Backup.Dir != filepath.Join(home, "Documents", "backup") {
		t.Errorf("backup folder: %s", cfg.Backup.Dir)
	}
	if !strings.Contains(out.String(), "⚠ permesso non concesso") || !strings.Contains(out.String(), "Fatto!") {
		t.Errorf("output:\n%s", out)
	}
}
