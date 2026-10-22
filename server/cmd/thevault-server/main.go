// Command thevault-server is the sync server of The Vault, meant to run on an always-on Mac (the Mac mini)
// or Linux computer (for example an NVIDIA Jetson).
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
	"runtime"
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
		if runtime.GOOS == "linux" && os.Geteuid() == 0 {
			// As root it would look for the service of root, and leave the real one running.
			err = errors.New("esegui il comando con il tuo utente, senza sudo")
			break
		}
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
	// Made before installing anything: runBackup copies the database as it is, without migrating it.
	if _, err := os.Stat(filepath.Join(dataDir, "thevault.db")); err == nil {
		fmt.Println("Backup di sicurezza prima dell'aggiornamento…")
		if err := runBackup(dataDir); err != nil {
			return fmt.Errorf("backup non riuscito, aggiornamento annullato: %w", err)
		}
	} else {
		fmt.Println("Ancora nessun dato sul server: niente backup prima dell'aggiornamento.")
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
	// A backup copies the database as it is: the schema is migrated only by the server that will use it
	// (before an upgrade this is the new program, and the old server is still running).
	st, err := store.OpenNoMigrate(filepath.Join(dataDir, "thevault.db"))
	if err != nil {
		return err
	}
	defer st.Close()
	dir, err := backup.RunAndRecord(context.Background(), cfg, st)
	if err != nil {
		return err
	}
	fmt.Println("Backup completato:", dir)
	if n := backup.ReadStatus(cfg).MissingBlobs; n > 0 {
		fmt.Printf("⚠ Sul server mancano %d allegati: le loro copie nei backup restano (elenco in %s).\n", n,
			filepath.Join(dir, "manifest.json"))
	}
	return nil
}
