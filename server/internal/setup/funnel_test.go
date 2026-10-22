package setup

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/simonescoca/the.vault/server/internal/backup"
	"github.com/simonescoca/the.vault/server/internal/config"
	"github.com/simonescoca/the.vault/server/internal/store"
)

// As printed by 'tailscale funnel status --json' after 'tailscale funnel --bg 8743'.
const funnelOn = `{
  "TCP": {"443": {"HTTPS": true}},
  "Web": {"jetson-orin.tail1234.ts.net:443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:8743"}}}},
  "AllowFunnel": {"jetson-orin.tail1234.ts.net:443": true}
}`

func TestFunnelPublishes(t *testing.T) {
	host := "jetson-orin.tail1234.ts.net"
	if !funnelPublishes([]byte(funnelOn), host, "8743") {
		t.Fatal("funnel on, not detected")
	}
	serveOnly := strings.Replace(funnelOn, `"AllowFunnel": {"jetson-orin.tail1234.ts.net:443": true}`, `"AllowFunnel": {}`, 1)
	for name, c := range map[string]struct{ json, host, port string }{
		"nothing published": {`{}`, host, "8743"},
		"tailnet only":      {serveOnly, host, "8743"},
		"another port":      {funnelOn, host, "9000"},
		"another host":      {funnelOn, "mac-mini.tail1234.ts.net", "8743"},
		"not the status":    {`Tailscale is stopped.`, host, "8743"},
	} {
		if funnelPublishes([]byte(c.json), c.host, c.port) {
			t.Errorf("%s: reported as published", name)
		}
	}
}

func TestKeyExpiryNote(t *testing.T) {
	now := time.Date(2026, 10, 22, 12, 0, 0, 0, time.Local)
	var st tsStatus
	json.Unmarshal([]byte(`{"BackendState":"Running","Self":{"DNSName":"jetson-orin.tail1234.ts.net."}}`), &st)
	if n := keyExpiryNote(&st, now, true); n != "" {
		t.Fatalf("no expiry: %q", n)
	}
	json.Unmarshal([]byte(`{"Self":{"DNSName":"jetson-orin.tail1234.ts.net.","KeyExpiry":"2027-04-20T10:00:00Z"}}`), &st)
	if n := keyExpiryNote(&st, now, true); !strings.HasPrefix(n, "⚠") || !strings.Contains(n, "20/04/2027") ||
		!strings.Contains(n, "machines › jetson-orin › ⋯ › Disable key expiry") {
		t.Fatalf("expiring: %q", n)
	}
	if n := keyExpiryNote(&st, now.AddDate(1, 0, 0), true); !strings.HasPrefix(n, "✗") || !strings.Contains(n, "sudo tailscale up") {
		t.Fatalf("expired: %q", n)
	}
}

// fakeTailscale puts a 'tailscale' in the PATH that prints statusJSON for 'status --json' and funnelJSON
// for 'funnel status --json'.
func fakeTailscale(t *testing.T, statusJSON, funnelJSON string) string {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("needs a shell")
	}
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "status.json"), []byte(statusJSON), 0o600)
	os.WriteFile(filepath.Join(dir, "funnel.json"), []byte(funnelJSON), 0o600)
	script := fmt.Sprintf("#!/bin/sh\ncase \"$*\" in\n\"status --json\") cat %q ;;\n\"funnel status --json\") cat %q ;;\n*) exit 1 ;;\nesac\n",
		filepath.Join(dir, "status.json"), filepath.Join(dir, "funnel.json"))
	cli := filepath.Join(dir, "tailscale")
	if err := os.WriteFile(cli, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return cli
}

func TestTailscaleSummaryAndFunnelActive(t *testing.T) {
	now := time.Date(2026, 10, 22, 12, 0, 0, 0, time.Local)
	cli := fakeTailscale(t, `{"BackendState":"Running","Self":{"DNSName":"jetson-orin.tail1234.ts.net."}}`, funnelOn)
	if s := tailscaleSummary(cli, now, true); !strings.HasPrefix(s, "✓") || !strings.Contains(s, "jetson-orin.tail1234.ts.net") {
		t.Errorf("summary: %s", s)
	}
	if ok, err := funnelActive(cli, "jetson-orin.tail1234.ts.net", "8743"); err != nil || !ok {
		t.Errorf("funnel: %v %v", ok, err)
	}
	cli = fakeTailscale(t, `{"BackendState":"NeedsLogin","Self":{}}`, `{}`)
	if s := tailscaleSummary(cli, now, true); !strings.Contains(s, "sudo tailscale up") {
		t.Errorf("logged out: %s", s)
	}
	if ok, err := funnelActive(cli, "jetson-orin.tail1234.ts.net", "8743"); err != nil || ok {
		t.Errorf("funnel off: %v %v", ok, err)
	}
	// On the Mac the Tailscale app is used, not the command.
	if s := tailscaleSummary(cli, now, false); strings.Contains(s, "sudo") || !strings.Contains(s, "apri Tailscale") {
		t.Errorf("logged out on the Mac: %s", s)
	}
	if _, err := funnelActive("", "x", "1"); err == nil {
		t.Error("no CLI: we cannot tell")
	}
}

func TestBackupSummarySaysWhenTheLastOneIsOld(t *testing.T) {
	dir := t.TempDir()
	cfg := config.Default(dir)
	write := func(s backup.Status) {
		b, _ := json.Marshal(s)
		os.WriteFile(filepath.Join(dir, "backup-status.json"), b, 0o600)
	}
	recent := time.Now().Add(-2 * time.Hour).UnixMilli()
	write(backup.Status{LastAttempt: recent, LastSuccess: recent})
	if s := backupSummary(cfg); !strings.HasPrefix(s, "✓") {
		t.Errorf("recent: %s", s)
	}
	old := time.Now().Add(-50 * time.Hour).UnixMilli()
	write(backup.Status{LastAttempt: old, LastSuccess: old})
	if s := backupSummary(cfg); !strings.HasPrefix(s, "⚠") {
		t.Errorf("two days old: %s", s)
	}
}

func TestUpgradePutsThePreviousVersionBack(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("uses the Linux service")
	}
	home := userDirs(t)
	fakeSystemctl(t, false)
	// The "installed" server keeps answering with the old version, as if the new one did not start.
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"service":"thevault","version":"1.1.0","time":1}`)
	}))
	srv.Listener = l
	srv.Start()
	defer srv.Close()
	cfg := config.Default(filepath.Join(home, ".thevault-server"))
	cfg.Listen = l.Addr().String()
	bin := BinPath(cfg.DataDir)
	os.MkdirAll(filepath.Dir(bin), 0o700)
	os.WriteFile(bin, []byte("old program"), 0o700)
	old := upgradeWait
	upgradeWait = time.Second
	t.Cleanup(func() { upgradeWait = old })

	err = Upgrade(cfg, "9.9.9")
	if err == nil || !strings.Contains(err.Error(), "Ho rimesso la versione precedente (1.1.0)") {
		t.Fatalf("upgrade: %v", err)
	}
	if b, _ := os.ReadFile(bin); string(b) != "old program" {
		t.Fatal("the previous program was not put back")
	}
	// The same version answering: the upgrade worked, and the previous program is kept aside.
	if err := Upgrade(cfg, "1.1.0"); err != nil {
		t.Fatalf("upgrade: %v", err)
	}
	if b, _ := os.ReadFile(bin + ".prev"); string(b) != "old program" {
		t.Fatal("previous program not kept")
	}
}

func TestUpgradeKeepsTheNewVersionOnceItUpdatedTheDatabase(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("uses the Linux service")
	}
	home := userDirs(t)
	fakeSystemctl(t, false)
	cfg := config.Default(filepath.Join(home, ".thevault-server"))
	st, err := store.Open(filepath.Join(cfg.DataDir, "thevault.db"))
	if err != nil {
		t.Fatal(err)
	}
	st.Close()
	// The new version starts, migrates the database (here: a newer schema) and then never answers right.
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if db, err := store.OpenNoMigrate(filepath.Join(cfg.DataDir, "thevault.db")); err == nil {
			db.DB.ExecContext(context.Background(), `UPDATE schema_version SET version = 99`)
			db.Close()
		}
		fmt.Fprint(w, `{"service":"thevault","version":"broken","time":1}`)
	}))
	srv.Listener = l
	srv.Start()
	defer srv.Close()
	cfg.Listen = l.Addr().String()
	bin := BinPath(cfg.DataDir)
	os.MkdirAll(filepath.Dir(bin), 0o700)
	if err := os.WriteFile(bin, []byte("old program"), 0o700); err != nil {
		t.Fatal(err)
	}
	old := upgradeWait
	upgradeWait = time.Second
	t.Cleanup(func() { upgradeWait = old })

	err = Upgrade(cfg, "9.9.9")
	if err == nil || !strings.Contains(err.Error(), "ha già aggiornato il database") {
		t.Fatalf("upgrade: %v", err)
	}
	if b, _ := os.ReadFile(bin); string(b) == "old program" {
		t.Fatal("the previous program cannot use the updated database: it must not be put back")
	}
}
