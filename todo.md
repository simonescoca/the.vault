# The Vault — piano di lavoro e diario di viaggio

> Questo file è insieme **il piano** e **il diario** del progetto.
> Ogni task ha uno stato; dopo ogni task eseguo i test e annoto cosa è successo, compresi gli scivoloni,
> risolti o ancora aperti. In fondo c'è il **diario di bordo** in ordine cronologico.
>
> Legenda: `[ ]` da fare · `[~]` in corso · `[x]` completato · `[!]` bloccato / problema aperto

---

## 1. Cosa stiamo costruendo

**The Vault** è un gestore di password personale, bello, minimal e intuitivo, sincronizzato in tempo reale
tra tutti i tuoi dispositivi tramite un server tuo: il **Mac mini M4**, sempre acceso.

- Prima fase (questo piano): **app desktop macOS + Windows** e **server sul Mac mini**.
- Fasi successive: app **iOS / Android** (stesso codice) e **compilazione automatica nei siti web** (autofill).

### 1.1 Requisiti di partenza (dalla tua richiesta)

1. Account obbligatorio; il login si fa **una sola volta** per dispositivo, con un **codice via email (OTP)**.
2. Il server conserva i dati **cifrati**, aggiornati **in tempo reale** da ogni modifica fatta su qualsiasi dispositivo.
3. Ogni voce ("password") ha un **titolo** e un numero **illimitato** di righe **chiave / valore**; le chiavi sono **libere**.
4. A ogni voce si possono **allegare file di qualsiasi tipo**.
5. Una nuova voce parte con **3 righe vuote** con chiavi suggerite in grigio: **sito web**, **email**, **password**.
6. Le righe si possono rimuovere, ma **ne resta sempre almeno una**; le righe vuote spariscono al salvataggio.
7. Gli **URL sono cliccabili**; le **email non sono cliccabili**.
8. Ogni voce si può **modificare** o **eliminare**; c'è il **cestino** (niente eliminazione immediata).
9. In fondo alle righe c'è sempre il campo **descrizione**: se è vuoto sparisce al salvataggio e in modifica ricompare,
   così come il campo per **allegare file**.
10. Font: **chiavi** in un sans-serif leggibile, elegante e minimal; **valori** in **monospace**;
    **descrizione** nello stesso font delle chiavi; **titolo** nello stesso font, ma più grande e più marcato.
11. Tema **chiaro / scuro** dalle impostazioni di sistema; lingua **italiano / inglese**.

### 1.2 Le tue risposte alle mie domande

| Tema | Scelta |
|---|---|
| Nuovo dispositivo | Codice email **+ conferma da un dispositivo già collegato** ("Nuovo accesso, approvi?"). Alla registrazione ricevi un **codice di emergenza** da conservare, che serve solo se perdi tutti i dispositivi. |
| Sblocco dell'app | **Touch ID / Windows Hello**; se la biometria non è disponibile, un **PIN dell'app**. |
| Utenti | **Solo tu** (un solo account). |
| Uso fuori casa | **Sì, ovunque**: il Mac mini sarà raggiungibile in modo sicuro da internet. |
| Valori nascosti | Di default **tutto visibile**. Su ogni valore c'è un **occhio**: cliccandolo passi da occhio a occhio barrato e il valore si nasconde con i pallini (o torna visibile). Lo stato di ogni valore **resta salvato**. |
| Righe compilate a metà | Se scrivi solo il valore, **la chiave diventa il suggerimento grigio** (es. "password"). Se scrivi solo la chiave, la riga **viene eliminata**. |
| Link | Gli indirizzi web sono cliccabili e, in più, puoi scrivere un **testo con un link associato** (es. "Area clienti" → apre il sito). |
| Cestino | Le voci restano nel cestino finché **non le ripristini o le elimini per sempre tu** (con conferma). |
| Finestra | **Tre colonne**: menu a sinistra (Tutte, Preferiti, Cestino, Impostazioni), elenco con ricerca al centro, dettaglio a destra. |
| Righe chiave/valore | **Affiancate**: chiave a sinistra, valore a destra, allineati. |
| Colore | **Monocromatico**: bianco/nero e grigi; il colore compare solo per gli avvisi. |
| Icone nell'elenco | L'**icona del sito**, se nella voce c'è un sito; altrimenti l'**iniziale** del titolo. |
| Organizzazione | **Un'unica lista** alfabetica con **ricerca istantanea**. |
| Funzioni extra (v1) | **Generatore di password**, **Preferiti**, **Esporta su file**, **Riordina righe** trascinandole. |
| Autofill nei siti | **Sì, ma più avanti** (fase successiva). |
| Non in v1 (possibili in futuro) | Cronologia modifiche, codici 2FA, import da Password di Apple, accesso rapido da tastiera. |

### 1.3 Dettagli che ho deciso io (puoi cambiarli quando vuoi)

- **Titolo**: se lo lasci vuoto e nella voce c'è un sito, il titolo diventa il nome del sito (es. `netflix.com` → "Netflix").
  È la stessa logica dei suggerimenti delle chiavi. Senza sito, il titolo è obbligatorio.
- **Righe aggiunte dopo le prime tre**: mostrano solo un aiuto generico ("chiave"), che non viene adottato:
  se lasci la chiave vuota, la riga resta senza chiave.
- **Copia**: un clic su un valore lo copia ("Copiato ✓"). Per sicurezza gli appunti si svuotano da soli dopo **1 minuto**
  (impostabile). I valori nascosti si copiano senza mostrarli.
- **Link**: un clic su un indirizzo web o su un testo con link apre il browser; un'icona accanto permette di copiarlo.
  Vengono riconosciuti `https://…`, `www.…` e i domini come `netflix.com`.
- **Blocco automatico** dopo **5 minuti** di inattività (impostabile) e quando il computer va in stop.
- **PIN** di 6 cifre. Dopo **10 tentativi sbagliati** il dispositivo si scollega da solo: i dati restano al sicuro sul server
  e per rientrare servono di nuovo il codice email e l'approvazione.
- **Allegati**: si aggiungono trascinandoli nella finestra o con un pulsante; si aprono con l'app predefinita del computer;
  "Salva una copia"; anteprima per le immagini; fino a **200 MB** per file; disponibili anche offline
  (copia cifrata su ogni computer).
- **Offline**: l'app funziona anche senza connessione (vedi e modifichi), e sincronizza appena torna online.
- **Conflitti**: se la stessa voce viene modificata su due dispositivi mentre uno è offline, non si perde nulla:
  viene tenuta anche una copia marcata "(conflitto)".
- **Impostazioni**: Aspetto (Sistema / Chiaro / Scuro), Lingua (Sistema / Italiano / English), Sicurezza
  (blocco automatico, Touch ID / Windows Hello, PIN, appunti), Dispositivi collegati (con disconnessione a distanza),
  Esporta / Importa backup, Kit di emergenza.
- **Avviso via email** quando un nuovo dispositivo viene collegato al tuo account.
- **Esporta su file**: un file di backup cifrato con una password scelta al momento; si può reimportare.
- **Server**: backup automatico giornaliero (già cifrato) in una cartella a scelta, conservando gli ultimi 30 giorni.
- **Elenco**: ordine alfabetico; sotto il titolo compare la prima email o il primo nome utente della voce.

### 1.4 Scelte tecniche, spiegate semplici

- **App: Flutter.** Un unico codice per Mac e Windows, e domani per iPhone e Android: le app mobile non dovranno
  essere riscritte da zero.
- **Server: Go.** Un solo programma leggero che gira sul Mac mini, parte da solo all'accensione e non richiede manutenzione.
- **Cifratura end-to-end.** Le password vengono cifrate sul tuo dispositivo *prima* di partire. Il Mac mini conserva
  solo dati illeggibili: anche se qualcuno entrasse nel server, non potrebbe leggere nulla.
  Algoritmi standard e collaudati (libsodium: XChaCha20-Poly1305, X25519, Argon2id).
- **Tempo reale.** Ogni dispositivo resta in ascolto sul server (WebSocket): una modifica appare sugli altri in un attimo.
- **Raggiungibile da fuori casa** senza toccare il router: Tailscale Funnel (gratuito, HTTPS automatico).
  Ti guiderò passo passo.
- **Email dei codici**: inviate dal server tramite la tua casella (es. iCloud, con una "password specifica per app").
- **Pacchetti pronti**: GitHub costruisce in automatico il `.dmg` per Mac, l'installer `.exe` per Windows e il server
  per il Mac mini.

---

## 2. Piano dei lavori

Dopo **ogni** task eseguo la batteria di test di tutto il progetto, non solo del pezzo nuovo, e ne annoto l'esito nel diario.

### Fase 0 — Preparazione
- [!] **T0.1** Verifica push su GitHub. *Bloccato: l'app GitHub di Claude non è installata sulla repo (errore 403).*
- [x] **T0.2** Piano di lavoro (`todo.md`) e struttura della repo
- [x] **T0.3** Strumenti di sviluppo (Flutter, Go) e prova di compilazione
- [~] **T0.4** Test automatici su GitHub (CI) per server e app. *Workflow scritto; si potrà verificare solo quando il push funzionerà.*

### Fase 1 — Progettazione
- [ ] **T1.1** Specifiche funzionali dettagliate: schermate, comportamenti, regole (`docs/SPEC.md`)
- [ ] **T1.2** Progetto di sicurezza: chiavi, cifratura, approvazione dispositivi, kit di emergenza (`docs/SECURITY.md`)
- [ ] **T1.3** Protocollo app ↔ server: API, sincronizzazione, tempo reale (`docs/PROTOCOL.md`)
- [ ] **T1.4** Design visivo: font, colori, spaziature, icone, componenti; anteprime delle schermate principali

### Fase 2 — Server (Mac mini)
- [ ] **T2.1** Scheletro del server: configurazione, database, log, avvio
- [ ] **T2.2** Accesso con codice email (OTP) e invio email
- [ ] **T2.3** Dispositivi: registrazione, approvazione da un altro dispositivo, kit di emergenza, disconnessione
- [ ] **T2.4** Sincronizzazione delle voci cifrate e notifiche in tempo reale (WebSocket)
- [ ] **T2.5** Allegati: caricamento e scaricamento a blocchi
- [ ] **T2.6** Protezioni: limiti ai tentativi, limiti di traffico, dimensioni massime, header di sicurezza
- [ ] **T2.7** Backup automatico giornaliero
- [ ] **T2.8** Installazione guidata su macOS (configurazione, avvio automatico, stato, aggiornamento)

### Fase 3 — Cuore dell'app (logica, senza grafica)
- [ ] **T3.1** Crittografia: chiavi, cifratura di voci e file, sigilli per l'approvazione, codice di emergenza
- [ ] **T3.2** Modello dati (voce, righe, link, allegati) e regole di salvataggio
- [ ] **T3.3** Archivio locale cifrato (funzionamento offline)
- [ ] **T3.4** Comunicazione con il server e motore di sincronizzazione, con gestione dei conflitti
- [ ] **T3.5** Flussi account: primo accesso, nuovo dispositivo, approvazione, kit di emergenza, disconnessione
- [ ] **T3.6** Test integrati: app ↔ server reale, più dispositivi simulati

### Fase 4 — Interfaccia
- [ ] **T4.1** Tema chiaro/scuro, font, lingua IT/EN, componenti di base
- [ ] **T4.2** Primo avvio: server, email, codice, kit di emergenza, PIN, Touch ID / Windows Hello
- [ ] **T4.3** Schermata di blocco e blocco automatico
- [ ] **T4.4** Finestra a tre colonne: menu, elenco con ricerca, dettaglio
- [ ] **T4.5** Dettaglio voce: righe affiancate, link, occhio, copia, allegati, descrizione
- [ ] **T4.6** Creazione e modifica: suggerimenti, aggiungi/rimuovi/riordina righe, link su testo, generatore, allegati
- [ ] **T4.7** Preferiti e Cestino (ripristina, elimina per sempre, svuota)
- [ ] **T4.8** Icone dei siti con ripiego sull'iniziale
- [ ] **T4.9** Impostazioni: aspetto, lingua, sicurezza, dispositivi, esporta/importa, kit di emergenza
- [ ] **T4.10** Approvazione di un nuovo dispositivo (finestra di conferma con codice di verifica)
- [ ] **T4.11** Stato della sincronizzazione, modalità offline, conflitti
- [ ] **T4.12** Scorciatoie da tastiera, animazioni, rifiniture e accessibilità

### Fase 5 — Integrazione con Mac e Windows
- [ ] **T5.1** Touch ID / Windows Hello, con ripiego sul PIN
- [ ] **T5.2** Custodia sicura delle chiavi (Portachiavi di macOS / protezione di Windows)
- [ ] **T5.3** Finestra, icona dell'app, menu
- [ ] **T5.4** Appunti con svuotamento automatico, apertura e salvataggio file, trascinamento

### Fase 6 — Pacchetti e rilascio
- [ ] **T6.1** Build macOS (`.dmg`) con GitHub Actions
- [ ] **T6.2** Build Windows (installer `.exe`) con GitHub Actions
- [ ] **T6.3** Server per Mac mini: programma e script di installazione
- [ ] **T6.4** Pubblicazione della release su GitHub

### Fase 7 — Guide (in italiano, passo passo)
- [ ] **T7.1** Installare il server sul Mac mini (email, accesso da fuori casa, backup)
- [ ] **T7.2** Installare l'app su Mac e Windows e primo utilizzo

### Fase 8 — Collaudo finale
- [ ] **T8.1** Test completi da capo a fondo (più dispositivi, offline, conflitti, allegati)
- [ ] **T8.2** Revisione di sicurezza
- [ ] **T8.3** Revisione visiva: schermate in chiaro/scuro, italiano/inglese
- [ ] **T8.4** Consegna: riepilogo, limiti noti, prossimi passi

---

## 3. Fasi future (dopo il desktop)

- App **iPhone / iPad** e **Android** (stesso codice Flutter).
- **Compilazione automatica** di password nei siti (estensione per il browser).
- Possibili extra: cronologia modifiche, codici 2FA, import da Password di Apple, accesso rapido da tastiera.

---

## 4. Diario di bordo

### 2026-10-02 — Giorno 1

- **Check iniziale GitHub: ❌.** Il tuo account GitHub è collegato e la repo si legge, ma ogni scrittura è rifiutata
  (errore 403 "Resource not accessible by integration"), sia il `git push` sia la creazione di un branch.
  Causa: l'app GitHub di Claude non è installata sulla repo `the.vault`.
  Soluzione: installarla da https://github.com/apps/claude/installations/select_target. Finché non funziona lavoro in locale
  e riprovo il push a ogni task.
- **Domande e risposte**: 4 blocchi (sicurezza e accesso, comportamento delle password, aspetto, funzioni).
  Risposte riportate nella sezione 1.2.
- Nota: la repo è **pubblica**, quindi codice e diario sono visibili a tutti. Non è un problema di sicurezza:
  il codice non contiene segreti e i dati restano cifrati sui tuoi dispositivi e sul Mac mini.
- Verificati gli strumenti disponibili nell'ambiente di sviluppo: Go 1.24, Node 22, Rust 1.97, clang, cmake.
  Flutter va installato (ultima stabile: 3.47.6). Le librerie che servono (biometria, portachiavi, libsodium,
  trascinamento file, SQLite) esistono e sono aggiornate al 2026.
- Scritto questo `todo.md`.

- **T0.2 ✅ Struttura della repo**: `app/` (Flutter), `server/` (Go), `docs/`, `scripts/test-all.sh` (lancia tutti i test),
  `.github/workflows/ci.yml`, `README.md`.
- **T0.3 ✅ Strumenti**: installato Flutter 3.47.6 e le librerie di sistema per compilare e provare l'app su Linux
  (qui non ho un Mac né un PC Windows: provo su Linux e GitHub compilerà per Mac e Windows).
  - libsodium 1.0.22 (cifratura) e SQLite 3.53 (database) si compilano e funzionano dentro l'app.
  - L'app di prova si compila e gira su uno schermo virtuale, da cui faccio gli screenshot: così controllo l'aspetto.
  - Il server Go si compila per il Mac mini (Apple Silicon) già firmato "ad-hoc", come richiede macOS.
  - 🟡 *Scivolone (risolto)*: il primo controllo automatico del codice (analyze) falliva per 4 avvisi nel test di prova
    (funzioni deprecate della libreria di cifratura). Corretto usando le funzioni nuove.
  - Nota: `sodium_libs` è deprecato nel 2026; si usa direttamente `sodium`, che compila libsodium da sé su ogni piattaforma.
- **T0.4 🟡 CI**: workflow pronto (test server, test app, compilazione su macOS e Windows). Non verificabile finché il push
  è bloccato.
- **Test dopo la Fase 0**: `scripts/test-all.sh` → ✅ tutto verde (server: vet ok; app: analyze 0 problemi, 3 test ok).
