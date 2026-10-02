# The Vault — Specifiche funzionali (desktop v1)

Documento di riferimento per lo sviluppo: descrive **cosa vede e cosa può fare l'utente**, schermata per schermata.
Le scelte vengono dalle risposte riportate in `todo.md` (sezione 1). Sicurezza: `SECURITY.md`. Protocollo: `PROTOCOL.md`.
Aspetto: `DESIGN.md`.

Testi dell'interfaccia: in **italiano** e **inglese**. In questo documento sono riportati in italiano.

---

## 1. Concetti

- **Voce**: è una "password" nel senso dell'utente. Contiene un **titolo**, una lista ordinata di **righe chiave/valore**,
  una **descrizione** facoltativa e degli **allegati** facoltativi. Può essere **preferita** e può stare nel **cestino**.
- **Riga**: una coppia **chiave** (testo libero, es. "email") e **valore** (testo libero, es. "mario@rossi.it").
  Ogni riga ha due proprietà in più:
  - **nascosta** sì/no: il valore viene mostrato con i pallini `••••••••`. Di default è **no**.
  - **link** (facoltativo): un indirizzo web associato al valore. Il valore diventa un testo cliccabile che apre l'indirizzo.
- **Dispositivo**: un computer (in futuro un telefono) collegato all'account. Il primo è collegato con il solo codice email;
  i successivi devono essere **approvati da un dispositivo già collegato** oppure con il **codice di emergenza**.

---

## 2. Primo avvio (onboarding)

Sequenza a schermo intero, centrata, essenziale. In ogni passo c'è "Indietro" quando ha senso.

1. **Benvenuto** — logo, "The Vault", sottotitolo "Le tue password, al sicuro, ovunque.", pulsante **Inizia**.
2. **Server** — "Indirizzo del tuo server" (es. `mac-mini.tail1234.ts.net`). Il pulsante **Continua** verifica che il server
   risponda. Se manca `https://` viene aggiunto da solo. Errori: "Server non raggiungibile", "Questo non è un server The Vault".
3. **Email** — "La tua email", pulsante **Invia codice**.
4. **Codice** — 6 caselle per il codice ricevuto via email (si può incollare). Il codice si verifica da solo quando è completo.
   "Non è arrivato? **Invia di nuovo**" (attivo dopo 30 secondi). Errori: "Codice errato", "Codice scaduto".
5. A questo punto le strade sono due.
   - **5A — Account nuovo** (primo dispositivo): viene creata la cassaforte, poi si apre il **Kit di emergenza**:
     il codice di emergenza in grande, in monospace, a gruppi (es. `K7QM-3XRP-9HTV-…`), con la spiegazione
     "Conservalo in un posto sicuro (stampato, o in un luogo che non sia questo computer). Ti servirà solo se perdi
     l'accesso a tutti i tuoi dispositivi. Senza questo codice e senza un dispositivo collegato, i dati non sono recuperabili."
     Pulsanti: **Salva PDF**, **Copia**. Casella "Ho conservato il codice in un posto sicuro", obbligatoria per **Continua**.
   - **5B — Account esistente** (nuovo dispositivo): schermata **Conferma questo dispositivo**:
     "Apri The Vault su un dispositivo già collegato: ti chiederà di approvare questo accesso." Poi, appena l'altro
     dispositivo risponde, compare il **codice di verifica** (6 cifre, es. `482 917`) con la scritta "Controlla che
     sull'altro dispositivo compaia lo stesso codice, poi approva da lì". Quando arriva l'approvazione si prosegue da soli.
     Link in basso: **Non ho altri dispositivi** → inserimento del **codice di emergenza** → si prosegue.
     Se l'altro dispositivo rifiuta: "Accesso rifiutato" e si torna all'inizio.
6. **PIN** — "Scegli un PIN di 6 cifre", poi "Ripeti il PIN". Serve quando la biometria non è disponibile.
7. **Touch ID / Windows Hello** — solo se il computer lo supporta: "Vuoi sbloccare The Vault con Touch ID?"
   **Attiva** / **Non ora**.
8. Si apre la finestra principale. Se l'account è nuovo, l'elenco è vuoto con l'invito a creare la prima voce.

Il login non viene **mai** più richiesto su quel dispositivo, a meno che il dispositivo venga disconnesso.

---

## 3. Blocco e sblocco

- L'app parte **bloccata**. Schermata di blocco: logo, "The Vault è bloccato".
  - Con biometria attiva: la richiesta di Touch ID / Windows Hello parte da sola; c'è il pulsante **Sblocca** per riprovare
    e il link **Usa il PIN**.
  - Senza biometria: tastierino del **PIN** (6 pallini; si può digitare dalla tastiera).
- PIN errato: piccolo scuotimento e "PIN errato". Dal 5° errore: attesa crescente (30 s, 1 min, 2 min, 5 min…)
  e "Tentativi rimasti: N". Al **10° errore** il dispositivo **si scollega** da solo: dati locali cancellati,
  si torna al primo avvio. I dati restano al sicuro sul server.
- **Blocco automatico**: dopo **5 minuti** senza attività (impostabile: 1, 5, 15, 30, 60 minuti), quando il computer va in
  stop, e con **⌘L / Ctrl+L**. Bloccando si cancellano dalla memoria la chiave e i dati in chiaro.
- Se arriva una richiesta di approvazione mentre l'app è bloccata, la schermata di blocco mostra
  "1 richiesta di accesso in attesa": va sbloccata per rispondere.

---

## 4. Finestra principale — tre colonne

```
┌────────────┬──────────────────────┬──────────────────────────────────────┐
│ (semafori) │ [ Cerca          ] + │                    ☆   Modifica   ⋯  │
│            ├──────────────────────┤                                      │
│ Tutte   24 │ [N] Netflix          │  Netflix                             │
│ Preferiti 3│     simone@icloud…   │                                      │
│ Cestino  2 │ [A] Amazon           │  sito web     netflix.com            │
│            │     simone@icloud…   │  email        simone@icloud.com      │
│            │ ...                  │  password     ••••••••••••           │
│            │                      │                                      │
│ ⚙ Impost.  │                      │  Account di famiglia.                │
│ ● Sincron. │                      │  📎 contratto.pdf  1,2 MB            │
└────────────┴──────────────────────┴──────────────────────────────────────┘
```

### 4.1 Menu (colonna sinistra)
- **Tutte** (con il numero di voci), **Preferiti** (numero), **Cestino** (numero). Una sola sezione attiva.
- In basso: **Impostazioni** e lo **stato di sincronizzazione**: "Sincronizzato", "Sincronizzazione…", "Offline — le
  modifiche verranno inviate appena possibile", "Server non raggiungibile".

### 4.2 Elenco (colonna centrale)
- In alto il campo **Cerca** (⌘F / Ctrl+F) e il pulsante **+** (Nuova voce, ⌘N / Ctrl+N).
- Ordine **alfabetico** per titolo, ignorando maiuscole e accenti.
- Ogni riga dell'elenco mostra:
  - l'**icona del sito** se la voce contiene un sito (vedi §8), altrimenti l'**iniziale** del titolo in un quadratino;
  - il **titolo**;
  - un **sottotitolo** grigio: il valore della prima riga che sembra un nome utente o un'email (chiave tipo
    "email", "utente", "username", "login", "account", oppure valore con forma di email) e che non sia nascosta.
- **Ricerca** istantanea mentre si scrive, su: titolo, chiavi, valori **non nascosti**, descrizione, nomi degli allegati.
  Ignora maiuscole e accenti. Prima i risultati che corrispondono nel titolo. Esc svuota la ricerca.
- Frecce ↑/↓ per muoversi tra le voci.
- Stati vuoti: "Ancora nessuna password. Creane una con +", "Nessun risultato per «…»", "Nessun preferito",
  "Il cestino è vuoto".

### 4.3 Dettaglio (colonna destra)
- Nessuna voce selezionata: logo tenue al centro.
- Voce selezionata: vedi §5 (visualizzazione) e §6 (modifica).

---

## 5. Visualizzare una voce

- In alto a destra: **stella** (preferito sì/no, salva subito), **Modifica** (⌘E / Ctrl+E), menu **⋯** con **Elimina**.
- **Titolo** grande e marcato.
- **Righe affiancate**: chiave a sinistra (grigia, sans-serif), valore a destra (monospace), allineati in colonna.
  La colonna delle chiavi è larga quanto la chiave più lunga, entro un massimo; le chiavi lunghe vanno a capo.
- **Clic sul valore** = copia negli appunti, con il messaggio "Copiato". Gli appunti si svuotano dopo 1 minuto
  (se contengono ancora quel valore).
- **Occhio** su ogni riga: occhio aperto = valore visibile, occhio barrato = valore nascosto con i pallini.
  Il clic cambia stato e **lo salva subito** (si sincronizza con gli altri dispositivi). L'occhio si vede al passaggio
  del mouse; sulle righe nascoste resta sempre visibile. Un valore nascosto si copia comunque con un clic.
- **Indirizzi web**: se il valore è un indirizzo (`https://…`, `http://…`, `www.…` oppure un dominio come `netflix.com`)
  è mostrato come link: il clic **apre il browser**. Un'icona "copia" accanto permette di copiarlo.
  Se manca `https://` viene aggiunto all'apertura.
- **Testo con link**: se la riga ha un link associato, il valore è mostrato come link; il clic apre l'indirizzo associato.
  Al passaggio del mouse compare l'indirizzo. L'icona "copia" copia il testo; il menu del tasto destro offre anche
  "Copia link".
- **Email**: mai trasformate in link in automatico (niente apertura del programma di posta): il clic le copia come
  qualsiasi altro valore. Se però associ tu, di proposito, un link a quella riga, vale il link che hai scelto.
- Valori su più righe: mostrati così come sono.
- **Descrizione**: sotto le righe, nel font delle chiavi, colore pieno. Assente se vuota.
- **Allegati**: elenco con icona del tipo, nome e dimensione. Clic → si apre con l'app predefinita del computer.
  Tasto destro / menu: **Apri**, **Salva una copia…**. Le immagini mostrano una piccola anteprima.
  Se l'allegato non è ancora scaricato, mostra l'avanzamento. Assente se non ci sono allegati.
- Voce **nel cestino**: tutto in sola lettura, con la fascia "Questa voce è nel cestino" e i pulsanti
  **Ripristina** ed **Elimina definitivamente**.

---

## 6. Creare e modificare una voce

### 6.1 Nuova voce
- **+** o ⌘N apre il dettaglio in modifica con:
  - **titolo** vuoto (aiuto grigio: "Titolo") e cursore già nel titolo;
  - **3 righe vuote** con le chiavi suggerite in grigio: **sito web**, **email**, **password**
    (in inglese: **website**, **email**, **password**);
  - il campo **descrizione** vuoto;
  - la zona **allegati** ("Trascina qui i file o **scegli…**").

### 6.2 Modifica
- **Modifica** trasforma il dettaglio in un modulo, nello stesso posto (niente finestre in più):
  - titolo modificabile;
  - per ogni riga: maniglia di trascinamento (per **riordinare**), chiave, valore (monospace), occhio, pulsante
    **link** (associa o rimuove un indirizzo al valore), pulsante **genera password** (vedi §6.4), pulsante **rimuovi** (−);
  - **+ Aggiungi riga** sotto l'ultima riga: la nuova riga ha come aiuti generici "chiave" e "valore"
    (che non vengono adottati);
  - **descrizione** (testo libero su più righe), sempre presente in modifica;
  - **allegati**: quelli esistenti (con **rimuovi**) e la zona per aggiungerne altri (trascinamento o "scegli…").
- Il pulsante **rimuovi** è disattivato quando resta **una sola riga**.
- In alto: **Annulla** (Esc) e **Salva** (⌘S / Ctrl+S). Annullando con modifiche non salvate:
  "Vuoi scartare le modifiche?".
- Tab passa da chiave a valore alla riga successiva; Invio nel valore dell'ultima riga aggiunge una riga;
  Maiusc+Invio va a capo nel valore.

### 6.3 Regole di salvataggio (in quest'ordine)
1. Gli spazi all'inizio e alla fine di chiavi e titolo vengono tolti. I valori restano come sono, tranne le righe
   composte solo da spazi, che contano come vuote.
2. Riga con **chiave vuota** e **valore pieno**:
   - se la riga ha una chiave **suggerita** (le 3 iniziali), la chiave diventa il suggerimento (es. "password");
   - altrimenti la riga resta **senza chiave**.
3. Riga con **valore vuoto** (con o senza chiave): **eliminata**.
4. Una voce può restare **senza righe** (es. solo titolo, descrizione e allegati): in modifica ricomparirà una riga vuota.
5. **Titolo vuoto**: se nella voce c'è un sito, il titolo diventa il nome del sito (`www.netflix.com` → "Netflix");
   altrimenti il salvataggio si ferma con "Dai un titolo a questa voce" e il cursore va nel titolo.
6. **Descrizione** vuota: sparisce dalla visualizzazione (ricompare in modifica).
7. Il **link** associato a una riga: se manca `https://` viene aggiunto; se il testo non è un indirizzo valido il link
   non si salva e compare un avviso.
8. Le proprietà **nascosta** e **link** restano legate alla loro riga anche se le righe vengono riordinate.

### 6.4 Generatore di password
- In modifica, il pulsante **genera** nel valore apre un piccolo pannello:
  anteprima della password (monospace), **lunghezza** (8–64, predefinita 20), interruttori **A–Z**, **a–z**, **0–9**,
  **simboli** (tutti attivi di default; almeno uno resta attivo), **Rigenera**, **Usa**.
  "Usa" scrive la password nel valore. Il generatore usa una fonte casuale crittografica e garantisce almeno un carattere
  per ogni gruppo attivo.

### 6.5 Allegati in modifica
- Qualsiasi tipo di file, fino a **200 MB** l'uno. Si possono aggiungere più file insieme, trascinandoli in qualsiasi
  punto del dettaglio in modifica oppure con "scegli…".
- I file aggiunti vengono **cifrati subito** sul computer; l'invio al server avviene in sottofondo, anche dopo,
  se si è offline.
- Rimuovere un allegato in modifica lo toglie al salvataggio. Il file sul server viene eliminato quando la voce non lo
  usa più.

---

## 7. Preferiti, eliminazione e cestino

- **Preferito**: stella nel dettaglio; la voce compare anche in "Preferiti".
- **Elimina** (menu ⋯ o ⌘⌫ / Canc): la voce va nel **cestino**, senza conferma, con il messaggio
  "Spostata nel cestino — **Annulla**" per qualche secondo.
- **Cestino**: elenca le voci eliminate (sottotitolo: "Eliminata il 2 ott 2026"). Per ogni voce: **Ripristina**,
  **Elimina definitivamente** (con conferma: "Eliminare definitivamente «Netflix»? Non si potrà recuperare.").
  In alto: **Svuota cestino** (con conferma). Le voci nel cestino **non** si cancellano mai da sole.
- Le voci nel cestino non compaiono in "Tutte" né in "Preferiti" e la ricerca non le trova (tranne quando si è nel cestino).

---

## 8. Icone dei siti

- Se una voce contiene un indirizzo web (in un valore o in un link), l'elenco mostra l'icona di quel sito.
  Se ce ne sono più di uno, vale il primo nell'ordine delle righe.
- L'icona viene scaricata **direttamente dal sito** (non da servizi di terzi), salvata sul computer e riusata.
  Si riprova al massimo una volta al giorno se non è disponibile.
- Finché l'icona non c'è, o se il sito non ne ha: **iniziale** del titolo in un quadratino grigio tenue.

---

## 9. Sincronizzazione, offline e conflitti

- Ogni modifica (salvataggio, preferito, occhio, cestino) è salvata **subito sul computer** e inviata al server.
  Gli altri dispositivi la ricevono **in tempo reale**.
- **Offline**: tutto funziona (consultazione, modifica, creazione, allegati). Le modifiche partono appena torna la
  connessione. Lo stato è visibile in basso nel menu.
- **Conflitto** (la stessa voce modificata su due dispositivi prima che si siano sincronizzati): nessuna perdita.
  La versione arrivata prima al server resta la voce originale; l'altra diventa una **copia** con il titolo
  "Netflix (conflitto)". Messaggio: "Una voce è stata modificata su due dispositivi: ho tenuto entrambe le versioni."
- Se si sta **modificando** una voce e nel frattempo un altro dispositivo la cambia, al salvataggio compare:
  "Questa voce è stata modificata su un altro dispositivo mentre la stavi modificando." **Sovrascrivi** /
  **Tieni entrambe** / **Annulla**.

---

## 10. Approvare un nuovo dispositivo

- Quando un nuovo dispositivo chiede l'accesso, su tutti i dispositivi collegati e sbloccati compare una finestra:
  "**Nuovo accesso**: «MacBook di Simone» (macOS) vuole accedere al tuo The Vault."
  Subito dopo compare il **codice di verifica** (6 cifre) con
  "Controlla che sul nuovo dispositivo compaia lo stesso codice."
  Pulsanti: **Rifiuta**, **Approva**.
- Se il codice non coincide, bisogna premere Rifiuta: qualcuno potrebbe star tentando di intromettersi.
- Basta l'approvazione di un dispositivo; sugli altri la finestra si chiude da sola.
- Ogni dispositivo collegato riceve anche un'**email di avviso** ("Nuovo dispositivo collegato al tuo The Vault").

---

## 11. Impostazioni

Finestra a schede (⌘, / Ctrl+,):

- **Generale**
  - Aspetto: **Sistema** / Chiaro / Scuro.
  - Lingua: **Sistema** / Italiano / English. Se la lingua di sistema non è l'italiano, si usa l'inglese.
- **Sicurezza**
  - Sblocco con Touch ID / Windows Hello: sì/no (se disponibile).
  - Cambia PIN (chiede il PIN attuale).
  - Blocco automatico: 1 / **5** / 15 / 30 / 60 minuti.
  - Svuota appunti dopo: 30 secondi / **1 minuto** / 2 minuti / 5 minuti / mai.
  - Kit di emergenza: **Genera un nuovo codice** (il vecchio smette di funzionare; si apre di nuovo la schermata del kit).
- **Dispositivi**
  - Elenco: nome, sistema, ultimo accesso, "questo dispositivo". **Rinomina** (questo dispositivo).
    **Disconnetti** (gli altri): il dispositivo perde subito l'accesso e cancella i suoi dati locali appena può.
- **Backup**
  - **Esporta…**: chiede una password per il file (due volte, con indicatore di robustezza), poi dove salvarlo.
    Crea `TheVault-Backup-AAAA-MM-GG.thevault` con tutte le voci (comprese quelle nel cestino) e gli allegati, cifrati.
  - **Importa…**: sceglie un file `.thevault`, chiede la password, mostra "N voci, M allegati" e importa.
    Voci già presenti (stessa voce): resta la versione modificata più di recente.
- **Account**
  - Email, indirizzo del server, versione dell'app.
  - **Esci da questo dispositivo**: con conferma; cancella tutti i dati locali di questo dispositivo.

---

## 12. Scorciatoie da tastiera

| Azione | macOS | Windows |
|---|---|---|
| Nuova voce | ⌘N | Ctrl+N |
| Cerca | ⌘F | Ctrl+F |
| Modifica | ⌘E | Ctrl+E |
| Salva | ⌘S | Ctrl+S |
| Annulla modifica / svuota ricerca | Esc | Esc |
| Sposta nel cestino | ⌘⌫ | Canc |
| Blocca | ⌘L | Ctrl+L |
| Impostazioni | ⌘, | Ctrl+, |
| Voce precedente / successiva | ↑ / ↓ | ↑ / ↓ |

---

## 13. Messaggi e conferme

- Messaggi brevi in basso al centro, per 2–4 secondi: "Copiato", "Salvata", "Spostata nel cestino — Annulla",
  "Ripristinata", "Allegato aggiunto", "Gli appunti sono stati svuotati".
- Conferme solo per le azioni **irreversibili**: eliminazione definitiva, svuota cestino, esci dal dispositivo,
  disconnetti un dispositivo, nuovo codice di emergenza, scartare modifiche.

---

## 14. Fuori da questa versione

Autofill nei siti (fase successiva), app mobile, cronologia delle modifiche, codici 2FA, import da Password di Apple,
accesso rapido da tastiera globale.
