package api

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/simonescoca/the.vault/server/internal/config"
	"github.com/simonescoca/the.vault/server/internal/mail"
	"github.com/simonescoca/the.vault/server/internal/store"
)

const testEmail = "me@example.com"

type env struct {
	t    *testing.T
	srv  *Server
	ts   *httptest.Server
	mail *mail.LogSender
}

func newEnv(t *testing.T) *env {
	t.Helper()
	dir := t.TempDir()
	cfg := config.Default(dir)
	cfg.AllowedEmails = []string{testEmail}
	cfg.ServerSecret = config.NewSecret()
	cfg.MailMode = "log"
	st, err := store.Open(filepath.Join(dir, "thevault.db"))
	if err != nil {
		t.Fatal(err)
	}
	ls := &mail.LogSender{}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := New(cfg, st, ls, log, "test")
	srv.PartSize = 1024
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(func() { ts.Close(); st.Close() })
	return &env{t: t, srv: srv, ts: ts, mail: ls}
}

type client struct {
	e     *env
	token string
	id    string
}

func (e *env) anon() *client { return &client{e: e} }

func (c *client) req(method, path string, body any) (int, map[string]any) {
	c.e.t.Helper()
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	r, _ := http.NewRequest(method, c.e.ts.URL+path, rd)
	r.Header.Set("Content-Type", "application/json")
	if c.token != "" {
		r.Header.Set("Authorization", "Bearer "+c.token)
	}
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		c.e.t.Fatalf("%s %s: %v", method, path, err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	out := map[string]any{}
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &out); err != nil {
			c.e.t.Fatalf("%s %s: bad JSON %q", method, path, raw)
		}
	}
	return resp.StatusCode, out
}

func (c *client) must(status int, method, path string, body any) map[string]any {
	c.e.t.Helper()
	got, out := c.req(method, path, body)
	if got != status {
		c.e.t.Fatalf("%s %s: status %d, want %d: %v", method, path, got, status, out)
	}
	return out
}

// status performs a request and returns only the status code (for binary responses).
func (c *client) status(method, path string) int {
	c.e.t.Helper()
	r, _ := http.NewRequest(method, c.e.ts.URL+path, nil)
	r.Header.Set("Authorization", "Bearer "+c.token)
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		c.e.t.Fatal(err)
	}
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	return resp.StatusCode
}

func errCode(out map[string]any) string {
	if e, ok := out["error"].(map[string]any); ok {
		return e["code"].(string)
	}
	return ""
}

func rnd(n int) []byte { b := make([]byte, n); rand.Read(b); return b }

func enc(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

var codeRe = regexp.MustCompile(`(\d{3}) (\d{3})`)

func (e *env) lastCode() string {
	e.t.Helper()
	sent := e.mail.Sent()
	if len(sent) == 0 {
		e.t.Fatal("no email sent")
	}
	m := codeRe.FindStringSubmatch(sent[len(sent)-1].Subject)
	if m == nil {
		e.t.Fatalf("no code in %q", sent[len(sent)-1].Subject)
	}
	return m[1] + m[2]
}

// login runs the email + code flow and returns an authenticated client.
func (e *env) login(name, platform string) (*client, string) {
	e.t.Helper()
	a := e.anon()
	// The resend cooldown applies per email: rewind the clock between logins.
	if o, err := e.srv.Store.GetOTP(context.Background(), testEmail); err == nil {
		e.srv.Store.PutOTP(context.Background(), store.OTP{Email: o.Email, CodeMAC: o.CodeMAC, ExpiresAt: o.ExpiresAt, SentAt: 0})
	}
	a.must(202, "POST", "/v1/auth/otp/request", map[string]any{"email": testEmail, "locale": "it", "deviceName": name})
	out := a.must(200, "POST", "/v1/auth/otp/verify", map[string]any{"email": " ME@example.com ", "code": e.lastCode(),
		"device": map[string]any{"name": name, "platform": platform, "publicKey": enc(rnd(32))}})
	return &client{e: e, token: out["token"].(string), id: out["deviceId"].(string)}, out["status"].(string)
}

func recoveryBody() map[string]any {
	return map[string]any{
		"keyCheck":     enc(rnd(16)),
		"recovery":     map[string]any{"salt": enc(rnd(16)), "opsLimit": 2, "memLimit": 64 << 20, "wrap": enc(rnd(72))},
		"recoveryAuth": enc(rnd(32)),
	}
}

// firstDevice logs in and creates the vault.
func (e *env) firstDevice() *client {
	c, status := e.login("Mac mini", "macos")
	if status != "setup" {
		e.t.Fatalf("first device status %s, want setup", status)
	}
	c.must(200, "POST", "/v1/vault/init", recoveryBody())
	return c
}

// --- WebSocket helper ---

type wsClient struct {
	t      *testing.T
	conn   *websocket.Conn
	mu     sync.Mutex
	events []map[string]any
	notify chan struct{}
	closed chan struct{}
}

func (c *client) ws() *wsClient {
	c.e.t.Helper()
	url := "ws" + strings.TrimPrefix(c.e.ts.URL, "http") + "/v1/ws"
	conn, _, err := websocket.Dial(context.Background(), url, &websocket.DialOptions{
		HTTPHeader: http.Header{"Authorization": []string{"Bearer " + c.token}},
	})
	if err != nil {
		c.e.t.Fatalf("ws dial: %v", err)
	}
	w := &wsClient{t: c.e.t, conn: conn, notify: make(chan struct{}, 100), closed: make(chan struct{})}
	go func() {
		defer close(w.closed)
		for {
			_, msg, err := conn.Read(context.Background())
			if err != nil {
				return
			}
			var ev map[string]any
			json.Unmarshal(msg, &ev)
			w.mu.Lock()
			w.events = append(w.events, ev)
			w.mu.Unlock()
			w.notify <- struct{}{}
		}
	}()
	c.e.t.Cleanup(func() { conn.Close(websocket.StatusNormalClosure, "") })
	w.wait("hello")
	return w
}

// wait returns the first not-yet-consumed event of the given type.
func (w *wsClient) wait(typ string) map[string]any {
	w.t.Helper()
	deadline := time.After(5 * time.Second)
	for {
		w.mu.Lock()
		for i, ev := range w.events {
			if ev["type"] == typ {
				w.events = append(w.events[:i], w.events[i+1:]...)
				w.mu.Unlock()
				return ev
			}
		}
		w.mu.Unlock()
		select {
		case <-w.notify:
		case <-deadline:
			w.t.Fatalf("timeout waiting for %s event", typ)
		}
	}
}

// --- tests ---

func TestHealthAndUnknownRoutes(t *testing.T) {
	e := newEnv(t)
	out := e.anon().must(200, "GET", "/v1/health", nil)
	if out["service"] != "thevault" {
		t.Fatalf("health: %v", out)
	}
	if code, out := e.anon().req("GET", "/v1/nope", nil); code != 404 || errCode(out) != "not_found" {
		t.Fatalf("unknown route: %d %v", code, out)
	}
	if code, _ := e.anon().req("GET", "/v1/me", nil); code != 401 {
		t.Fatalf("me without token: %d", code)
	}
}

func TestLoginWithCodeAndVaultInit(t *testing.T) {
	e := newEnv(t)
	a := e.anon()
	a.must(202, "POST", "/v1/auth/otp/request", map[string]any{"email": testEmail, "locale": "it"})
	if len(e.mail.Sent()) != 1 || e.mail.Sent()[0].To != testEmail {
		t.Fatalf("expected one email to %s: %v", testEmail, e.mail.Sent())
	}
	// Resend too early.
	if code, out := a.req("POST", "/v1/auth/otp/request", map[string]any{"email": testEmail}); code != 429 || errCode(out) != "rate_limited" {
		t.Fatalf("resend cooldown: %d %v", code, out)
	}
	dev := map[string]any{"name": "MacBook", "platform": "macos", "publicKey": enc(rnd(32))}
	code := e.lastCode()
	wrong := "000000"
	if wrong == code {
		wrong = "111111"
	}
	_, out := a.req("POST", "/v1/auth/otp/verify", map[string]any{"email": testEmail, "code": wrong, "device": dev})
	if errCode(out) != "otp_invalid" || out["attemptsLeft"].(float64) != 4 {
		t.Fatalf("wrong code: %v", out)
	}
	out = a.must(200, "POST", "/v1/auth/otp/verify", map[string]any{"email": testEmail, "code": code[:3] + " " + code[3:], "device": dev})
	if out["status"] != "setup" {
		t.Fatalf("status: %v", out)
	}
	c := &client{e: e, token: out["token"].(string)}
	// The code is single-use.
	if code2, out2 := a.req("POST", "/v1/auth/otp/verify", map[string]any{"email": testEmail, "code": code, "device": dev}); code2 != 410 {
		t.Fatalf("reused code: %d %v", code2, out2)
	}
	// A setup device cannot read records.
	if code, _ := c.req("GET", "/v1/records", nil); code != 403 {
		t.Fatalf("records before init: %d", code)
	}
	me := c.must(200, "GET", "/v1/me", nil)
	if me["email"] != testEmail || me["vault"].(map[string]any)["initialized"] != false {
		t.Fatalf("me: %v", me)
	}
	bad := recoveryBody()
	bad["keyCheck"] = enc(rnd(5))
	if code, out := c.req("POST", "/v1/vault/init", bad); code != 400 || errCode(out) != "invalid_field" {
		t.Fatalf("bad init: %d %v", code, out)
	}
	c.must(200, "POST", "/v1/vault/init", recoveryBody())
	c.must(200, "GET", "/v1/records", nil)
	if code, _ := c.req("POST", "/v1/vault/init", recoveryBody()); code != 403 {
		t.Fatalf("second init: %d", code)
	}
	// A later login lands in pending.
	if _, status := e.login("PC", "windows"); status != "pending" {
		t.Fatalf("second device status %s", status)
	}
}

func TestNotAllowedEmailBehavesLikeWrongCode(t *testing.T) {
	e := newEnv(t)
	a := e.anon()
	a.must(202, "POST", "/v1/auth/otp/request", map[string]any{"email": "intruder@evil.com"})
	if len(e.mail.Sent()) != 0 {
		t.Fatal("no email must be sent to a non-allowed address")
	}
	dev := map[string]any{"name": "X", "platform": "linux", "publicKey": enc(rnd(32))}
	for i := 0; i < 5; i++ {
		code, out := a.req("POST", "/v1/auth/otp/verify", map[string]any{"email": "intruder@evil.com", "code": fmt.Sprintf("%06d", i), "device": dev})
		if code != 422 || errCode(out) != "otp_invalid" {
			t.Fatalf("attempt %d: %d %v", i, code, out)
		}
	}
	if code, out := a.req("POST", "/v1/auth/otp/verify", map[string]any{"email": "intruder@evil.com", "code": "123456", "device": dev}); code != 410 {
		t.Fatalf("after 5 attempts: %d %v", code, out)
	}
	if code, out := a.req("POST", "/v1/auth/otp/request", map[string]any{"email": "not-an-email"}); code != 400 || errCode(out) != "invalid_email" {
		t.Fatalf("invalid email: %d %v", code, out)
	}
}

func TestDeviceApprovalFlow(t *testing.T) {
	e := newEnv(t)
	d1 := e.firstDevice()
	ws1 := d1.ws()
	d2, status := e.login("PC di casa", "windows")
	if status != "pending" {
		t.Fatalf("status %s", status)
	}
	ws1.wait("devices.changed")
	if code, _ := d2.req("GET", "/v1/records", nil); code != 403 {
		t.Fatalf("pending device must not read records: %d", code)
	}
	ws2 := d2.ws()

	commit := rnd(32)
	out := d2.must(201, "POST", "/v1/approvals", map[string]any{"commitment": enc(commit)})
	id := out["approvalId"].(string)

	ev := ws1.wait("approval.requested")
	ap := ev["approval"].(map[string]any)
	if ap["id"] != id || ap["commitment"] != enc(commit) || ap["device"].(map[string]any)["name"] != "PC di casa" {
		t.Fatalf("requested event: %v", ev)
	}
	list := d1.must(200, "GET", "/v1/approvals", nil)
	if len(list["approvals"].([]any)) != 1 {
		t.Fatalf("open approvals: %v", list)
	}
	// Steps out of order are refused.
	if code, _ := d2.req("POST", "/v1/approvals/"+id+"/reveal", map[string]any{"nonce": enc(rnd(32))}); code != 409 {
		t.Fatalf("reveal before respond: %d", code)
	}
	pk1, n1 := rnd(32), rnd(32)
	d1.must(200, "POST", "/v1/approvals/"+id+"/respond", map[string]any{"publicKey": enc(pk1), "nonce": enc(n1)})
	ev = ws2.wait("approval.responded")
	if ev["approval"].(map[string]any)["responderNonce"] != enc(n1) {
		t.Fatalf("responded event: %v", ev)
	}
	n2 := rnd(32)
	d2.must(200, "POST", "/v1/approvals/"+id+"/reveal", map[string]any{"nonce": enc(n2)})
	ev = ws1.wait("approval.revealed")
	if ev["approval"].(map[string]any)["revealedNonce"] != enc(n2) || ev["approval"].(map[string]any)["box"] != nil {
		t.Fatalf("revealed event: %v", ev)
	}
	box, boxNonce := rnd(120), rnd(24)
	d1.must(200, "POST", "/v1/approvals/"+id+"/approve", map[string]any{"box": enc(box), "boxNonce": enc(boxNonce)})
	ev = ws2.wait("approval.approved")
	if ev["approval"].(map[string]any)["box"] != enc(box) {
		t.Fatalf("approved event: %v", ev)
	}
	// The box is visible only to the requesting device.
	if got := d1.must(200, "GET", "/v1/approvals/"+id, nil); got["box"] != nil {
		t.Fatalf("box leaked to approver: %v", got)
	}
	if got := d2.must(200, "GET", "/v1/approvals/"+id, nil); got["box"] != enc(box) || got["state"] != "approved" {
		t.Fatalf("approval for d2: %v", got)
	}
	d2.must(200, "GET", "/v1/records", nil)
	// After approval the WS of d2 receives active events.
	d1.must(200, "PUT", "/v1/records/"+newID(), map[string]any{"baseRev": 0, "data": enc(rnd(40))})
	ws2.wait("records.changed")
	// New-device alert email.
	time.Sleep(100 * time.Millisecond)
	found := false
	for _, m := range e.mail.Sent() {
		if strings.Contains(m.Subject, "Nuovo dispositivo") || strings.Contains(m.Subject, "New device") {
			found = true
		}
	}
	if !found {
		t.Fatal("no new-device alert email")
	}
	devs := d1.must(200, "GET", "/v1/devices", nil)["devices"].([]any)
	if len(devs) != 2 {
		t.Fatalf("devices: %v", devs)
	}
}

func TestApprovalRejectionsPauseRequests(t *testing.T) {
	e := newEnv(t)
	d1 := e.firstDevice()
	d2, _ := e.login("Intruso", "linux")
	for i := 0; i < 3; i++ {
		id := d2.must(201, "POST", "/v1/approvals", map[string]any{"commitment": enc(rnd(32))})["approvalId"].(string)
		d1.must(200, "POST", "/v1/approvals/"+id+"/reject", nil)
		if got := d2.must(200, "GET", "/v1/approvals/"+id, nil); got["state"] != "rejected" {
			t.Fatalf("state after reject: %v", got)
		}
	}
	if code, out := d2.req("POST", "/v1/approvals", map[string]any{"commitment": enc(rnd(32))}); code != 429 {
		t.Fatalf("requests must be paused: %d %v", code, out)
	}
}

func TestApprovalExpiryAndClaim(t *testing.T) {
	e := newEnv(t)
	d1 := e.firstDevice()
	d1b, _ := e.login("Second active", "macos")
	// Activate d1b via the store to have two active devices.
	e.srv.Store.ActivateDevice(context.Background(), d1b.id)
	wsB := d1b.ws()
	d2, _ := e.login("New", "windows")
	id := d2.must(201, "POST", "/v1/approvals", map[string]any{"commitment": enc(rnd(32))})["approvalId"].(string)
	wsB.wait("approval.requested")
	d1.must(200, "POST", "/v1/approvals/"+id+"/respond", map[string]any{"publicKey": enc(rnd(32)), "nonce": enc(rnd(32))})
	if ev := wsB.wait("approval.closed"); ev["state"] != "claimed" {
		t.Fatalf("claimed: %v", ev)
	}
	if code, _ := d1b.req("POST", "/v1/approvals/"+id+"/respond", map[string]any{"publicKey": enc(rnd(32)), "nonce": enc(rnd(32))}); code != 409 {
		t.Fatalf("second responder: %d", code)
	}
	// Expire it.
	old := store.NowMillis
	defer func() { store.NowMillis = old }()
	base := old()
	store.NowMillis = func() int64 { return base + 11*60_000 }
	e.srv.MaintenanceOnce(context.Background())
	if got := d2.must(200, "GET", "/v1/approvals/"+id, nil); got["state"] != "expired" {
		t.Fatalf("expected expired: %v", got)
	}
}

func TestRecoveryActivation(t *testing.T) {
	e := newEnv(t)
	d1, _ := e.login("Mac", "macos")
	body := recoveryBody()
	auth := body["recoveryAuth"].(string)
	d1.must(200, "POST", "/v1/vault/init", body)
	d2, _ := e.login("Nuovo Mac", "macos")
	rec := d2.must(200, "GET", "/v1/recovery", nil)
	if rec["wrap"] != body["recovery"].(map[string]any)["wrap"] {
		t.Fatalf("recovery bundle: %v", rec)
	}
	if code, out := d2.req("POST", "/v1/recovery/activate", map[string]any{"recoveryAuth": enc(rnd(32))}); code != 422 || errCode(out) != "recovery_invalid" {
		t.Fatalf("wrong recovery: %d %v", code, out)
	}
	d2.must(200, "POST", "/v1/recovery/activate", map[string]any{"recoveryAuth": auth})
	d2.must(200, "GET", "/v1/records", nil)
	// Replace the kit: the old code stops working.
	newBody := recoveryBody()
	d2.must(200, "PUT", "/v1/recovery", map[string]any{"recovery": newBody["recovery"], "recoveryAuth": newBody["recoveryAuth"]})
	d3, _ := e.login("Terzo", "windows")
	if code, _ := d3.req("POST", "/v1/recovery/activate", map[string]any{"recoveryAuth": auth}); code != 422 {
		t.Fatalf("old code must not work: %d", code)
	}
	// Brute force is limited.
	for i := 0; i < 3; i++ {
		d3.req("POST", "/v1/recovery/activate", map[string]any{"recoveryAuth": enc(rnd(32))})
	}
	if code, _ := d3.req("POST", "/v1/recovery/activate", map[string]any{"recoveryAuth": newBody["recoveryAuth"]}); code != 429 {
		t.Fatalf("recovery attempts must be limited: %d", code)
	}
}

func TestRecordsSyncConflictsAndRealtime(t *testing.T) {
	e := newEnv(t)
	d1 := e.firstDevice()
	d2, _ := e.login("PC", "windows")
	e.srv.Store.ActivateDevice(context.Background(), d2.id)
	ws2 := d2.ws()

	id := newID()
	data1 := rnd(100)
	out := d1.must(200, "PUT", "/v1/records/"+id, map[string]any{"baseRev": 0, "data": enc(data1)})
	rev1 := int64(out["rev"].(float64))
	ev := ws2.wait("records.changed")
	if int64(ev["latest"].(float64)) != rev1 || ev["by"] != d1.id {
		t.Fatalf("records.changed: %v", ev)
	}
	got := d2.must(200, "GET", "/v1/records?since=0", nil)
	recs := got["records"].([]any)
	if len(recs) != 1 || recs[0].(map[string]any)["data"] != enc(data1) || int64(got["latest"].(float64)) != rev1 {
		t.Fatalf("pull: %v", got)
	}
	// Concurrent edit from a stale base → conflict with the current version.
	d2.must(200, "PUT", "/v1/records/"+id, map[string]any{"baseRev": rev1, "data": enc(rnd(50))})
	code, cout := d1.req("PUT", "/v1/records/"+id, map[string]any{"baseRev": rev1, "data": enc(rnd(50))})
	if code != 409 || errCode(cout) != "conflict" || cout["current"].(map[string]any)["rev"].(float64) <= float64(rev1) {
		t.Fatalf("conflict: %d %v", code, cout)
	}
	cur := int64(cout["current"].(map[string]any)["rev"].(float64))
	// Permanent delete with the right base.
	if code, _ := d1.req("DELETE", "/v1/records/"+id+"?baseRev=1", nil); code != 409 {
		t.Fatalf("stale delete: %d", code)
	}
	d1.must(200, "DELETE", fmt.Sprintf("/v1/records/%s?baseRev=%d", id, cur), nil)
	got = d2.must(200, "GET", fmt.Sprintf("/v1/records?since=%d", cur), nil)
	tomb := got["records"].([]any)[0].(map[string]any)
	if tomb["deleted"] != true || tomb["data"] != nil {
		t.Fatalf("tombstone: %v", tomb)
	}
	// Validation.
	if code, _ := d1.req("PUT", "/v1/records/not-a-uuid", map[string]any{"baseRev": 0, "data": enc(rnd(4))}); code != 400 {
		t.Fatalf("bad id: %d", code)
	}
	if code, _ := d1.req("PUT", "/v1/records/"+newID(), map[string]any{"data": enc(rnd(4))}); code != 400 {
		t.Fatalf("missing baseRev: %d", code)
	}
	if code, out := d1.req("PUT", "/v1/records/"+newID(), map[string]any{"baseRev": 0, "data": enc(rnd(4)), "blobs": []string{newID()}}); code != 422 || errCode(out) != "missing_blob" {
		t.Fatalf("missing blob: %d %v", code, out)
	}
}

func (c *client) uploadPart(blobID string, n int, data []byte) int {
	c.e.t.Helper()
	r, _ := http.NewRequest("PUT", fmt.Sprintf("%s/v1/blobs/%s/parts/%d", c.e.ts.URL, blobID, n), bytes.NewReader(data))
	r.Header.Set("Authorization", "Bearer "+c.token)
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		c.e.t.Fatal(err)
	}
	resp.Body.Close()
	return resp.StatusCode
}

func TestBlobUploadResumeDownloadAndGC(t *testing.T) {
	e := newEnv(t)
	d1 := e.firstDevice()
	blob := rnd(2500) // 3 parts of 1024 bytes in tests
	sum := sha256.Sum256(blob)
	id := newID()
	out := d1.must(201, "POST", "/v1/blobs/"+id, map[string]any{"size": len(blob)})
	if out["partSize"].(float64) != 1024 {
		t.Fatalf("part size: %v", out)
	}
	if st := d1.uploadPart(id, 0, blob[:1024]); st != 204 {
		t.Fatalf("part 0: %d", st)
	}
	if st := d1.uploadPart(id, 1, blob[1024:1500]); st != 400 {
		t.Fatalf("short part must be refused: %d", st)
	}
	// Resume: the server reports which parts it has.
	out = d1.must(200, "POST", "/v1/blobs/"+id, map[string]any{"size": len(blob)})
	if parts := out["receivedParts"].([]any); len(parts) != 1 || parts[0].(float64) != 0 {
		t.Fatalf("resume info: %v", out)
	}
	if code, out := d1.req("POST", "/v1/blobs/"+id+"/complete", map[string]any{"parts": 3}); code != 422 {
		t.Fatalf("incomplete upload: %d %v", code, out)
	}
	d1.uploadPart(id, 1, blob[1024:2048])
	d1.uploadPart(id, 2, blob[2048:])
	d1.must(200, "POST", "/v1/blobs/"+id+"/complete", map[string]any{"parts": 3, "sha256": hex.EncodeToString(sum[:])})

	// Download, also with a range.
	r, _ := http.NewRequest("GET", e.ts.URL+"/v1/blobs/"+id, nil)
	r.Header.Set("Authorization", "Bearer "+d1.token)
	resp, _ := http.DefaultClient.Do(r)
	got, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !bytes.Equal(got, blob) {
		t.Fatalf("downloaded blob differs (%d bytes)", len(got))
	}
	r.Header.Set("Range", "bytes=2000-")
	resp, _ = http.DefaultClient.Do(r)
	got, _ = io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 206 || !bytes.Equal(got, blob[2000:]) {
		t.Fatalf("range download: %d %d bytes", resp.StatusCode, len(got))
	}

	// Too large.
	if code, out := d1.req("POST", "/v1/blobs/"+newID(), map[string]any{"size": e.srv.Cfg.MaxBlobBytes + 1}); code != 413 {
		t.Fatalf("too large: %d %v", code, out)
	}

	// Referenced by a record, then dereferenced and garbage-collected after the grace period.
	rid := newID()
	rev := int64(d1.must(200, "PUT", "/v1/records/"+rid, map[string]any{"baseRev": 0, "data": enc(rnd(10)), "blobs": []string{id}})["rev"].(float64))
	got2 := d1.must(200, "GET", "/v1/records", nil)["records"].([]any)[0].(map[string]any)
	if b := got2["blobs"].([]any); len(b) != 1 || b[0] != id {
		t.Fatalf("record blobs: %v", got2)
	}
	d1.must(200, "PUT", "/v1/records/"+rid, map[string]any{"baseRev": rev, "data": enc(rnd(10))})
	e.srv.MaintenanceOnce(context.Background())
	if code := d1.status("GET", "/v1/blobs/"+id); code != 200 {
		t.Fatalf("blob must survive during the grace period: %d", code)
	}
	old := store.NowMillis
	defer func() { store.NowMillis = old }()
	base := old()
	store.NowMillis = func() int64 { return base + 25*3600_000 }
	e.srv.MaintenanceOnce(context.Background())
	store.NowMillis = old
	if code := d1.status("GET", "/v1/blobs/"+id); code != 404 {
		t.Fatalf("orphan blob must be collected: %d", code)
	}
}

func TestRevokeAndSignOut(t *testing.T) {
	e := newEnv(t)
	d1 := e.firstDevice()
	d2, _ := e.login("Vecchio PC", "windows")
	e.srv.Store.ActivateDevice(context.Background(), d2.id)
	ws2 := d2.ws()
	ws1 := d1.ws()
	if code, _ := d1.req("DELETE", "/v1/devices/"+d1.id, nil); code != 400 {
		t.Fatalf("self revoke via id: %d", code)
	}
	d1.must(204, "DELETE", "/v1/devices/"+d2.id, nil)
	ws2.wait("device.revoked")
	select {
	case <-ws2.closed:
	case <-time.After(3 * time.Second):
		t.Fatal("revoked device socket not closed")
	}
	ws1.wait("devices.changed")
	if code, _ := d2.req("GET", "/v1/me", nil); code != 401 {
		t.Fatalf("revoked token must be rejected: %d", code)
	}
	d1.must(200, "PATCH", "/v1/devices/self", map[string]any{"name": "Mac mini di Simone"})
	devs := d1.must(200, "GET", "/v1/devices", nil)["devices"].([]any)
	if len(devs) != 1 || devs[0].(map[string]any)["name"] != "Mac mini di Simone" || devs[0].(map[string]any)["current"] != true {
		t.Fatalf("devices: %v", devs)
	}
	d1.must(204, "DELETE", "/v1/devices/self", nil)
	if code, _ := d1.req("GET", "/v1/me", nil); code != 401 {
		t.Fatalf("signed-out token must be rejected: %d", code)
	}
}
