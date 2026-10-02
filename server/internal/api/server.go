// Package api implements the HTTP + WebSocket API of the server (see docs/PROTOCOL.md).
package api

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/simonescoca/the.vault/server/internal/blobs"
	"github.com/simonescoca/the.vault/server/internal/config"
	"github.com/simonescoca/the.vault/server/internal/hub"
	"github.com/simonescoca/the.vault/server/internal/mail"
	"github.com/simonescoca/the.vault/server/internal/ratelimit"
	"github.com/simonescoca/the.vault/server/internal/store"
)

const (
	DefaultPartSize = 4 << 20 // blob upload part size
	maxJSONBody     = 1 << 20
	maxRecordBody   = 2 << 20
	maxRecordData   = 1 << 20
	otpTTL          = 10 * time.Minute
	otpMaxAttempts  = 5
	otpResendDelay  = 30 * time.Second
	approvalTTL     = 10 * time.Minute
	blobGracePeriod = 24 * time.Hour
)

type Server struct {
	Cfg     *config.Config
	Store   *store.Store
	Hub     *hub.Hub
	Mail    mail.Sender
	Files   *blobs.Files
	Log     *slog.Logger
	Version string
	// PartSize is the blob upload part size (smaller in tests).
	PartSize int64

	otpPerEmail     *ratelimit.Limiter
	otpPerIP        *ratelimit.Limiter
	verifyPerIP     *ratelimit.Limiter
	recoveryPerUser *ratelimit.Limiter
}

func New(cfg *config.Config, st *store.Store, sender mail.Sender, log *slog.Logger, version string) *Server {
	if cfg.TestMode {
		log.Warn("TEST MODE: login code limits are disabled")
	}
	return &Server{
		Cfg:             cfg,
		Store:           st,
		Hub:             hub.New(),
		Mail:            sender,
		Files:           &blobs.Files{Dir: cfg.DataDir},
		Log:             log,
		Version:         version,
		PartSize:        DefaultPartSize,
		otpPerEmail:     ratelimit.New(5, time.Hour),
		otpPerIP:        ratelimit.New(30, time.Hour),
		verifyPerIP:     ratelimit.New(60, time.Hour),
		recoveryPerUser: ratelimit.New(5, time.Hour),
	}
}

// Handler returns the HTTP handler with all routes and middleware.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	any := []string{store.StatusSetup, store.StatusPending, store.StatusActive}
	active := []string{store.StatusActive}
	pending := []string{store.StatusPending}

	mux.HandleFunc("GET /v1/health", s.health)
	mux.HandleFunc("POST /v1/auth/otp/request", s.otpRequest)
	mux.HandleFunc("POST /v1/auth/otp/verify", s.otpVerify)
	mux.Handle("GET /v1/me", s.auth(any, s.me))
	mux.Handle("POST /v1/vault/init", s.auth([]string{store.StatusSetup}, s.vaultInit))

	mux.Handle("GET /v1/devices", s.auth(active, s.listDevices))
	mux.Handle("PATCH /v1/devices/self", s.auth(any, s.renameSelf))
	mux.Handle("DELETE /v1/devices/self", s.auth(any, s.deleteSelf))
	mux.Handle("DELETE /v1/devices/{id}", s.auth(active, s.revokeDevice))

	mux.Handle("POST /v1/approvals", s.auth(pending, s.createApproval))
	mux.Handle("GET /v1/approvals", s.auth(active, s.listApprovals))
	mux.Handle("GET /v1/approvals/{id}", s.auth([]string{store.StatusPending, store.StatusActive}, s.getApproval))
	mux.Handle("DELETE /v1/approvals/{id}", s.auth(pending, s.cancelApproval))
	mux.Handle("POST /v1/approvals/{id}/reveal", s.auth(pending, s.revealApproval))
	mux.Handle("POST /v1/approvals/{id}/respond", s.auth(active, s.respondApproval))
	mux.Handle("POST /v1/approvals/{id}/approve", s.auth(active, s.approveApproval))
	mux.Handle("POST /v1/approvals/{id}/reject", s.auth(active, s.rejectApproval))

	mux.Handle("GET /v1/recovery", s.auth(pending, s.getRecovery))
	mux.Handle("POST /v1/recovery/activate", s.auth(pending, s.activateRecovery))
	mux.Handle("PUT /v1/recovery", s.auth(active, s.putRecovery))

	mux.Handle("GET /v1/records", s.auth(active, s.listRecords))
	mux.Handle("PUT /v1/records/{id}", s.auth(active, s.putRecord))
	mux.Handle("DELETE /v1/records/{id}", s.auth(active, s.deleteRecord))

	mux.Handle("POST /v1/blobs/{id}", s.auth(active, s.startBlob))
	mux.Handle("PUT /v1/blobs/{id}/parts/{n}", s.auth(active, s.putBlobPart))
	mux.Handle("POST /v1/blobs/{id}/complete", s.auth(active, s.completeBlob))
	mux.Handle("GET /v1/blobs/{id}", s.auth(active, s.getBlob))

	mux.Handle("GET /v1/ws", s.auth([]string{store.StatusPending, store.StatusActive}, s.websocket))

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusNotFound, "not_found", "no such endpoint")
	})
	return s.middleware(mux)
}

// --- middleware ---

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) { r.status = code; r.ResponseWriter.WriteHeader(code) }

// Unwrap lets http.ResponseController and the WebSocket upgrade reach the underlying writer.
func (r *statusRecorder) Unwrap() http.ResponseWriter { return r.ResponseWriter }

func (s *Server) middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		h := w.Header()
		h.Set("X-TheVault-Server", s.Version)
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Cache-Control", "no-store")
		h.Set("Referrer-Policy", "no-referrer")
		rec := &statusRecorder{ResponseWriter: w, status: 200}
		defer func() {
			if v := recover(); v != nil {
				s.Log.Error("panic", "path", r.URL.Path, "error", fmt.Sprint(v))
				writeError(rec, http.StatusInternalServerError, "internal", "internal error")
			}
			level := slog.LevelDebug
			if rec.status >= 500 {
				level = slog.LevelError
			} else if rec.status >= 400 && rec.status != 404 {
				level = slog.LevelInfo
			}
			s.Log.Log(r.Context(), level, "request", "method", r.Method, "path", r.URL.Path, "status", rec.status,
				"ms", time.Since(start).Milliseconds())
		}()
		next.ServeHTTP(rec, r)
	})
}

type ctxKey int

const deviceKey ctxKey = 1

// auth authenticates the bearer token and checks the device status.
func (s *Server) auth(statuses []string, h http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tok, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		raw, err := decodeB64(strings.TrimSpace(tok))
		if !ok || err != nil || len(raw) != 32 {
			writeError(w, http.StatusUnauthorized, "unauthorized", "missing or invalid token")
			return
		}
		sum := sha256.Sum256(raw)
		dev, err := s.Store.DeviceByTokenHash(r.Context(), sum[:])
		if errors.Is(err, store.ErrNotFound) {
			writeError(w, http.StatusUnauthorized, "unauthorized", "unknown or revoked device")
			return
		}
		if err != nil {
			s.internal(w, err)
			return
		}
		allowed := false
		for _, st := range statuses {
			if dev.Status == st {
				allowed = true
			}
		}
		if !allowed {
			writeError(w, http.StatusForbidden, "forbidden", "not allowed for a device in status "+dev.Status)
			return
		}
		_ = s.Store.TouchDevice(r.Context(), dev.ID)
		h(w, r.WithContext(context.WithValue(r.Context(), deviceKey, dev)))
	})
}

func device(r *http.Request) *store.Device { return r.Context().Value(deviceKey).(*store.Device) }

// clientIP returns the caller address. Behind a local reverse proxy (Tailscale Funnel) the last
// X-Forwarded-For entry is the one the proxy added.
func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	if ip := net.ParseIP(host); ip != nil && ip.IsLoopback() {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			parts := strings.Split(xff, ",")
			return strings.TrimSpace(parts[len(parts)-1])
		}
	}
	return host
}

// --- helpers ---

type apiError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, code, msg string, extra ...map[string]any) {
	body := map[string]any{"error": apiError{Code: code, Message: msg}}
	for _, e := range extra {
		for k, v := range e {
			body[k] = v
		}
	}
	writeJSON(w, status, body)
}

func (s *Server) internal(w http.ResponseWriter, err error) {
	s.Log.Error("internal error", "error", err)
	writeError(w, http.StatusInternalServerError, "internal", "internal error")
}

func tooMany(w http.ResponseWriter, wait time.Duration) {
	secs := int(wait.Seconds() + 0.999)
	if secs < 1 {
		secs = 1
	}
	w.Header().Set("Retry-After", strconv.Itoa(secs))
	writeError(w, http.StatusTooManyRequests, "rate_limited", "too many requests, retry later",
		map[string]any{"retryAfter": secs})
}

func decodeJSON(w http.ResponseWriter, r *http.Request, limit int64, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	dec := json.NewDecoder(r.Body)
	if err := dec.Decode(v); err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			writeError(w, http.StatusRequestEntityTooLarge, "too_large", "request body too large")
		} else {
			writeError(w, http.StatusBadRequest, "bad_request", "invalid JSON body")
		}
		return false
	}
	return true
}

func b64(b []byte) string {
	if b == nil {
		return ""
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

func b64OrNil(b []byte) any {
	if b == nil {
		return nil
	}
	return b64(b)
}

// decodeB64 accepts base64url with or without padding.
func decodeB64(s string) ([]byte, error) {
	return base64.RawURLEncoding.DecodeString(strings.TrimRight(s, "="))
}

// decodeField decodes a base64 field of an exact (or maximum, when exact is false) length.
func decodeField(w http.ResponseWriter, name, value string, n int, exact bool) ([]byte, bool) {
	b, err := decodeB64(value)
	if err != nil || (exact && len(b) != n) || (!exact && (len(b) == 0 || len(b) > n)) {
		writeError(w, http.StatusBadRequest, "invalid_field", "invalid "+name)
		return nil, false
	}
	return b, true
}

func newID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	h := fmt.Sprintf("%x", b)
	return h[0:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:32]
}

func newToken() ([]byte, string) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return b, b64(b)
}

func nowMs() int64 { return store.NowMillis() }

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"service": "thevault", "version": s.Version, "time": nowMs()})
}

// sendAsync delivers an email in the background (alerts must not slow down requests).
func (s *Server) sendAsync(m mail.Message) {
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
		defer cancel()
		if err := s.Mail.Send(ctx, m); err != nil {
			s.Log.Error("email not sent", "subject", m.Subject, "error", err)
		}
	}()
}
