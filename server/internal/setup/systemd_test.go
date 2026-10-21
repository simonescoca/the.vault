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

	if err := uninstallSystemdUnit(cfg.DataDir); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(unitPath()); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("unit still there: %v", err)
	}
	if got := calls(); got[3] != "--user disable --now "+UnitName {
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
	// email, provider (iCloud), sender, backup dir (default)
	w, out, installed := newTestWizard(t, "me@icloud.com\n\n\n\n", nil)
	w.OS = "linux"
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
	if *installed != 1 || atBoot != 1 {
		t.Errorf("installed=%d atBoot=%d", *installed, atBoot)
	}
	for _, mac := range []string{"macOS", "Mac mini", "Time Machine"} {
		if strings.Contains(out.String(), mac) {
			t.Errorf("%q in the Linux setup:\n%s", mac, out)
		}
	}
	if !strings.Contains(out.String(), "nuova sessione SSH") {
		t.Errorf("no hint for the terminal:\n%s", out)
	}
}

func TestWizardOnLinuxAcceptsAnyBackupFolderAndWarnsWithoutLinger(t *testing.T) {
	// A folder that macOS would refuse is fine on Linux.
	w, out, _ := newTestWizard(t, "me@icloud.com\n\n\n~/Documents/backup\n", nil)
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
