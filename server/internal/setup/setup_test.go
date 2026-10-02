package setup

import (
	"bufio"
	"bytes"
	"errors"
	"path/filepath"
	"strings"
	"testing"

	"github.com/simonescoca/the.vault/server/internal/config"
)

func newTestWizard(t *testing.T, input string, mailErrs []error) (*Wizard, *bytes.Buffer, *int) {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	out := &bytes.Buffer{}
	sent := 0
	installed := 0
	w := &Wizard{
		In:      bufio.NewReader(strings.NewReader(input)),
		Out:     out,
		DataDir: filepath.Join(t.TempDir(), "data"),
		Version: "test",
		ReadPassword: func(prompt string) (string, error) {
			return "abcd-efgh-ijkl-mnop", nil
		},
		SendTestMail: func(cfg *config.Config) error {
			defer func() { sent++ }()
			if sent < len(mailErrs) {
				return mailErrs[sent]
			}
			return nil
		},
		InstallService: func(cfg *config.Config) error { installed++; return nil },
		WaitHealthy:    func(cfg *config.Config) error { return nil },
		SetupFunnel: func(w *Wizard, cfg *config.Config) error {
			cfg.PublicURL = "https://mac-mini.tail1234.ts.net"
			return nil
		},
	}
	return w, out, &installed
}

func TestWizardICloudHappyPath(t *testing.T) {
	// email, provider (default 1 = iCloud), sender (default = email), backup dir (default)
	w, out, installed := newTestWizard(t, "Mario.Rossi@iCloud.com\n\n\n\n", nil)
	if err := w.Run(); err != nil {
		t.Fatalf("wizard: %v\n%s", err, out)
	}
	cfg, err := config.Load(w.DataDir)
	if err != nil {
		t.Fatalf("saved config: %v", err)
	}
	if cfg.AllowedEmails[0] != "mario.rossi@icloud.com" {
		t.Errorf("email: %v", cfg.AllowedEmails)
	}
	if cfg.SMTP.Host != "smtp.mail.me.com" || cfg.SMTP.Port != 587 || cfg.SMTP.Security != "starttls" ||
		cfg.SMTP.Username != "mario.rossi@icloud.com" || cfg.SMTP.Password != "abcd-efgh-ijkl-mnop" {
		t.Errorf("smtp: %+v", cfg.SMTP)
	}
	if cfg.PublicURL != "https://mac-mini.tail1234.ts.net" || cfg.ServerSecret == "" || *installed != 1 {
		t.Errorf("cfg: %+v installed=%d", cfg, *installed)
	}
	if !strings.Contains(out.String(), "mac-mini.tail1234.ts.net") {
		t.Errorf("final address not shown:\n%s", out)
	}
	// Re-running keeps the secret.
	secret := cfg.ServerSecret
	w2, out2, _ := newTestWizard(t, "\n\n\n\n", nil)
	w2.DataDir = w.DataDir
	if err := w2.Run(); err != nil {
		t.Fatalf("second run: %v\n%s", err, out2)
	}
	cfg2, _ := config.Load(w.DataDir)
	if cfg2.ServerSecret != secret || cfg2.AllowedEmails[0] != "mario.rossi@icloud.com" {
		t.Errorf("second run lost settings: %+v", cfg2)
	}
}

func TestWizardRetriesFailingMailAndValidatesEmail(t *testing.T) {
	// invalid email, valid email, provider 2 (Gmail), sender, [mail fails] retry yes, sender again, backup dir
	in := "not-an-email\nme@gmail.com\n2\n\ns\n\n\n"
	w, out, _ := newTestWizard(t, in, []error{errors.New("535 bad credentials")})
	if err := w.Run(); err != nil {
		t.Fatalf("wizard: %v\n%s", err, out)
	}
	if !strings.Contains(out.String(), "Non sembra un indirizzo email valido") || !strings.Contains(out.String(), "535 bad credentials") {
		t.Errorf("missing messages:\n%s", out)
	}
	cfg, _ := config.Load(w.DataDir)
	if cfg.SMTP.Host != "smtp.gmail.com" {
		t.Errorf("smtp host: %s", cfg.SMTP.Host)
	}
}

func TestPlistEscapesPaths(t *testing.T) {
	p := Plist("/Users/a&b/bin/thevault-server", "/Users/a&b/Library/Application Support/TheVaultServer")
	if !strings.Contains(p, "/Users/a&amp;b/bin/thevault-server") || !strings.Contains(p, "<string>serve</string>") ||
		!strings.Contains(p, "<key>KeepAlive</key>") {
		t.Fatalf("plist:\n%s", p)
	}
}
