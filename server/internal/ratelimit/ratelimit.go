// Package ratelimit implements simple in-memory sliding-window limits.
package ratelimit

import (
	"sync"
	"time"
)

type Limiter struct {
	mu     sync.Mutex
	limit  int
	window time.Duration
	events map[string][]time.Time
	now    func() time.Time
}

func New(limit int, window time.Duration) *Limiter {
	return &Limiter{limit: limit, window: window, events: map[string][]time.Time{}, now: time.Now}
}

// Allow records an event for key and reports whether it is within the limit.
// When it is not, it returns how long to wait.
func (l *Limiter) Allow(key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	ev := l.prune(key, now)
	if len(ev) >= l.limit {
		return false, ev[0].Add(l.window).Sub(now)
	}
	l.events[key] = append(ev, now)
	if len(l.events) > 10000 {
		l.gc(now)
	}
	return true, 0
}

// Peek reports whether one more event would be allowed, without recording it.
func (l *Limiter) Peek(key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	ev := l.prune(key, now)
	if len(ev) >= l.limit {
		return false, ev[0].Add(l.window).Sub(now)
	}
	return true, 0
}

func (l *Limiter) prune(key string, now time.Time) []time.Time {
	ev := l.events[key]
	i := 0
	for i < len(ev) && now.Sub(ev[i]) >= l.window {
		i++
	}
	ev = ev[i:]
	if len(ev) == 0 {
		delete(l.events, key)
	} else {
		l.events[key] = ev
	}
	return ev
}

func (l *Limiter) gc(now time.Time) {
	for k := range l.events {
		l.prune(k, now)
	}
}

// SetClock replaces the clock (tests).
func (l *Limiter) SetClock(f func() time.Time) { l.mu.Lock(); l.now = f; l.mu.Unlock() }
