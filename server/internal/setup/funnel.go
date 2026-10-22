package setup

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
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
		// KeyExpiry is set while the node key expires (the Tailscale default, 180 days): when it does, the
		// server is no longer reachable from outside home until someone logs in again.
		KeyExpiry *time.Time `json:"KeyExpiry"`
	} `json:"Self"`
}

// serveConfig is the part of 'tailscale funnel status --json' that tells what is published.
type serveConfig struct {
	Web map[string]struct {
		Handlers map[string]struct {
			Proxy string `json:"Proxy"`
		} `json:"Handlers"`
	} `json:"Web"`
	AllowFunnel map[string]bool `json:"AllowFunnel"`
}

// funnelPublishes reports whether a 'tailscale funnel status --json' output publishes https://host on the
// internet and forwards it to the local port.
func funnelPublishes(statusJSON []byte, host, port string) bool {
	var c serveConfig
	if json.Unmarshal(statusJSON, &c) != nil {
		return false
	}
	hp := host + ":443"
	if !c.AllowFunnel[hp] {
		return false
	}
	for _, h := range c.Web[hp].Handlers {
		if strings.HasSuffix(strings.TrimRight(h.Proxy, "/"), ":"+port) {
			return true
		}
	}
	return false
}

// funnelActive asks Tailscale whether Funnel publishes host for the local port (an error: we cannot tell).
func funnelActive(cli, host, port string) (bool, error) {
	if cli == "" {
		return false, errors.New("Tailscale non installato")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, cli, "funnel", "status", "--json").Output()
	if err != nil {
		return false, err
	}
	return funnelPublishes(out, host, port), nil
}

// tailscaleLogin tells how to log in to Tailscale: the command on Linux, the app on the Mac.
func tailscaleLogin(linux bool) string {
	if linux {
		return "esegui 'sudo tailscale up' e apri il link che compare"
	}
	return "apri Tailscale (l'icona nella barra dei menu) e accedi al tuo account"
}

// keyExpiryNote describes the expiry of this computer's Tailscale key ("" if it never expires).
func keyExpiryNote(st *tsStatus, now time.Time, linux bool) string {
	if st.Self.KeyExpiry == nil {
		return ""
	}
	name := strings.SplitN(st.Self.DNSName, ".", 2)[0]
	fix := "disattiva la scadenza: login.tailscale.com/admin/machines › " + name + " › ⋯ › Disable key expiry"
	if st.Self.KeyExpiry.Before(now) {
		return "✗ la chiave Tailscale di questo computer è scaduta: The Vault non è raggiungibile da fuori casa.\n" +
			"                    Per rinnovarla " + tailscaleLogin(linux) + ", poi " + fix
	}
	return "⚠ la chiave Tailscale di questo computer scade il " + st.Self.KeyExpiry.Local().Format("02/01/2006") +
		": da allora The Vault non sarà raggiungibile da fuori casa.\n                    Per evitarlo " + fix
}

// tailscaleSummary describes Tailscale for 'status'.
func tailscaleSummary(cli string, now time.Time, linux bool) string {
	st, err := tailscaleStatus(cli)
	switch {
	case err != nil:
		return "✗ non risponde (" + err.Error() + ")"
	case st.BackendState != "Running":
		return "✗ non collegato: " + tailscaleLogin(linux)
	}
	if note := keyExpiryNote(st, now, linux); note != "" {
		return note
	}
	return "✓ collegato (" + strings.TrimSuffix(st.Self.DNSName, ".") + "), chiave senza scadenza"
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

// runFunnel runs a Tailscale command, showing its output (it may contain the link to enable Funnel), and
// returns that output too.
func (w *Wizard) runFunnel(args []string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	var out bytes.Buffer
	cmd := exec.CommandContext(ctx, args[0], args[1:]...)
	cmd.Stdin = os.Stdin
	cmd.Stdout, cmd.Stderr = io.MultiWriter(w.Out, &out), io.MultiWriter(w.Out, &out)
	err := cmd.Run()
	return out.String(), err
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
		out, err := w.runFunnel(append(sudo, cli, "funnel", "--bg", "--yes", port))
		if err != nil && (strings.Contains(out, "flag provided but not defined") || strings.Contains(out, "unknown flag")) {
			// Older CLIs do not know --yes.
			_, err = w.runFunnel(append(sudo, cli, "funnel", "--bg", port))
		}
		host := strings.TrimSuffix(st.Self.DNSName, ".")
		if err == nil {
			// The command can end without publishing anything (e.g. Funnel not allowed on the account).
			if ok, ferr := funnelActive(cli, host, port); ferr == nil && !ok {
				err = errors.New("Tailscale non pubblica il server su internet")
			}
		}
		if err != nil {
			w.say("     ✗ Tailscale Funnel non si è attivato (%v).", err)
			w.say("       Se è comparso un link, aprilo nel browser e conferma l'attivazione di Funnel, poi riprova.")
			again, err := w.askYesNo("     Riprovo?", true)
			if err != nil {
				return err
			}
			if !again {
				return errors.New("Funnel non attivo: riesegui 'thevault-server setup' più tardi")
			}
			continue
		}
		cfg.PublicURL = "https://" + host
		w.say("     Verifico che il server risponda su %s …", cfg.PublicURL)
		deadline := time.Now().Add(90 * time.Second)
		var last error
		for time.Now().Before(deadline) {
			if last = checkHealth(cfg.PublicURL); last == nil {
				break
			}
			time.Sleep(3 * time.Second)
		}
		if last != nil {
			w.say("     ⚠ Non risponde ancora (%v). A volte servono un paio di minuti per il certificato:", last)
			w.say("       controlla più tardi con 'thevault-server status'.")
		} else {
			// From here the address goes through Tailscale's own network: the real test is from outside.
			w.say("     ✓ Il server risponde ed è pubblicato su internet con Tailscale Funnel.")
			w.say("       Prova da fuori casa: da un telefono con i dati mobili (non il Wi-Fi) apri")
			w.say("       %s/v1/health  (deve comparire \"thevault\").", cfg.PublicURL)
		}
		if note := keyExpiryNote(st, time.Now(), w.linux()); note != "" {
			w.say("     %s", note)
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
	cli := tailscaleCLI()
	if cli != "" {
		fmt.Println("  Tailscale:       ", tailscaleSummary(cli, time.Now(), runtime.GOOS == "linux"))
	}
	host := strings.TrimPrefix(cfg.PublicURL, "https://")
	_, port, _ := net.SplitHostPort(cfg.Listen)
	var public error
	if cfg.PublicURL != "" {
		public = checkHealth(cfg.PublicURL)
	}
	switch {
	case cfg.PublicURL == "":
		fmt.Println("  Fuori casa:       ✗ non configurato (riesegui 'thevault-server setup')")
	case public != nil:
		fmt.Println("  Fuori casa:       ✗", cfg.PublicURL, "non raggiungibile:", public)
	default:
		// The health check from here goes through Tailscale's own network: ask Tailscale whether Funnel is on.
		if ok, err := funnelActive(cli, host, port); err == nil && !ok {
			fmt.Println("  Fuori casa:       ⚠", cfg.PublicURL, "risponde solo ai dispositivi con Tailscale:")
			fmt.Println("                    Funnel non è attivo, riesegui 'thevault-server setup'")
		} else {
			fmt.Println("  Fuori casa:       ✓", cfg.PublicURL, "(prova da un telefono con i dati mobili)")
		}
		fmt.Println("  Indirizzo per l'app:", host)
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
	case st.LastError == "" && st.MissingBlobs > 0:
		return fmt.Sprintf("⚠ ultimo riuscito il %s, ma sul server mancano %d allegati: le loro copie nei backup restano.\n"+
			"                    Dettagli nel registro: %s", when(st.LastSuccess), st.MissingBlobs, LogPath(cfg.DataDir))
	case st.LastError == "" && time.Since(time.UnixMilli(st.LastSuccess)) > 26*time.Hour:
		return "⚠ l'ultimo riuscito è del " + when(st.LastSuccess) + ", più di un giorno fa: il server era spento?\n" +
			"                    Se dura, guarda il registro: " + LogPath(cfg.DataDir)
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
