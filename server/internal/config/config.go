// Package config loads and saves the server configuration (config.json in the data directory).
package config

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/mail"
	"os"
	"path/filepath"
	"strings"
)

const FileName = "config.json"

// DefaultMaxBlobBytes is the maximum encrypted size of one attachment: 200 MiB of content plus
// the stream encryption overhead (17 bytes per 64 KiB chunk) and some margin.
const DefaultMaxBlobBytes int64 = 201 << 20

type SMTP struct {
	Host     string `json:"host"`
	Port     int    `json:"port"`
	Username string `json:"username"`
	Password string `json:"password"`
	From     string `json:"from"`
	// Security is "starttls" (port 587), "tls" (port 465) or "none" (only for local testing).
	Security string `json:"security"`
}

type Backup struct {
	Dir      string `json:"dir"`
	KeepDays int    `json:"keepDays"`
	// Hour (0-23, local time) at which the daily backup runs.
	Hour int `json:"hour"`
}

type Config struct {
	Listen        string   `json:"listen"`
	DataDir       string   `json:"-"`
	PublicURL     string   `json:"publicUrl"`
	AllowedEmails []string `json:"allowedEmails"`
	// ServerSecret keys the HMAC of one-time codes. Generated at setup, never leaves the server.
	ServerSecret string `json:"serverSecret"`
	// MailMode is "smtp" or "log" (emails are written to mail.log; for tests and development).
	MailMode     string `json:"mailMode"`
	SMTP         SMTP   `json:"smtp"`
	Backup       Backup `json:"backup"`
	MaxBlobBytes int64  `json:"maxBlobBytes"`
	LogLevel     string `json:"logLevel"`
	// TestMode disables the resend delay and the per-email/IP limits of login codes.
	// Only for automated tests: never enable it on a real server.
	TestMode bool `json:"testMode,omitempty"`
}

// Default returns a configuration with sensible defaults for the given data directory.
func Default(dataDir string) *Config {
	return &Config{
		Listen:       "127.0.0.1:8743",
		DataDir:      dataDir,
		MailMode:     "smtp",
		SMTP:         SMTP{Port: 587, Security: "starttls"},
		Backup:       Backup{KeepDays: 30, Hour: 3},
		MaxBlobBytes: DefaultMaxBlobBytes,
		LogLevel:     "info",
	}
}

// DefaultDataDir is ~/Library/Application Support/TheVaultServer on macOS and ~/.thevault-server elsewhere.
func DefaultDataDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ".thevault-server"
	}
	if _, err := os.Stat(filepath.Join(home, "Library", "Application Support")); err == nil {
		return filepath.Join(home, "Library", "Application Support", "TheVaultServer")
	}
	return filepath.Join(home, ".thevault-server")
}

// Load reads dataDir/config.json.
func Load(dataDir string) (*Config, error) {
	b, err := os.ReadFile(filepath.Join(dataDir, FileName))
	if err != nil {
		return nil, err
	}
	c := Default(dataDir)
	if err := json.Unmarshal(b, c); err != nil {
		return nil, fmt.Errorf("config.json non valido: %w", err)
	}
	c.DataDir = dataDir
	c.Normalize()
	return c, c.Validate()
}

// Save writes dataDir/config.json with owner-only permissions (it contains the SMTP password).
func (c *Config) Save() error {
	if err := os.MkdirAll(c.DataDir, 0o700); err != nil {
		return err
	}
	b, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	tmp := filepath.Join(c.DataDir, FileName+".tmp")
	if err := os.WriteFile(tmp, append(b, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, filepath.Join(c.DataDir, FileName))
}

// Normalize lower-cases and de-duplicates emails and fills empty values with defaults.
func (c *Config) Normalize() {
	seen := map[string]bool{}
	var emails []string
	for _, e := range c.AllowedEmails {
		e = NormalizeEmail(e)
		if e != "" && !seen[e] {
			seen[e] = true
			emails = append(emails, e)
		}
	}
	c.AllowedEmails = emails
	if c.Listen == "" {
		c.Listen = "127.0.0.1:8743"
	}
	if c.MailMode == "" {
		c.MailMode = "smtp"
	}
	if c.MaxBlobBytes <= 0 {
		c.MaxBlobBytes = DefaultMaxBlobBytes
	}
	if c.Backup.KeepDays <= 0 {
		c.Backup.KeepDays = 30
	}
	if c.Backup.Hour < 0 || c.Backup.Hour > 23 {
		c.Backup.Hour = 3
	}
	c.PublicURL = strings.TrimRight(strings.TrimSpace(c.PublicURL), "/")
}

func (c *Config) Validate() error {
	if len(c.AllowedEmails) == 0 {
		return errors.New("nessuna email ammessa: esegui 'thevault-server setup'")
	}
	if s, err := base64.RawURLEncoding.DecodeString(c.ServerSecret); err != nil || len(s) < 32 {
		return errors.New("serverSecret mancante o non valido: esegui 'thevault-server setup'")
	}
	switch c.MailMode {
	case "log":
	case "smtp":
		if c.SMTP.Host == "" || c.SMTP.Port == 0 || c.SMTP.From == "" {
			return errors.New("configurazione email (SMTP) incompleta: esegui 'thevault-server setup'")
		}
		switch c.SMTP.Security {
		case "starttls", "tls", "none":
		default:
			return fmt.Errorf("smtp.security non valido: %q", c.SMTP.Security)
		}
	default:
		return fmt.Errorf("mailMode non valido: %q", c.MailMode)
	}
	return nil
}

// Secret returns the decoded server secret.
func (c *Config) Secret() []byte {
	s, _ := base64.RawURLEncoding.DecodeString(c.ServerSecret)
	return s
}

// IsAllowed reports whether an (already normalized) email may log in.
func (c *Config) IsAllowed(email string) bool {
	for _, e := range c.AllowedEmails {
		if e == email {
			return true
		}
	}
	return false
}

// NewSecret returns a fresh random 32-byte secret, base64url encoded.
func NewSecret() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

// NormalizeEmail trims and lower-cases an email; returns "" when it is not a plain address.
func NormalizeEmail(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	if s == "" || len(s) > 254 {
		return ""
	}
	a, err := mail.ParseAddress(s)
	if err != nil || a.Address != s || a.Name != "" || !strings.Contains(s[strings.LastIndex(s, "@")+1:], ".") {
		return ""
	}
	return s
}
