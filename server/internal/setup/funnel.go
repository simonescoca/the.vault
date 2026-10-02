package setup

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/simonescoca/the.vault/server/internal/config"
)

// tailscaleCLI finds the Tailscale command line tool (Homebrew/CLI install or the Mac app).
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

// PublicHost returns the Funnel host name (without scheme) of this Mac, if Tailscale is running.
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

func setupFunnel(w *Wizard, cfg *config.Config) error {
	w.say("     Per usare The Vault fuori casa il Mac mini deve essere raggiungibile da internet in modo sicuro.")
	w.say("     Usiamo Tailscale Funnel: gratuito, HTTPS automatico, nessuna modifica al router.")
	for {
		cli := tailscaleCLI()
		if cli == "" {
			w.say("")
			w.say("     Tailscale non è installato. Fai così:")
			w.say("       1. Scarica e installa Tailscale per Mac: https://tailscale.com/download/mac")
			w.say("       2. Aprilo e accedi (va bene il tuo account Apple, Google o Microsoft).")
			w.say("       3. Nel menu di Tailscale attiva «Launch at login» (avvio all'accesso).")
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
			w.say("     Tailscale è installato ma non è collegato: aprilo e accedi al tuo account.")
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
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
		cmd := exec.CommandContext(ctx, cli, "funnel", "--bg", "--yes", port)
		cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, w.Out, w.Out
		err = cmd.Run()
		cancel()
		if err != nil {
			// Older CLIs do not know --yes.
			ctx, cancel = context.WithTimeout(context.Background(), 10*time.Minute)
			cmd = exec.CommandContext(ctx, cli, "funnel", "--bg", port)
			cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, w.Out, w.Out
			err = cmd.Run()
			cancel()
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
	if cfg.PublicURL == "" {
		fmt.Println("  Fuori casa:       ✗ non configurato (riesegui 'thevault-server setup')")
	} else if err := checkHealth(cfg.PublicURL); err != nil {
		fmt.Println("  Fuori casa:       ✗", cfg.PublicURL, "non raggiungibile:", err)
	} else {
		fmt.Println("  Fuori casa:       ✓", cfg.PublicURL)
		fmt.Println("  Indirizzo per l'app:", strings.TrimPrefix(cfg.PublicURL, "https://"))
	}
	dir := cfg.Backup.Dir
	if dir == "" {
		dir = dataDir + "/backups"
	}
	entries, _ := os.ReadDir(dir + "/snapshots")
	if len(entries) == 0 {
		fmt.Println("  Ultimo backup:    nessuno ancora")
	} else {
		fmt.Println("  Ultimo backup:   ", entries[len(entries)-1].Name(), "in", dir)
	}
	return nil
}
