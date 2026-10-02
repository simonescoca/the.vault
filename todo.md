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
- [x] **T1.1** Specifiche funzionali dettagliate: schermate, comportamenti, regole (`docs/SPEC.md`)
- [x] **T1.2** Progetto di sicurezza: chiavi, cifratura, approvazione dispositivi, kit di emergenza (`docs/SECURITY.md`)
- [x] **T1.3** Protocollo app ↔ server: API, sincronizzazione, tempo reale (`docs/PROTOCOL.md`)
- [x] **T1.4** Design visivo: font, colori, spaziature, icone, componenti (`docs/DESIGN.md`). *Le anteprime delle schermate arrivano con la Fase 4, renderizzate dall'app vera.*

### Fase 2 — Server (Mac mini)
- [x] **T2.1** Scheletro del server: configurazione, database, log, avvio
- [x] **T2.2** Accesso con codice email (OTP) e invio email
- [x] **T2.3** Dispositivi: registrazione, approvazione da un altro dispositivo, kit di emergenza, disconnessione
- [x] **T2.4** Sincronizzazione delle voci cifrate e notifiche in tempo reale (WebSocket)
- [x] **T2.5** Allegati: caricamento e scaricamento a blocchi
- [x] **T2.6** Protezioni: limiti ai tentativi, limiti di traffico, dimensioni massime, header di sicurezza
- [x] **T2.7** Backup automatico giornaliero
- [x] **T2.8** Installazione guidata su macOS (configurazione, avvio automatico, stato, aggiornamento)

### Fase 3 — Cuore dell'app (logica, senza grafica)
- [x] **T3.1** Crittografia: chiavi, cifratura di voci e file, sigilli per l'approvazione, codice di emergenza
- [x] **T3.2** Modello dati (voce, righe, link, allegati) e regole di salvataggio
- [x] **T3.3** Archivio locale cifrato (funzionamento offline)
- [x] **T3.4** Comunicazione con il server e motore di sincronizzazione, con gestione dei conflitti
- [x] **T3.5** Flussi account: primo accesso, nuovo dispositivo, approvazione, kit di emergenza, disconnessione
- [x] **T3.6** Test integrati: app ↔ server reale, più dispositivi simulati

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

- **Fase 1 ✅ Progettazione** (4 documenti in `docs/`):
  - `SPEC.md`: tutte le schermate e i comportamenti, comprese le regole di salvataggio delle righe.
  - `SECURITY.md`: chi conosce quali chiavi, come si cifrano voci e allegati, come funziona l'approvazione di un nuovo
    dispositivo.
    - Ragionando sull'approvazione ho trovato una **trappola**: con un semplice codice di 6 cifre calcolato dalla chiave
      del nuovo dispositivo, un server compromesso potrebbe provare milioni di chiavi finché il codice coincide
      (bastano pochi secondi). Ho adottato il **confronto numerico con impegno** (lo schema del Bluetooth): ogni dispositivo
      si "impegna" prima di vedere i dati dell'altro, quindi un intruso ha 1 possibilità su un milione e un solo tentativo.
  - `PROTOCOL.md`: le API del server, il canale in tempo reale e l'algoritmo di sincronizzazione con i conflitti.
  - `DESIGN.md`: colori monocromatici chiaro/scuro, tipografia, spazi, icone (Lucide), finestra.
  - **Font scelti dopo un confronto renderizzato** (`docs/design/font-specimen.png`): **Geist** per titoli, chiavi e
    descrizione; **Geist Mono** per i valori. Geist Mono ha lo zero barrato e distingue `1 l I`
    (`docs/design/mono-ambiguous-chars.png`). L'alternativa (Inter + JetBrains Mono) era valida ma meno elegante,
    e il suo zero si confonde di più con la O.
  - 🟡 *Scivolone (risolto)*: nel primo confronto i testi apparivano sottolineati in giallo. Era l'avviso di Flutter per i
    testi fuori da un contenitore "Material", non un problema dei font: corretto il banco di prova.

- **Fase 2 ✅ Server** (Go, cartella `server/`), un task dopo l'altro, con test a ogni passo:
  - **T2.1** Scheletro: configurazione (`config.json`, permessi riservati), database SQLite con migrazioni, registro, avvio
    e spegnimento puliti. Test del database: utenti, dispositivi, creazione della cassaforte (anche in "gara" tra due
    dispositivi), revisioni, conflitti, voci eliminate, riferimenti agli allegati, approvazioni.
  - **T2.2** Login con codice email: codice di 6 cifre valido 10 minuti, max 5 tentativi, conservato solo come impronta
    (HMAC), attesa di 30 s tra un invio e l'altro, limiti per email e per indirizzo IP. Le email non ammesse si comportano
    esattamente come quelle ammesse, così da fuori non si capisce quale email usi.
    Invio email via SMTP (iCloud / Gmail / altro) **provato contro un finto server di posta** con connessione cifrata e
    password: funziona. Modelli in italiano e inglese.
  - **T2.3** Dispositivi: stati `setup` → `pending` → `active`; approvazione con il protocollo a impegno (il server fa solo
    da postino), codice di emergenza, rinomina, uscita, disconnessione a distanza. Dopo 3 rifiuti in un'ora, stop di un'ora
    alle nuove richieste. Email di avviso quando un dispositivo viene collegato.
  - **T2.4** Sincronizzazione: voci cifrate con numero di revisione; scrittura accettata solo se il dispositivo parte
    dall'ultima versione, altrimenti risposta "conflitto" con la versione attuale. Notifiche istantanee via WebSocket.
  - **T2.5** Allegati a blocchi da 4 MB: **ripresa** dopo un'interruzione, verifica SHA-256, scaricamento anche parziale.
    Gli allegati non più usati vengono cancellati dopo 24 ore di "tolleranza", utile in caso di conflitti.
  - **T2.6** Protezioni: limiti di tentativi e di traffico, dimensioni massime, confronti a tempo costante, nessun segreto
    nei registri, header di sicurezza.
  - **T2.7** Backup notturno: copia coerente del database più gli allegati in una cartella condivisa (gli allegati non
    cambiano mai, quindi non si duplicano), conservazione di 30 giorni. Se il Mac era spento all'ora del backup, lo fa
    appena riparte.
  - **T2.8** Installazione guidata in italiano (`thevault-server setup`): email, invio email con prova reale, cartella dei
    backup (predefinita: iCloud Drive), avvio automatico (servizio macOS che si riavvia da solo), Tailscale Funnel per
    l'accesso da fuori casa con verifica finale. In più: `status`, `backup`, `uninstall`, `version`.
  - **Collaudo del programma vero**: avviato, codice richiesto, login fatto → ✅. Compila per Mac Apple Silicon e Intel.
  - 🟡 *Scivoloni (risolti)*:
    1. un mio test si aspettava l'oggetto dell'email "codificato", ma i testi senza accenti restano in chiaro (è il
       comportamento corretto): ho sbagliato l'aspettativa, non il codice;
    2. il test degli allegati provava a leggere come testo un file binario: aggiunto un controllo che guarda solo l'esito.
  - 📝 Cambiato rispetto al protocollo iniziale: l'eliminazione definitiva passa la revisione nell'indirizzo invece che nel
    corpo della richiesta, perché alcuni proxy scartano il corpo delle richieste DELETE (`PROTOCOL.md` aggiornato).
  - ⚠️ *Da verificare sul Mac mini vero* (qui non ho macOS): servizio `launchctl`, comandi di Tailscale Funnel, invio da
    iCloud. Il codice è pronto e testato con simulazioni; la prova reale sarà nella guida passo passo.
- **Test dopo la Fase 2**: `scripts/test-all.sh` → ✅ (server: 6 pacchetti di test verdi, con controllo delle "race";
  app: 3 test verdi).

- **Fase 3 ✅ Cuore dell'app** (Dart/Flutter, cartella `app/lib/src/core/`), senza grafica ma completo:
  - **T3.1 Crittografia** (libsodium): cifratura delle voci legata al loro identificativo e con lunghezza mascherata;
    kit di emergenza (Argon2id, calcolato in sottofondo per non bloccare l'app); impegno + codice di 6 cifre +
    consegna autenticata della chiave per l'approvazione; PIN; allegati cifrati a flusso. **14 test** verdi.
    - 🟢 *Falso allarme*: leggendo la libreria temevo che i file di dimensione esattamente multipla di 64 KB (o vuoti)
      restassero senza "segnale di fine" e quindi illeggibili. Leggendo tutto il codice ho visto che la libreria
      aggiunge da sola un blocco finale vuoto. L'ho comunque blindato con test su 0 byte, 64 KB−1, 64 KB, 64 KB+1… e su
      file troncati (rifiutati).
  - **T3.2 Modello e regole**: voce, righe (con occhio e link), allegati; **le tue regole di salvataggio** codificate e
    testate una per una (suggerimento che diventa chiave, righe solo-chiave eliminate, almeno una riga in modifica,
    titolo dal nome del sito…). Riconoscimento di indirizzi web ed email (`README.md` o `script.sh` non diventano link
    per sbaglio), ricerca e ordinamento senza accenti, generatore di password. **13 test** verdi.
    - 🟡 *Scivolone (risolto)*: un nome usato due volte nel codice (`isEmail`) impediva la compilazione. Rinominato.
  - **T3.3 Archivio locale** (SQLite): copia cifrata dei dati + coda delle modifiche da inviare, con un contatore che
    evita di perdere una modifica fatta mentre la precedente è in viaggio. **3 test** verdi.
  - **T3.4 Server e sincronizzazione**: client delle API, canale in tempo reale con riconnessione automatica, motore di
    sincronizzazione (invio, ricezione, allegati con ripresa e verifica, pulizia).
    **Conflitti risolti senza perdere nulla**: se un dispositivo ha solo messo una stella o cambiato un occhio, le due
    modifiche si **uniscono**; se entrambi hanno cambiato i contenuti, la tua versione diventa una copia
    "(conflitto)".
  - **T3.5 Flussi di accesso**: primo dispositivo, nuovo dispositivo con approvazione, codice di emergenza, nuovo kit,
    uscita.
  - **T3.6 Test end-to-end** con il **server vero** e 4 dispositivi simulati: creazione della cassaforte, approvazione con
    codici identici sui due schermi, tempo reale (meno di 1 secondo), conflitti, unione, allegati, cestino, eliminazione
    definitiva, codice di emergenza (anche sbagliato), revoca, intruso con la sola email bloccato. ✅ in 2 secondi.
  - 🔴→🟢 *Scivoloni trovati dal test end-to-end (tutti risolti)*:
    1. due scaricamenti dello stesso allegato potevano partire insieme e scrivere sullo stesso file → ora condividono un
       solo scaricamento;
    2. il canale in tempo reale, chiudendosi, provava a inviare un ultimo evento → ora tace dopo la chiusura;
    3. la pulizia degli allegati poteva toccare il database già chiuso → ora si ferma e viene attesa;
    4. il più subdolo: correggendo il punto 1 ho introdotto un'attesa **circolare** (un'operazione che aspettava sé
       stessa) e il test si bloccava. Trovato con tracce passo-passo e corretto, con un commento nel codice perché non
       si ripeta.
  - Aggiunta al server una "modalità test" (solo per i test automatici) che toglie l'attesa di 30 secondi tra i codici.
- **Test dopo la Fase 3**: `scripts/test-all.sh` → ✅ server 6/6 pacchetti, app **34 test** (inclusi end-to-end).
