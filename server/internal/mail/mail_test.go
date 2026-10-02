package mail

import (
	"bufio"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"math/big"
	"net"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/simonescoca/the.vault/server/internal/config"
)

// fakeSMTP is a minimal SMTP server supporting EHLO, STARTTLS, AUTH PLAIN, MAIL, RCPT, DATA, QUIT.
type fakeSMTP struct {
	ln       net.Listener
	tlsCfg   *tls.Config
	authUser string
	authPass string
	got      chan string
}

func selfSigned(t *testing.T) tls.Certificate {
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	tpl := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "localhost"},
		DNSNames: []string{"localhost"}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour)}
	der, err := x509.CreateCertificate(rand.Reader, tpl, tpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}
}

func (f *fakeSMTP) serve(t *testing.T) {
	conn, err := f.ln.Accept()
	if err != nil {
		return
	}
	defer conn.Close()
	r, w := bufio.NewReader(conn), conn
	write := func(s string) { w.Write([]byte(s + "\r\n")) }
	write("220 localhost ESMTP fake")
	tlsOn := false
	authed := false
	var data strings.Builder
	for {
		line, err := r.ReadString('\n')
		if err != nil {
			return
		}
		line = strings.TrimRight(line, "\r\n")
		cmd := strings.ToUpper(strings.SplitN(line, " ", 2)[0])
		switch cmd {
		case "EHLO", "HELO":
			if !tlsOn {
				write("250-localhost")
				write("250 STARTTLS")
			} else {
				write("250-localhost")
				write("250 AUTH PLAIN")
			}
		case "STARTTLS":
			write("220 go ahead")
			tc := tls.Server(conn, f.tlsCfg)
			if err := tc.Handshake(); err != nil {
				t.Errorf("tls handshake: %v", err)
				return
			}
			conn, r, w = tc, bufio.NewReader(tc), tc
			tlsOn = true
		case "AUTH":
			parts := strings.Fields(line)
			raw, _ := base64.StdEncoding.DecodeString(parts[2])
			fields := strings.Split(string(raw), "\x00")
			if len(fields) == 3 && fields[1] == f.authUser && fields[2] == f.authPass && tlsOn {
				authed = true
				write("235 ok")
			} else {
				write("535 bad credentials")
			}
		case "MAIL", "RCPT":
			if !authed {
				write("530 auth required")
				continue
			}
			write("250 ok")
		case "DATA":
			write("354 send")
			for {
				l, err := r.ReadString('\n')
				if err != nil {
					return
				}
				if l == ".\r\n" {
					break
				}
				data.WriteString(l)
			}
			write("250 queued")
			f.got <- data.String()
		case "QUIT":
			write("221 bye")
			return
		default:
			write("502 unknown")
		}
	}
}

func TestSMTPSenderStartTLSAuthAndDelivery(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	cert := selfSigned(t)
	f := &fakeSMTP{ln: ln, tlsCfg: &tls.Config{Certificates: []tls.Certificate{cert}}, authUser: "me@icloud.com",
		authPass: "abcd-efgh-ijkl-mnop", got: make(chan string, 1)}
	go f.serve(t)

	port, _ := strconv.Atoi(strings.Split(ln.Addr().String(), ":")[1])
	s := &SMTPSender{
		Cfg: config.SMTP{Host: "localhost", Port: port, Username: "me@icloud.com", Password: "abcd-efgh-ijkl-mnop",
			From: "The Vault <me@icloud.com>", Security: "starttls"},
		TLSConfig: &tls.Config{InsecureSkipVerify: true}, // self-signed test certificate
	}
	// Dial 127.0.0.1 via "localhost".
	m := OTPMessage("me@icloud.com", "123456", "it", "MacBook")
	if err := s.Send(context.Background(), m); err != nil {
		t.Fatalf("send: %v", err)
	}
	select {
	case body := <-f.got:
		if !strings.Contains(body, "Subject: Il tuo codice di accesso a The Vault: 123 456\r\n") {
			t.Errorf("unexpected subject in:\n%s", body)
		}
		if !strings.Contains(body, "123 456") || !strings.Contains(body, "scade tra 10 minuti") {
			t.Errorf("body missing code or text:\n%s", body)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("no message received")
	}
}

func TestSMTPSenderRejectsBadCredentials(t *testing.T) {
	ln, _ := net.Listen("tcp", "127.0.0.1:0")
	defer ln.Close()
	f := &fakeSMTP{ln: ln, tlsCfg: &tls.Config{Certificates: []tls.Certificate{selfSigned(t)}}, authUser: "u", authPass: "right",
		got: make(chan string, 1)}
	go f.serve(t)
	port, _ := strconv.Atoi(strings.Split(ln.Addr().String(), ":")[1])
	s := &SMTPSender{Cfg: config.SMTP{Host: "localhost", Port: port, Username: "u", Password: "wrong", From: "u@x.it",
		Security: "starttls"}, TLSConfig: &tls.Config{InsecureSkipVerify: true}}
	if err := s.Send(context.Background(), Message{To: "a@b.it", Subject: "x", Text: "y"}); err == nil {
		t.Fatal("expected authentication error")
	}
}

func TestTemplates(t *testing.T) {
	en := OTPMessage("a@b.it", "654321", "en-US", "")
	if !strings.Contains(en.Subject, "654 321") || !strings.Contains(en.Text, "expires in 10 minutes") {
		t.Fatalf("bad EN otp: %+v", en)
	}
	it := NewDeviceMessage("a@b.it", "it", "PC di casa", "windows", "recovery")
	if !strings.Contains(it.Text, "codice di emergenza") || !strings.Contains(it.Text, "PC di casa") {
		t.Fatalf("bad IT alert: %+v", it)
	}
	raw := string(Build("The Vault <me@icloud.com>", it))
	if !strings.Contains(raw, "Content-Transfer-Encoding: quoted-printable") || !strings.Contains(raw, "@icloud.com>") {
		t.Fatalf("bad raw message:\n%s", raw)
	}
}
