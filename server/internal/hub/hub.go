// Package hub fans out real-time events to the connected devices of each user.
package hub

import (
	"encoding/json"
	"sync"
)

// Event is a message pushed to devices over the WebSocket.
type Event struct {
	Type string         `json:"type"`
	Data map[string]any `json:"-"`
}

// MarshalJSON flattens Data next to "type".
func (e Event) MarshalJSON() ([]byte, error) {
	m := map[string]any{"type": e.Type}
	for k, v := range e.Data {
		m[k] = v
	}
	return json.Marshal(m)
}

// Conn is one WebSocket connection of a device.
type Conn struct {
	UserID   string
	DeviceID string
	// Send receives encoded events. When it is full the connection is considered too slow and closed:
	// the device reconnects and pulls what it missed.
	Send   chan []byte
	Closed chan struct{}
	once   sync.Once
	mu     sync.Mutex
	active bool
}

func (c *Conn) Close() { c.once.Do(func() { close(c.Closed) }) }

// SetActive updates whether this connection belongs to an active (approved) device.
func (c *Conn) SetActive(v bool) { c.mu.Lock(); c.active = v; c.mu.Unlock() }

func (c *Conn) IsActive() bool { c.mu.Lock(); defer c.mu.Unlock(); return c.active }

type Hub struct {
	mu    sync.Mutex
	conns map[string]map[*Conn]bool // userID → conns
}

func New() *Hub { return &Hub{conns: map[string]map[*Conn]bool{}} }

func (h *Hub) Register(userID, deviceID string, active bool) *Conn {
	c := &Conn{UserID: userID, DeviceID: deviceID, Send: make(chan []byte, 64), Closed: make(chan struct{}), active: active}
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.conns[userID] == nil {
		h.conns[userID] = map[*Conn]bool{}
	}
	h.conns[userID][c] = true
	return c
}

func (h *Hub) Unregister(c *Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if m := h.conns[c.UserID]; m != nil {
		delete(m, c)
		if len(m) == 0 {
			delete(h.conns, c.UserID)
		}
	}
	c.Close()
}

func (h *Hub) deliver(c *Conn, msg []byte) {
	select {
	case c.Send <- msg:
	default:
		c.Close()
	}
}

func (h *Hub) targets(userID string, pick func(*Conn) bool) []*Conn {
	h.mu.Lock()
	defer h.mu.Unlock()
	var out []*Conn
	for c := range h.conns[userID] {
		if pick(c) {
			out = append(out, c)
		}
	}
	return out
}

// ToActive sends an event to every active device of a user, except the one with id `except` (may be "").
func (h *Hub) ToActive(userID, except string, e Event) {
	msg, _ := json.Marshal(e)
	for _, c := range h.targets(userID, func(c *Conn) bool { return c.IsActive() && c.DeviceID != except }) {
		h.deliver(c, msg)
	}
}

// ToDevice sends an event to every connection of one device.
func (h *Hub) ToDevice(userID, deviceID string, e Event) {
	msg, _ := json.Marshal(e)
	for _, c := range h.targets(userID, func(c *Conn) bool { return c.DeviceID == deviceID }) {
		h.deliver(c, msg)
	}
}

// Activate marks the connections of a device as active (after approval).
func (h *Hub) Activate(userID, deviceID string) {
	for _, c := range h.targets(userID, func(c *Conn) bool { return c.DeviceID == deviceID }) {
		c.SetActive(true)
	}
}

// Disconnect sends a final event to a device and closes its connections (revocation).
func (h *Hub) Disconnect(userID, deviceID string, final *Event) {
	var msg []byte
	if final != nil {
		msg, _ = json.Marshal(final)
	}
	for _, c := range h.targets(userID, func(c *Conn) bool { return c.DeviceID == deviceID }) {
		if msg != nil {
			select {
			case c.Send <- msg:
			default:
			}
		}
		c.Close()
	}
}

// Count returns the number of open connections (tests and status).
func (h *Hub) Count() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	n := 0
	for _, m := range h.conns {
		n += len(m)
	}
	return n
}
