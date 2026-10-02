// Command thevault-server is the sync server of The Vault, meant to run on an always-on Mac (the Mac mini).
//
//	thevault-server setup     interactive configuration (Italian) + automatic start
//	thevault-server serve     run the server (used by the background service)
//	thevault-server status    show whether the server is running and reachable
//	thevault-server backup    make a backup now
//	thevault-server upgrade   install this program over the running one (backup first), keeping the settings
//	thevault-server version   print the version
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/simonescoca/the.vault/server/internal/api"
	"github.com/simonescoca/the.vault/server/internal/backup"
	"github.com/simonescoca/the.vault/server/internal/config"
	"github.com/simonescoca/the.vault/server/internal/mail"
	"github.com/simonescoca/the.vault/server/internal/setup"
	"github.com/simonescoca/the.vault/server/internal/store"
)

// version is set at build time with -ldflags "-X main.version=…".
var version = "dev"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	cmd, args := os.Args[1], os.Args[2:]
	fs := flag.NewFlagSet(cmd, flag.ExitOnError)
	dataDir := fs.String("data", config.DefaultDataDir(), "cartella dei dati del server")
	_ = fs.Parse(args)

	var err error
	switch cmd {
	case "serve":
		err = serve(*dataDir)
	case "setup":
		err = setup.Run(*dataDir, version)
	case "status":
		err = setup.Status(*dataDir)
	case "backup":
		err = runBackup(*dataDir)
	case "uninstall":
		err = setup.Uninstall(*dataDir)
	case "upgrade":
		err = upgrade(*dataDir)
	case "version", "--version", "-v":
		fmt.Println("thevault-server", version)
	case "help", "--help", "-h":
		usage()
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "Errore:", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `The Vault — server (%s)

Uso: thevault-server <comando> [--data cartella]

  setup      configurazione guidata e avvio automatico
  serve      avvia il server (lo usa il servizio in background)
  status     mostra se il server è attivo e raggiungibile
  backup     esegue subito un backup
  upgrade    installa questa versione al posto di quella attiva (con backup prima)
  uninstall  rimuove l'avvio automatico (i dati restano)
  version    mostra la versione
`, version)
}

func newLogger(level string) *slog.Logger {
	var l slog.Level
	switch strings.ToLower(level) {
	case "debug":
		l = slog.LevelDebug
	case "warn":
		l = slog.LevelWarn
	case "error":
		l = slog.LevelError
	default:
		l = slog.LevelInfo
	}
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: l}))
}

func serve(dataDir string) error {
	cfg, err := config.Load(dataDir)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("configurazione assente in %s: esegui prima 'thevault-server setup'", dataDir)
		}
		return err
	}
	log := newLogger(cfg.LogLevel)
	st, err := store.Open(filepath.Join(dataDir, "thevault.db"))
	if err != nil {
		return err
	}
	defer st.Close()

	srv := api.New(cfg, st, mail.New(cfg), log, version)
	httpSrv := &http.Server{
		Addr:              cfg.Listen,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go srv.RunMaintenance(ctx, 30*time.Second)
	go backup.RunDaily(ctx, cfg, st, log)

	errCh := make(chan error, 1)
	go func() {
		log.Info("The Vault server started", "version", version, "listen", cfg.Listen, "data", dataDir)
		errCh <- httpSrv.ListenAndServe()
	}()
	select {
	case err := <-errCh:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
	case <-ctx.Done():
		log.Info("shutting down")
		sctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = httpSrv.Shutdown(sctx)
	}
	return nil
}

// exitNotConfigured tells the install script to run the setup instead of an upgrade.
const exitNotConfigured = 3

func upgrade(dataDir string) error {
	cfg, err := config.Load(dataDir)
	if errors.Is(err, os.ErrNotExist) {
		fmt.Fprintln(os.Stderr, "Il server non è ancora configurato: esegui 'thevault-server setup'.")
		os.Exit(exitNotConfigured)
	}
	if err != nil {
		return err
	}
	fmt.Println("Backup di sicurezza prima dell'aggiornamento…")
	if err := runBackup(dataDir); err != nil {
		return fmt.Errorf("backup non riuscito, aggiornamento annullato: %w", err)
	}
	fmt.Printf("Installo la versione %s…\n", version)
	if err := setup.Upgrade(cfg, version); err != nil {
		return err
	}
	fmt.Printf("✓ Server aggiornato alla versione %s e di nuovo attivo.\n", version)
	return nil
}

func runBackup(dataDir string) error {
	cfg, err := config.Load(dataDir)
	if err != nil {
		return err
	}
	st, err := store.Open(filepath.Join(dataDir, "thevault.db"))
	if err != nil {
		return err
	}
	defer st.Close()
	dir, err := backup.RunAndRecord(context.Background(), cfg, st)
	if err != nil {
		return err
	}
	fmt.Println("Backup completato:", dir)
	return nil
}
