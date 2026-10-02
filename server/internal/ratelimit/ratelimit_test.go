package ratelimit

import (
	"testing"
	"time"
)

func TestSlidingWindow(t *testing.T) {
	now := time.Unix(1000, 0)
	l := New(2, time.Minute)
	l.SetClock(func() time.Time { return now })
	if ok, _ := l.Allow("k"); !ok {
		t.Fatal("1st")
	}
	if ok, _ := l.Allow("k"); !ok {
		t.Fatal("2nd")
	}
	ok, wait := l.Allow("k")
	if ok || wait != time.Minute {
		t.Fatalf("3rd must be refused with 1m wait, got %v %v", ok, wait)
	}
	if ok, _ := l.Allow("other"); !ok {
		t.Fatal("keys are independent")
	}
	now = now.Add(61 * time.Second)
	if ok, _ := l.Peek("k"); !ok {
		t.Fatal("window must slide")
	}
}
