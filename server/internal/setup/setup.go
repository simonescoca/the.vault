// Package setup implements the interactive configuration (in Italian) and the macOS background service.
package setup

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"golang.org/x/term"

	"github.com/simonescoca/the.vault/server/internal/config"
	"github.com/simonescoca/the.vault/server/internal/mail"
)

// Wizard asks the questions and writes the configuration. Its dependencies are replaceable in tests.
type Wizard struct {
	In      *bufio.Reader
	Out     io.Writer
	DataDir string
	Version string

	ReadPassword   func(prompt string) (string, error)
	SendTestMail   func(cfg *config.Config) error
	InstallService func(cfg *config.Config) error
	WaitHealthy    func(cfg *config.Config) error
	SetupFunnel    func(w *Wizard, cfg *config.Config) error
}

// Run is the entry point of `thevault-server setup`.
func Run(dataDir, version string) error {
	w := &Wizard{
		In:      bufio.NewReader(os.Stdin),
		Out:     os.Stdout,
		DataDir: dataDir,
		Version: version,
		ReadPassword: func(prompt string) (string, error) {
			fmt.Print(prompt)
			b, err := term.ReadPassword(int(os.Stdin.Fd()))
			fmt.Println()
			return string(b), err
		},
		SendTestMail: func(cfg *config.Config) error {
			ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
			defer cancel()
			to := cfg.AllowedEmails[0]
			return mail.New(cfg).Send(ctx, mail.Message{To: to, Subject: "The Vault: email di prova",
				Text: "Ciao,\n\nse leggi questa email il server di The Vault riesce a inviare i codici di accesso.\n\n— The Vault\n"})
		},
		InstallService: InstallService,
		WaitHealthy:    WaitHealthy,
		SetupFunnel:    setupFunnel,
	}
	return w.Run()
}

func (w *Wizard) say(format string, a ...any) { fmt.Fprintf(w.Out, format+"\n", a...) }

// ask prints a question with a default and returns the trimmed answer (or the default).
func (w *Wizard) ask(question, def string) (string, error) {
	if def != "" {
		fmt.Fprintf(w.Out, "%s [%s]: ", question, def)
	} else {
		fmt.Fprintf(w.Out, "%s: ", question)
	}
	line, err := w.In.ReadString('\n')
	if err != nil && !(errors.Is(err, io.EOF) && line != "") {
		return "", errors.New("configurazione interrotta")
	}
	line = strings.TrimSpace(line)
	if line == "" {
		return def, nil
	}
	return line, nil
}

func (w *Wizard) askYesNo(question string, def bool) (bool, error) {
	d := "s"
	if !def {
		d = "n"
	}
	for {
		a, err := w.ask(question+" (s/n)", d)
		if err != nil {
			return false, err
		}
		switch strings.ToLower(a) {
		case "s", "si", "sì", "y", "yes":
			return true, nil
		case "n", "no":
			return false, nil
		}
	}
}

func (w *Wizard) Run() error {
	w.say("")
	w.say("The Vault — configurazione del server (%s)", w.Version)
	w.say("==============================================")
	w.say("Ti farò qualche domanda. Premi Invio per accettare il valore tra [parentesi].")
	w.say("Puoi ripetere questa configurazione quando vuoi: i dati già salvati restano.")
	w.say("")

	cfg, err := config.Load(w.DataDir)
	if err != nil {
		cfg = config.Default(w.DataDir)
	}
	if cfg.ServerSecret == "" {
		cfg.ServerSecret = config.NewSecret()
	}

	// 1. Email
	w.say("1/5  La tua email")
	w.say("     Solo questa email potrà accedere a The Vault.")
	def := ""
	if len(cfg.AllowedEmails) > 0 {
		def = cfg.AllowedEmails[0]
	}
	for {
		a, err := w.ask("     Email", def)
		if err != nil {
			return err
		}
		if e := config.NormalizeEmail(a); e != "" {
			cfg.AllowedEmails = []string{e}
			break
		}
		w.say("     ✗ Non sembra un indirizzo email valido, riprova.")
	}
	w.say("")

	// 2. Mail sending
	if err := w.configureMail(cfg); err != nil {
		return err
	}

	// 3. Backups
	w.say("3/5  Backup automatici")
	w.say("     Ogni notte il server salva una copia dei dati (già cifrati: nessuno può leggerli).")
	w.say("     Lascia la cartella proposta: macOS non permette ai servizi in background di scrivere su")
	w.say("     iCloud Drive, Scrivania, Documenti, Download o dischi esterni. Per avere una copia anche")
	w.say("     fuori dal Mac mini, attiva Time Machine: copierà anche questa cartella.")
	defDir := cfg.Backup.Dir
	if defDir == "" || BlockedBackupLocation(defDir) != "" {
		defDir = defaultBackupDir()
	}
	for {
		dir, err := w.ask("     Cartella dei backup", defDir)
		if err != nil {
			return err
		}
		dir = expandHome(dir)
		if where := BlockedBackupLocation(dir); where != "" {
			w.say("     ⚠ %s: macOS non lascerebbe scrivere lì il server in background. Scegli un'altra cartella.", where)
			continue
		}
		if err := os.MkdirAll(dir, 0o700); err != nil {
			w.say("     ⚠ Non riesco a creare la cartella (%v). Scegline un'altra.", err)
			continue
		}
		cfg.Backup.Dir = dir
		break
	}
	w.say("")

	cfg.Normalize()
	if err := cfg.Validate(); err != nil {
		return err
	}
	if err := cfg.Save(); err != nil {
		return fmt.Errorf("salvataggio della configurazione: %w", err)
	}

	// 4. Service
	w.say("4/5  Avvio automatico")
	w.say("     Installo il servizio che tiene acceso il server e lo riavvia da solo…")
	if err := w.InstallService(cfg); err != nil {
		return fmt.Errorf("installazione del servizio: %w", err)
	}
	if err := w.WaitHealthy(cfg); err != nil {
		return fmt.Errorf("il server non risponde: %w (vedi il registro in %s)", err, LogPath(w.DataDir))
	}
	w.say("     ✓ Il server è attivo su http://%s", cfg.Listen)
	w.say("")

	// 5. Access from outside home
	w.say("5/5  Accesso da fuori casa")
	if err := w.SetupFunnel(w, cfg); err != nil {
		w.say("     ⚠ %v", err)
	}
	if err := cfg.Save(); err != nil {
		return err
	}
	w.say("")
	w.say("==============================================")
	w.say("Fatto! 🎉")
	if cfg.PublicURL != "" {
		w.say("Nell'app The Vault, come indirizzo del server inserisci:")
		w.say("")
		w.say("    %s", strings.TrimPrefix(cfg.PublicURL, "https://"))
	} else {
		w.say("Completa il passo 5 (Tailscale) per usare The Vault da fuori casa,")
		w.say("poi riesegui:  thevault-server setup")
	}
	w.say("")
	w.say("Per controllare il server, in una nuova finestra del Terminale scrivi:  thevault-server status")
	w.say("(da questa finestra: %s status)", ShellCommand(BinPath(w.DataDir)))
	return nil
}

// ShellCommand writes path so that it can be pasted in the Terminal: with $HOME instead of the home folder
// and in quotes (the default data folder has a space in "Application Support").
func ShellCommand(path string) string {
	if home, err := os.UserHomeDir(); err == nil && home != "" && strings.HasPrefix(path, home+string(filepath.Separator)) {
		path = "$HOME" + strings.TrimPrefix(path, home)
	}
	return `"` + strings.ReplaceAll(path, `"`, `\"`) + `"`
}

func (w *Wizard) configureMail(cfg *config.Config) error {
	w.say("2/5  Invio delle email con i codici di accesso")
	w.say("     Il server invia i codici dalla tua casella di posta.")
	w.say("       1) iCloud  (indirizzi @icloud.com, @me.com, @mac.com)")
	w.say("       2) Gmail")
	w.say("       3) Altro servizio (server SMTP)")
	defChoice := "1"
	switch {
	case cfg.SMTP.Host == "smtp.gmail.com":
		defChoice = "2"
	case cfg.SMTP.Host != "" && cfg.SMTP.Host != "smtp.mail.me.com":
		defChoice = "3"
	case cfg.SMTP.Host == "" && len(cfg.AllowedEmails) > 0 && strings.HasSuffix(cfg.AllowedEmails[0], "@gmail.com"):
		defChoice = "2"
	}
	for {
		choice, err := w.ask("     Scelta", defChoice)
		if err != nil {
			return err
		}
		cfg.MailMode = "smtp"
		switch choice {
		case "1":
			cfg.SMTP = config.SMTP{Host: "smtp.mail.me.com", Port: 587, Security: "starttls", Username: cfg.SMTP.Username, Password: cfg.SMTP.Password}
			w.say("     Serve una «password specifica per le app»: creala su https://account.apple.com")
			w.say("     › Accesso e sicurezza › Password specifiche per le app (es. «The Vault»).")
		case "2":
			cfg.SMTP = config.SMTP{Host: "smtp.gmail.com", Port: 587, Security: "starttls", Username: cfg.SMTP.Username, Password: cfg.SMTP.Password}
			w.say("     Serve una «password per le app» di Google: https://myaccount.google.com/apppasswords")
			w.say("     (richiede la verifica in due passaggi attiva).")
		case "3":
			host, err := w.ask("     Server SMTP (es. smtp.esempio.it)", cfg.SMTP.Host)
			if err != nil {
				return err
			}
			portS, err := w.ask("     Porta", strconv.Itoa(max(cfg.SMTP.Port, 587)))
			if err != nil {
				return err
			}
			port, _ := strconv.Atoi(portS)
			sec := "starttls"
			if port == 465 {
				sec = "tls"
			}
			cfg.SMTP = config.SMTP{Host: host, Port: port, Security: sec, Username: cfg.SMTP.Username, Password: cfg.SMTP.Password}
		default:
			w.say("     ✗ Scrivi 1, 2 oppure 3.")
			continue
		}
		break
	}
	userDef := cfg.SMTP.Username
	if userDef == "" {
		userDef = cfg.AllowedEmails[0]
	}
	for {
		user, err := w.ask("     Indirizzo email da cui inviare", userDef)
		if err != nil {
			return err
		}
		cfg.SMTP.Username = user
		cfg.SMTP.From = "The Vault <" + user + ">"
		prompt := "     Password specifica per app"
		if cfg.SMTP.Password != "" {
			prompt += " (Invio per lasciare quella salvata)"
		}
		pw, err := w.ReadPassword(prompt + ": ")
		if err != nil {
			return err
		}
		if strings.TrimSpace(pw) != "" {
			cfg.SMTP.Password = strings.TrimSpace(pw)
		}
		w.say("     Invio un'email di prova a %s…", cfg.AllowedEmails[0])
		if err := w.SendTestMail(cfg); err != nil {
			w.say("     ✗ Invio non riuscito: %v", err)
			again, err := w.askYesNo("     Vuoi riprovare con altri dati?", true)
			if err != nil {
				return err
			}
			if again {
				userDef = user
				cfg.SMTP.Password = ""
				continue
			}
			return errors.New("senza invio delle email non è possibile accedere all'app")
		}
		w.say("     ✓ Email inviata. Controlla la posta (anche nella cartella Spam).")
		break
	}
	w.say("")
	return nil
}

// defaultBackupDir is a visible folder in the home folder, where a background service may write.
func defaultBackupDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "The Vault Backup")
}

// BlockedBackupLocation names the place if dir is somewhere macOS does not let a background service (the
// LaunchAgent) write without a permission it cannot ask for: iCloud Drive and other cloud folders, Desktop,
// Documents, Downloads, external and network disks. Empty if dir is fine.
func BlockedBackupLocation(dir string) string {
	home, _ := os.UserHomeDir()
	clean := filepath.Clean(expandHome(dir))
	within := func(base string) bool {
		rel, err := filepath.Rel(base, clean)
		return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
	}
	switch {
	case within(filepath.Join(home, "Library", "Mobile Documents")):
		return "iCloud Drive"
	case within(filepath.Join(home, "Library", "CloudStorage")):
		return "Una cartella cloud (Dropbox, OneDrive, Google Drive…)"
	case within(filepath.Join(home, "Desktop")):
		return "La Scrivania"
	case within(filepath.Join(home, "Documents")):
		return "La cartella Documenti"
	case within(filepath.Join(home, "Downloads")):
		return "La cartella Download"
	case within("/Volumes"):
		return "Un disco esterno o di rete"
	}
	return ""
}

func expandHome(p string) string {
	if strings.HasPrefix(p, "~/") {
		home, _ := os.UserHomeDir()
		return filepath.Join(home, p[2:])
	}
	return p
}
