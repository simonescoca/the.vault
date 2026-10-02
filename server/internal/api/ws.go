package api

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/coder/websocket"

	"github.com/simonescoca/the.vault/server/internal/store"
)

const (
	wsPingEvery  = 25 * time.Second
	wsWriteLimit = 10 * time.Second
)

// websocket upgrades the connection and streams events to the device until it disconnects.
func (s *Server) websocket(w http.ResponseWriter, r *http.Request) {
	me := device(r)
	c, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		// Native apps authenticate with a bearer token, not cookies: no cross-site risk.
		InsecureSkipVerify: true,
	})
	if err != nil {
		return
	}
	c.SetReadLimit(4096)
	conn := s.Hub.Register(me.UserID, me.ID, me.Status == store.StatusActive)
	defer s.Hub.Unregister(conn)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Reader: we do not expect messages, but reading processes control frames and detects closure.
	go func() {
		defer cancel()
		for {
			if _, _, err := c.Read(ctx); err != nil {
				return
			}
		}
	}()

	latest, _ := s.Store.LatestRev(ctx, me.UserID)
	hello, _ := json.Marshal(event("hello", map[string]any{"latest": latest, "status": me.Status}))
	if !write(ctx, c, hello) {
		return
	}
	ping := time.NewTicker(wsPingEvery)
	defer ping.Stop()
	for {
		select {
		case msg := <-conn.Send:
			if !write(ctx, c, msg) {
				return
			}
		case <-conn.Closed:
			// Flush what is queued (e.g. device.revoked), then close.
			for {
				select {
				case msg := <-conn.Send:
					if !write(ctx, c, msg) {
						return
					}
				default:
					c.Close(websocket.StatusNormalClosure, "closed by server")
					return
				}
			}
		case <-ping.C:
			pctx, pcancel := context.WithTimeout(ctx, wsWriteLimit)
			err := c.Ping(pctx)
			pcancel()
			if err != nil {
				return
			}
		case <-ctx.Done():
			c.Close(websocket.StatusNormalClosure, "")
			return
		}
	}
}

func write(ctx context.Context, c *websocket.Conn, msg []byte) bool {
	wctx, cancel := context.WithTimeout(ctx, wsWriteLimit)
	defer cancel()
	return c.Write(wctx, websocket.MessageText, msg) == nil
}
