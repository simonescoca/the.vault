// Package mail sends the server's emails: one-time login codes and new-device alerts.
package mail

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/hex"
	"errors"
	"fmt"
	"mime"
	"mime/quotedprintable"
	"net"
	"net/smtp"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/simonescoca/the.vault/server/internal/config"
)

type Message struct {
	To      string
	Subject string
	Text    string
}

type Sender interface {
	Send(ctx context.Context, m Message) error
}

// New returns the sender configured in c.
func New(c *config.Config) Sender {
	if c.MailMode == "log" {
		return &LogSender{Path: c.DataDir + string(os.PathSeparator) + "mail.log"}
	}
	return &SMTPSender{Cfg: c.SMTP}
}

// LogSender appends messages to a file and keeps them in memory (development and tests).
type LogSender struct {
	Path string
	mu   sync.Mutex
	sent []Message
}

func (l *LogSender) Send(_ context.Context, m Message) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.sent = append(l.sent, m)
	if l.Path == "" {
		return nil
	}
	f, err := os.OpenFile(l.Path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = fmt.Fprintf(f, "---- %s\nTo: %s\nSubject: %s\n\n%s\n", time.Now().Format(time.RFC3339), m.To, m.Subject, m.Text)
	return err
}

// Sent returns a copy of the messages sent so far.
func (l *LogSender) Sent() []Message {
	l.mu.Lock()
	defer l.mu.Unlock()
	return append([]Message(nil), l.sent...)
}

// SMTPSender delivers through an SMTP server (e.g. iCloud: smtp.mail.me.com:587, STARTTLS,
// with an app-specific password).
type SMTPSender struct {
	Cfg config.SMTP
	// TLSConfig overrides the TLS settings (tests).
	TLSConfig *tls.Config
}

func (s *SMTPSender) Send(ctx context.Context, m Message) error {
	cfg := s.Cfg
	addr := net.JoinHostPort(cfg.Host, strconv.Itoa(cfg.Port))
	tlsCfg := s.TLSConfig
	if tlsCfg == nil {
		tlsCfg = &tls.Config{ServerName: cfg.Host, MinVersion: tls.VersionTLS12}
	}
	dialer := &net.Dialer{Timeout: 15 * time.Second}
	deadline := time.Now().Add(30 * time.Second)
	if d, ok := ctx.Deadline(); ok && d.Before(deadline) {
		deadline = d
	}
	var conn net.Conn
	var err error
	if cfg.Security == "tls" {
		conn, err = tls.DialWithDialer(dialer, "tcp", addr, tlsCfg)
	} else {
		conn, err = dialer.DialContext(ctx, "tcp", addr)
	}
	if err != nil {
		return fmt.Errorf("connessione al server email %s: %w", addr, err)
	}
	conn.SetDeadline(deadline)
	c, err := smtp.NewClient(conn, cfg.Host)
	if err != nil {
		conn.Close()
		return err
	}
	defer c.Close()
	if err := c.Hello(helloName()); err != nil {
		return err
	}
	if cfg.Security == "starttls" {
		if ok, _ := c.Extension("STARTTLS"); !ok {
			return errors.New("il server email non supporta STARTTLS")
		}
		if err := c.StartTLS(tlsCfg); err != nil {
			return fmt.Errorf("STARTTLS: %w", err)
		}
	}
	if cfg.Username != "" {
		if ok, _ := c.Extension("AUTH"); ok {
			if err := c.Auth(smtp.PlainAuth("", cfg.Username, cfg.Password, cfg.Host)); err != nil {
				return fmt.Errorf("autenticazione email: %w", err)
			}
		}
	}
	from := cfg.From
	if a, err := parseAddr(from); err == nil {
		from = a
	}
	if err := c.Mail(from); err != nil {
		return err
	}
	if err := c.Rcpt(m.To); err != nil {
		return err
	}
	w, err := c.Data()
	if err != nil {
		return err
	}
	if _, err := w.Write(Build(cfg.From, m)); err != nil {
		return err
	}
	if err := w.Close(); err != nil {
		return err
	}
	return c.Quit()
}

func helloName() string {
	h, err := os.Hostname()
	if err != nil || h == "" || strings.ContainsAny(h, " \t") {
		return "localhost"
	}
	return h
}

func parseAddr(s string) (string, error) {
	if i := strings.LastIndex(s, "<"); i >= 0 {
		if j := strings.LastIndex(s, ">"); j > i {
			return s[i+1 : j], nil
		}
	}
	if strings.Contains(s, "@") {
		return strings.TrimSpace(s), nil
	}
	return "", errors.New("invalid address")
}

// Build renders an RFC 5322 message with a quoted-printable UTF-8 text body.
func Build(from string, m Message) []byte {
	var b bytes.Buffer
	id := make([]byte, 12)
	rand.Read(id)
	domain := "thevault.local"
	if a, err := parseAddr(from); err == nil {
		if i := strings.LastIndex(a, "@"); i >= 0 {
			domain = a[i+1:]
		}
	}
	fmt.Fprintf(&b, "From: %s\r\n", encodeAddress(from))
	fmt.Fprintf(&b, "To: %s\r\n", m.To)
	fmt.Fprintf(&b, "Subject: %s\r\n", mime.QEncoding.Encode("utf-8", m.Subject))
	fmt.Fprintf(&b, "Date: %s\r\n", time.Now().Format(time.RFC1123Z))
	fmt.Fprintf(&b, "Message-ID: <%s@%s>\r\n", hex.EncodeToString(id), domain)
	b.WriteString("MIME-Version: 1.0\r\n")
	b.WriteString("Content-Type: text/plain; charset=utf-8\r\n")
	b.WriteString("Content-Transfer-Encoding: quoted-printable\r\n\r\n")
	qp := quotedprintable.NewWriter(&b)
	qp.Write([]byte(strings.ReplaceAll(m.Text, "\n", "\r\n")))
	qp.Close()
	b.WriteString("\r\n")
	return b.Bytes()
}

func encodeAddress(s string) string {
	if i := strings.LastIndex(s, "<"); i > 0 {
		name := strings.TrimSpace(s[:i])
		return mime.QEncoding.Encode("utf-8", name) + " " + s[i:]
	}
	return s
}

// --- templates ---

func lang(locale string) string {
	if strings.HasPrefix(strings.ToLower(locale), "it") {
		return "it"
	}
	return "en"
}

// OTPMessage is the login code email.
func OTPMessage(to, code, locale, deviceName string) Message {
	spaced := code[:3] + " " + code[3:]
	if lang(locale) == "it" {
		return Message{To: to,
			Subject: "Il tuo codice di accesso a The Vault: " + spaced,
			Text: "Ciao,\n\n" +
				"ecco il codice per accedere a The Vault" + deviceSuffixIT(deviceName) + ":\n\n" +
				"    " + spaced + "\n\n" +
				"Il codice scade tra 10 minuti.\n\n" +
				"Se non hai chiesto tu questo codice, ignora questa email: senza l'approvazione da uno dei tuoi dispositivi " +
				"(o il tuo codice di emergenza) nessuno può leggere le tue password.\n\n— The Vault\n"}
	}
	return Message{To: to,
		Subject: "Your The Vault sign-in code: " + spaced,
		Text: "Hi,\n\n" +
			"here is your code to sign in to The Vault" + deviceSuffixEN(deviceName) + ":\n\n" +
			"    " + spaced + "\n\n" +
			"The code expires in 10 minutes.\n\n" +
			"If you did not request it, ignore this email: without the approval of one of your devices " +
			"(or your emergency code) nobody can read your passwords.\n\n— The Vault\n"}
}

// NewDeviceMessage is the alert sent when a device gains access to the vault.
func NewDeviceMessage(to, locale, deviceName, platform, how string) Message {
	when := time.Now().Format("02/01/2006 15:04")
	if lang(locale) == "it" {
		via := "approvato da un tuo dispositivo"
		if how == "recovery" {
			via = "con il codice di emergenza"
		}
		return Message{To: to,
			Subject: "Nuovo dispositivo collegato a The Vault",
			Text: "Ciao,\n\n" +
				"il dispositivo «" + deviceName + "» (" + platform + ") è stato collegato al tuo The Vault il " + when +
				", " + via + ".\n\n" +
				"Se non sei stato tu, apri The Vault su un tuo dispositivo, vai in Impostazioni › Dispositivi e " +
				"disconnettilo subito; poi genera un nuovo codice di emergenza.\n\n— The Vault\n"}
	}
	via := "approved by one of your devices"
	if how == "recovery" {
		via = "using the emergency code"
	}
	return Message{To: to,
		Subject: "New device connected to The Vault",
		Text: "Hi,\n\n" +
			"the device “" + deviceName + "” (" + platform + ") was connected to your The Vault on " + when + ", " + via + ".\n\n" +
			"If this was not you, open The Vault on one of your devices, go to Settings › Devices and disconnect it " +
			"right away; then generate a new emergency code.\n\n— The Vault\n"}
}

func deviceSuffixIT(name string) string {
	if name == "" {
		return ""
	}
	return " da «" + name + "»"
}

func deviceSuffixEN(name string) string {
	if name == "" {
		return ""
	}
	return " from “" + name + "”"
}
