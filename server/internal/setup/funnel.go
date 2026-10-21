package setup

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/simonescoca/the.vault/server/internal/backup"
	"github.com/simonescoca/the.vault/server/internal/config"
)

// tailscaleCLI finds the Tailscale command line tool (on Linux, or a Homebrew/CLI install, it is in the PATH;
// otherwise the Mac app).
func tailscaleCLI() string {
	if p, err := exec.LookPath("tailscale"); err == nil {
		return p
	}
	for _, p := range []string{
		"/Applications/Tailscale.app/Contents/MacOS/Tailscale",
		"/opt/homebrew/bin/tailscale",
		"/usr/local/bin/tailscale",
	} {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

type tsStatus struct {
	BackendState string `json:"BackendState"`
	Self         struct {
		DNSName string `json:"DNSName"`
	} `json:"Self"`
}

func tailscaleStatus(cli string) (*tsStatus, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, cli, "status", "--json").Output()
	if err != nil && len(out) == 0 {
		return nil, err
	}
	var st tsStatus
	if err := json.Unmarshal(out, &st); err != nil {
		return nil, err
	}
	return &st, nil
}

// PublicHost returns the Funnel host name (without scheme) of this computer, if Tailscale is running.
func PublicHost() string {
	cli := tailscaleCLI()
	if cli == "" {
		return ""
	}
	st, err := tailscaleStatus(cli)
	if err != nil || st.BackendState != "Running" {
		return ""
	}
	return strings.TrimSuffix(st.Self.DNSName, ".")
}

// runFunnel runs a Tailscale command, showing its output (it may contain the link to enable Funnel).
func (w *Wizard) runFunnel(args []string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, args[0], args[1:]...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, w.Out, w.Out
	return cmd.Run()
}

func setupFunnel(w *Wizard, cfg *config.Config) error {
	if w.linux() {
		w.say("     Per usare The Vault fuori casa questo computer deve essere raggiungibile da internet in modo sicuro.")
	} else {
		w.say("     Per usare The Vault fuori casa il Mac mini deve essere raggiungibile da internet in modo sicuro.")
	}
	w.say("     Usiamo Tailscale Funnel: gratuito, HTTPS automatico, nessuna modifica al router.")
	for {
		cli := tailscaleCLI()
		if cli == "" {
			w.say("")
			w.say("     Tailscale non è installato. Fai così:")
			if w.linux() {
				w.say("       1. In un altro terminale installalo:  curl -fsSL https://tailscale.com/install.sh | sh")
				w.say("       2. Collegalo al tuo account:  sudo tailscale up")
				w.say("          e apri nel browser il link che compare (va bene il tuo account Apple, Google o Microsoft).")
				w.say("          Da allora Tailscale parte da solo a ogni accensione.")
			} else {
				w.say("       1. Scarica e installa Tailscale per Mac: https://tailscale.com/download/mac")
				w.say("       2. Aprilo e accedi (va bene il tuo account Apple, Google o Microsoft).")
				w.say("       3. Nel menu di Tailscale attiva «Launch at login» (avvio all'accesso).")
			}
			again, err := w.askYesNo("     Fatto? Riprovo adesso?", true)
			if err != nil {
				return err
			}
			if !again {
				return errors.New("accesso da fuori casa non configurato: riesegui 'thevault-server setup' quando Tailscale è installato")
			}
			continue
		}
		st, err := tailscaleStatus(cli)
		if err != nil || st.BackendState != "Running" || st.Self.DNSName == "" {
			if w.linux() {
				w.say("     Tailscale è installato ma non è collegato: in un altro terminale esegui  sudo tailscale up")
				w.say("     e apri nel browser il link che compare.")
			} else {
				w.say("     Tailscale è installato ma non è collegato: aprilo e accedi al tuo account.")
			}
			again, err := w.askYesNo("     Fatto? Riprovo adesso?", true)
			if err != nil {
				return err
			}
			if !again {
				return errors.New("Tailscale non collegato: riesegui 'thevault-server setup' più tardi")
			}
			continue
		}
		_, port, err := net.SplitHostPort(cfg.Listen)
		if err != nil {
			return err
		}
		w.say("     Attivo Tailscale Funnel… Se compare un link, aprilo nel browser e conferma: è la")
		w.say("     richiesta di Tailscale di abilitare Funnel sul tuo account (si fa una volta sola).")
		var sudo []string
		if w.linux() && os.Geteuid() != 0 {
			// On Linux only root (or the Tailscale "operator") may change what Tailscale publishes.
			w.say("     Se richiesta, inserisci la password di amministratore.")
			sudo = []string{"sudo"}
		}
		err = w.runFunnel(append(sudo, cli, "funnel", "--bg", "--yes", port))
		if err != nil {
			// Older CLIs do not know --yes.
			err = w.runFunnel(append(sudo, cli, "funnel", "--bg", port))
		}
		if err != nil {
			w.say("     ✗ Tailscale Funnel non si è attivato (%v).", err)
			again, err := w.askYesNo("     Riprovo?", true)
			if err != nil {
				return err
			}
			if !again {
				return errors.New("Funnel non attivo: riesegui 'thevault-server setup' più tardi")
			}
			continue
		}
		host := strings.TrimSuffix(st.Self.DNSName, ".")
		cfg.PublicURL = "https://" + host
		w.say("     Verifico che il server sia raggiungibile su %s …", cfg.PublicURL)
		deadline := time.Now().Add(90 * time.Second)
		var last error
		for time.Now().Before(deadline) {
			if last = checkHealth(cfg.PublicURL); last == nil {
				break
			}
			time.Sleep(3 * time.Second)
		}
		if last != nil {
			w.say("     ⚠ Non ancora raggiungibile (%v). A volte servono un paio di minuti per il certificato:", last)
			w.say("       controlla più tardi con 'thevault-server status'.")
		} else {
			w.say("     ✓ Raggiungibile da internet.")
		}
		return nil
	}
}

// Status prints the state of the service and of the public address.
func Status(dataDir string) error {
	cfg, err := config.Load(dataDir)
	if err != nil {
		return fmt.Errorf("configurazione non trovata in %s: esegui 'thevault-server setup'", dataDir)
	}
	fmt.Println("The Vault — stato del server")
	fmt.Println("  Dati:            ", dataDir)
	fmt.Println("  Email ammessa:   ", strings.Join(cfg.AllowedEmails, ", "))
	fmt.Println("  Invio email:     ", cfg.SMTP.Host)
	if err := checkHealth(localURL(cfg)); err != nil {
		fmt.Println("  Server locale:    ✗ non risponde:", err)
		fmt.Println("                    registro:", LogPath(dataDir))
	} else {
		fmt.Println("  Server locale:    ✓ attivo su", localURL(cfg))
	}
	if runtime.GOOS == "linux" {
		fmt.Println("  Avvio automatico:", systemdSummary())
	}
	if cfg.PublicURL == "" {
		fmt.Println("  Fuori casa:       ✗ non configurato (riesegui 'thevault-server setup')")
	} else if err := checkHealth(cfg.PublicURL); err != nil {
		fmt.Println("  Fuori casa:       ✗", cfg.PublicURL, "non raggiungibile:", err)
	} else {
		fmt.Println("  Fuori casa:       ✓", cfg.PublicURL)
		fmt.Println("  Indirizzo per l'app:", strings.TrimPrefix(cfg.PublicURL, "https://"))
	}
	fmt.Println("  Backup:          ", backupSummary(cfg))
	return nil
}

// backupSummary describes the latest backup for 'status'.
func backupSummary(cfg *config.Config) string {
	st := backup.ReadStatus(cfg)
	when := func(ms int64) string { return time.UnixMilli(ms).Format("02/01/2006 15:04") }
	switch {
	case st.LastAttempt == 0:
		return "nessuno ancora (il primo parte 30 secondi dopo l'avvio del server)"
	case st.LastError == "":
		return "✓ ultimo riuscito il " + when(st.LastSuccess) + " in " + backup.Dir(cfg)
	}
	msg := "✗ l'ultimo (" + when(st.LastAttempt) + ") non è riuscito: " + st.LastError
	if strings.Contains(st.LastError, "operation not permitted") || strings.Contains(st.LastError, "permission denied") {
		who := "macOS non lascia scrivere il server"
		if runtime.GOOS == "linux" {
			who = "il server non ha il permesso di scrivere"
		}
		msg += "\n                    " + who + " in " + backup.Dir(cfg) +
			": esegui 'thevault-server setup' e scegli la cartella proposta."
	}
	if st.LastSuccess != 0 {
		msg += "\n                    Ultimo riuscito: " + when(st.LastSuccess)
	}
	return msg
}
