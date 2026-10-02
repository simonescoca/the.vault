package api

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/simonescoca/the.vault/server/internal/config"
	"github.com/simonescoca/the.vault/server/internal/mail"
	"github.com/simonescoca/the.vault/server/internal/store"
)

var platforms = map[string]bool{"macos": true, "windows": true, "linux": true, "ios": true, "android": true}

func (s *Server) otpMAC(email, code string) []byte {
	m := hmac.New(sha256.New, s.Cfg.Secret())
	m.Write([]byte("thevault/otp/v1\x00" + email + "\x00" + code))
	return m.Sum(nil)
}

func newOTPCode() string {
	n, err := rand.Int(rand.Reader, big.NewInt(1_000_000))
	if err != nil {
		panic(err)
	}
	return fmt.Sprintf("%06d", n.Int64())
}

func (s *Server) otpRequest(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email      string `json:"email"`
		Locale     string `json:"locale"`
		DeviceName string `json:"deviceName"`
	}
	if !decodeJSON(w, r, maxJSONBody, &req) {
		return
	}
	email := config.NormalizeEmail(req.Email)
	if email == "" {
		writeError(w, http.StatusBadRequest, "invalid_email", "invalid email address")
		return
	}
	if ok, wait := s.otpPerIP.Allow(clientIP(r)); !ok {
		tooMany(w, wait)
		return
	}
	if o, err := s.Store.GetOTP(r.Context(), email); err == nil {
		if since := time.Duration(nowMs()-o.SentAt) * time.Millisecond; since < otpResendDelay {
			tooMany(w, otpResendDelay-since)
			return
		}
	}
	if ok, wait := s.otpPerEmail.Allow(email); !ok {
		tooMany(w, wait)
		return
	}
	code := newOTPCode()
	mac := s.otpMAC(email, code)
	allowed := s.Cfg.IsAllowed(email)
	if !allowed {
		// Store an unusable code so that non-allowed emails behave exactly like allowed ones.
		mac = make([]byte, 32)
		rand.Read(mac)
	}
	now := nowMs()
	if err := s.Store.PutOTP(r.Context(), store.OTP{Email: email, CodeMAC: mac, ExpiresAt: now + otpTTL.Milliseconds(), SentAt: now}); err != nil {
		s.internal(w, err)
		return
	}
	if allowed {
		name := strings.TrimSpace(req.DeviceName)
		if utf8.RuneCountInString(name) > 64 {
			name = ""
		}
		ctx, cancel := context.WithTimeout(r.Context(), 45*time.Second)
		defer cancel()
		if err := s.Mail.Send(ctx, mail.OTPMessage(email, code, req.Locale, name)); err != nil {
			s.Log.Error("otp email not sent", "error", err)
			_ = s.Store.DeleteOTP(r.Context(), email)
			writeError(w, http.StatusServiceUnavailable, "mail_failed", "the server could not send the email")
			return
		}
		s.Log.Info("otp sent")
	}
	writeJSON(w, http.StatusAccepted, map[string]any{})
}

type deviceInfo struct {
	Name      string `json:"name"`
	Platform  string `json:"platform"`
	PublicKey string `json:"publicKey"`
}

func (s *Server) otpVerify(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email  string     `json:"email"`
		Code   string     `json:"code"`
		Device deviceInfo `json:"device"`
	}
	if !decodeJSON(w, r, maxJSONBody, &req) {
		return
	}
	if ok, wait := s.verifyPerIP.Allow(clientIP(r)); !ok {
		tooMany(w, wait)
		return
	}
	email := config.NormalizeEmail(req.Email)
	code := strings.ReplaceAll(strings.TrimSpace(req.Code), " ", "")
	name := strings.TrimSpace(req.Device.Name)
	if email == "" || len(code) != 6 || strings.Trim(code, "0123456789") != "" {
		writeError(w, http.StatusBadRequest, "bad_request", "invalid email or code")
		return
	}
	if name == "" || utf8.RuneCountInString(name) > 64 || !platforms[req.Device.Platform] {
		writeError(w, http.StatusBadRequest, "invalid_field", "invalid device name or platform")
		return
	}
	pk, ok := decodeField(w, "device.publicKey", req.Device.PublicKey, 32, true)
	if !ok {
		return
	}
	ctx := r.Context()
	o, err := s.Store.GetOTP(ctx, email)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusGone, "otp_expired", "no valid code: request a new one")
		return
	}
	if err != nil {
		s.internal(w, err)
		return
	}
	if nowMs() > o.ExpiresAt || o.Attempts >= otpMaxAttempts {
		_ = s.Store.DeleteOTP(ctx, email)
		writeError(w, http.StatusGone, "otp_expired", "the code has expired: request a new one")
		return
	}
	if !hmac.Equal(o.CodeMAC, s.otpMAC(email, code)) {
		n, err := s.Store.IncOTPAttempts(ctx, email)
		if err != nil {
			s.internal(w, err)
			return
		}
		left := otpMaxAttempts - n
		if left <= 0 {
			_ = s.Store.DeleteOTP(ctx, email)
			left = 0
		}
		writeError(w, http.StatusUnprocessableEntity, "otp_invalid", "wrong code", map[string]any{"attemptsLeft": left})
		return
	}
	_ = s.Store.DeleteOTP(ctx, email)
	if !s.Cfg.IsAllowed(email) {
		writeError(w, http.StatusUnprocessableEntity, "otp_invalid", "wrong code", map[string]any{"attemptsLeft": 0})
		return
	}
	u, err := s.Store.EnsureUser(ctx, newID(), email)
	if err != nil {
		s.internal(w, err)
		return
	}
	status := store.StatusSetup
	if u.VaultInitialized {
		status = store.StatusPending
	}
	raw, tok := newToken()
	sum := sha256.Sum256(raw)
	d := &store.Device{ID: newID(), UserID: u.ID, Name: name, Platform: req.Device.Platform, PublicKey: pk, Status: status}
	if err := s.Store.CreateDevice(ctx, d, sum[:]); err != nil {
		s.internal(w, err)
		return
	}
	s.Log.Info("device registered", "device", d.ID, "status", status)
	s.Hub.ToActive(u.ID, "", event("devices.changed", nil))
	writeJSON(w, http.StatusOK, map[string]any{"token": tok, "deviceId": d.ID, "userId": u.ID, "status": status})
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	d := device(r)
	u, err := s.Store.User(r.Context(), d.UserID)
	if err != nil {
		s.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"userId": u.ID,
		"email":  u.Email,
		"device": map[string]any{"id": d.ID, "name": d.Name, "platform": d.Platform, "status": d.Status},
		"vault":  map[string]any{"initialized": u.VaultInitialized, "keyCheck": b64OrNil(u.KeyCheck)},
	})
}

type recoveryJSON struct {
	Salt     string `json:"salt"`
	OpsLimit int64  `json:"opsLimit"`
	MemLimit int64  `json:"memLimit"`
	Wrap     string `json:"wrap"`
}

// wrapLen is nonce (24) + AEAD of a 32-byte key (32 + 16).
const wrapLen = 24 + 32 + 16

func parseRecovery(w http.ResponseWriter, rj recoveryJSON, authB64 string) (store.Recovery, bool) {
	var rec store.Recovery
	salt, ok := decodeField(w, "recovery.salt", rj.Salt, 16, true)
	if !ok {
		return rec, false
	}
	wrap, ok := decodeField(w, "recovery.wrap", rj.Wrap, wrapLen, true)
	if !ok {
		return rec, false
	}
	auth, ok := decodeField(w, "recoveryAuth", authB64, 32, true)
	if !ok {
		return rec, false
	}
	if rj.OpsLimit < 1 || rj.OpsLimit > 20 || rj.MemLimit < 8<<20 || rj.MemLimit > 1<<30 {
		writeError(w, http.StatusBadRequest, "invalid_field", "invalid recovery parameters")
		return rec, false
	}
	h := sha256.Sum256(auth)
	return store.Recovery{Salt: salt, OpsLimit: rj.OpsLimit, MemLimit: rj.MemLimit, Wrap: wrap, AuthHash: h[:]}, true
}

func (s *Server) vaultInit(w http.ResponseWriter, r *http.Request) {
	var req struct {
		KeyCheck     string       `json:"keyCheck"`
		Recovery     recoveryJSON `json:"recovery"`
		RecoveryAuth string       `json:"recoveryAuth"`
	}
	if !decodeJSON(w, r, maxJSONBody, &req) {
		return
	}
	kc, ok := decodeField(w, "keyCheck", req.KeyCheck, 16, true)
	if !ok {
		return
	}
	rec, ok := parseRecovery(w, req.Recovery, req.RecoveryAuth)
	if !ok {
		return
	}
	d := device(r)
	err := s.Store.InitVault(r.Context(), d.UserID, d.ID, kc, rec)
	if errors.Is(err, store.ErrAlreadyInitialized) {
		writeError(w, http.StatusConflict, "already_initialized", "the vault was created by another device: approval needed")
		return
	}
	if err != nil {
		s.internal(w, err)
		return
	}
	s.Hub.Activate(d.UserID, d.ID)
	s.Log.Info("vault initialized", "device", d.ID)
	writeJSON(w, http.StatusOK, map[string]any{"status": store.StatusActive})
}
