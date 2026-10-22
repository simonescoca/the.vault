# Guida: il server di The Vault su un NVIDIA Jetson

Il server è il "punto d'incontro" dei tuoi dispositivi: tiene la copia **cifrata** delle password e la passa in tempo
reale a tutti i computer collegati. Invece del Mac mini può farlo un **NVIDIA Jetson** (per esempio un Jetson Orin
Nano 8 GB) sempre acceso. Non può leggere le tue password: conserva solo dati illeggibili.

Il server è lo stesso del Mac mini, con le stesse funzioni (backup notturni, accesso da fuori casa, aggiornamenti con un
comando). Cambia solo il modo di installarlo: questa guida. Va bene anche un altro computer Linux con systemd (per
esempio Ubuntu o Debian, a 64 bit).

Tempo necessario: circa **30 minuti**, una volta sola (più 10 minuti se devi creare la casella email del punto 2).

**Cosa ti serve**
- il Jetson con **JetPack 6 o più recente** (cioè Ubuntu; provato su un Jetson Orin Nano 8 GB con JetPack 7, Ubuntu
  24.04), già configurato con il tuo utente, acceso e collegato a internet (meglio con il cavo di rete);
- meglio se il sistema è su un **SSD NVMe** invece che sulla scheda microSD: è più veloce e dura di più;
- un computer da cui collegarti al Jetson (oppure tastiera e schermo collegati al Jetson);
- una **casella email da cui inviare i codici di accesso**: ti consiglio di crearne una **apposta**, gratis (punto 2).

---

## 1. Prepara il Jetson

### Collegati
Dal Mac, apri il **Terminale** e collegati al Jetson con il tuo utente. Al posto di `mario` e `jetson` metti il tuo nome
utente e il nome del Jetson: sul Jetson li mostrano i comandi `whoami` e `hostname` (per esempio
`ssh mario@jetson-orin.local`).

```
ssh mario@jetson.local
```

Se invece usi tastiera e schermo collegati al Jetson, apri l'app **Terminale**. Tutti i comandi di questa guida si
scrivono lì, **con il tuo utente**: `sudo` solo dove è scritto.

### Che non vada mai in stop
Copia questa riga e premi **Invio** (se la chiede, scrivi la password del tuo utente):

```
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

### Dopo un riavvio o un'interruzione di corrente
Il Jetson Orin Nano Developer Kit si riaccende da solo quando torna la corrente, e il server riparte da solo **senza che
nessuno faccia l'accesso** (sul Mac mini con FileVault, invece, serve un accesso).

Senza la batteria dell'orologio, dopo un'interruzione di corrente il Jetson riparte con la data sbagliata (1° gennaio
1970) finché non la riprende da internet, di solito entro un minuto: il server aspetta l'ora giusta prima di fare i
backup, e quello saltato durante la notte lo fa appena può.

### E la cifratura del disco?
Le tue password sono **sempre cifrate** sui tuoi dispositivi prima di partire: sul Jetson arrivano già illeggibili.
In chiaro, sul disco del Jetson, c'è solo la configurazione del server, che contiene la **password per le app** della
casella che invia i codici. Chi rubasse il Jetson potrebbe usarla per entrare in quella casella. Due possibilità:

| | Cosa fai | Pro | Contro |
|---|---|---|---|
| **A — consigliata** | Per inviare i codici usi una **casella email creata apposta** (punto 2: un nuovo account Gmail gratuito). I codici arrivano comunque alla **tua** email. | Chi rubasse il Jetson troverebbe solo la chiave di quella casella vuota. | Un account email in più. |
| **B — per esperti** | Cifri il disco del Jetson con la funzione **Disk Encryption** di NVIDIA (guida *Jetson Linux Developer Guide › Security*). | Tutto il disco è cifrato e il Jetson riparte da solo. | Si fa **reinstallando il sistema** da un PC con Ubuntu, e protegge davvero solo se sostituisci la chiave d'esempio di NVIDIA con una tua. |

Se usi lo stesso la tua casella di sempre, la configurazione te lo fa notare e chiede conferma.

## 2. Crea la casella per i codici e la sua password per le app

Il server invia i codici di accesso da una casella email. Per farlo gli serve una **password specifica per le app**
(non la password normale dell'account, che non va mai data a nessun programma).

**Gmail, con una casella nuova (consigliata, gratis)**
1. Crea l'account su **[accounts.google.com/signup](https://accounts.google.com/signup)**, per esempio
   `mario.thevault@gmail.com` (il nome lo scegli tu). Google potrebbe chiederti un numero di telefono.
2. Attiva la **verifica in due passaggi**:
   **[myaccount.google.com/signinoptions/two-step-verification](https://myaccount.google.com/signinoptions/two-step-verification)**.
3. Vai su **[myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)**, scrivi `The Vault` e
   conferma.

**iCloud** (se usi comunque una casella iCloud): **[account.apple.com](https://account.apple.com)** › **Accesso e
sicurezza › Password specifiche per le app** › **+**, scrivi `The Vault` e conferma.

Compare una password del tipo `abcd efgh ijkl mnop` (Google) o `abcd-efgh-ijkl-mnop` (Apple): **lasciala aperta**, ti
servirà tra poco. Non scriverla da nessun'altra parte.

## 3. Installa Tailscale (per usare The Vault fuori casa)

Tailscale rende il Jetson raggiungibile da internet **in modo sicuro**, con indirizzo e certificato HTTPS automatici,
senza toccare il router. Per uso personale è gratuito.

1. Installalo:

   ```
   curl -fsSL https://tailscale.com/install.sh | sh
   ```

2. Collegalo al tuo account (se non ce l'hai, lo crei in quel momento):

   ```
   sudo tailscale up
   ```

   Compare un link: aprilo nel browser (anche dal Mac) e accedi (va bene il tuo account Apple, Google o Microsoft).
   Da questo momento Tailscale parte da solo a ogni accensione.

3. **Togli la scadenza della chiave** (importante): Tailscale, di serie, chiede di rifare l'accesso ogni 180 giorni, e
   da quel giorno The Vault non sarebbe più raggiungibile da fuori casa. Apri
   **[login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines)**, accanto al Jetson premi **⋯** e
   scegli **Disable key expiry**. Lì vedi anche il **nome** del Jetson (es. `jetson-orin`): fa parte dell'indirizzo del
   server, quindi non cambiarlo dopo aver collegato le app.

## 4. Installa il server

1. Copia questa riga, incollala nel terminale e premi **Invio** (**senza** `sudo` davanti):

   ```
   curl -fsSL https://github.com/simonescoca/the.vault/releases/latest/download/install-server.sh | bash
   ```

2. Parte la **configurazione guidata** (5 passi). Per accettare la proposta tra `[parentesi quadre]` basta premere Invio.

   | Passo | Cosa fare |
   |---|---|
   | **1/5 La tua email** | Scrivi la **tua** email: sarà l'unica ammessa, e lì arriveranno i codici. |
   | **2/5 Invio delle email** | Premi Invio per **2) Gmail** (oppure scegli **1) iCloud**), poi scrivi l'indirizzo **da cui** inviare: la casella creata al punto 2. Incolla la password per le app (**mentre la incolli non compare nulla: è normale**; gli spazi della password di Google non contano) e premi Invio. Ti arriva un'email di prova: controlla anche lo Spam. |
   | **3/5 Backup automatici** | Premi Invio: i backup vanno nella cartella **thevault-backup** della tua Home. |
   | **4/5 Avvio automatico** | Se te la chiede, scrivi la **password del tuo utente** (quella di `sudo`): serve una volta sola, perché il server parta da solo a ogni accensione. |
   | **5/5 Accesso da fuori casa** | Se te la chiede, di nuovo la password del tuo utente. Se compare un link, aprilo nel browser e conferma l'attivazione di **Funnel** su Tailscale (si fa una volta sola), poi torna al terminale. |

3. Alla fine compare **Fatto! 🎉** con l'**indirizzo del server**, per esempio:

   ```
   jetson-orin.tail1234.ts.net
   ```

   **Scrivilo**: lo inserirai nell'app (vedi la [guida dell'app](guida-app.md)).

4. **Prova da fuori casa**: da un telefono con i **dati mobili** (non il Wi-Fi di casa) apri
   `https://jetson-orin.tail1234.ts.net/v1/health` (con il tuo indirizzo): deve comparire una riga con `"thevault"`.
   È la prova che il server è raggiungibile da internet; dal Jetson stesso non si può verificare.

> Se il certificato HTTPS non è ancora pronto, il passo 5 dice «non risponde ancora»: è normale nei primi minuti.
> Controlla più tardi con il comando del punto 5.

## 5. Controllare che tutto funzioni

Apri un **nuovo** terminale (o una nuova sessione `ssh`) e scrivi:

```
thevault-server status
```

Vedrai qualcosa come:

```
The Vault — stato del server
  Dati:             /home/mario/.thevault-server
  Email ammessa:    mario.rossi@icloud.com
  Invio email:      smtp.gmail.com
  Server locale:    ✓ attivo su http://127.0.0.1:8743
  Avvio automatico: ✓ parte da solo a ogni accensione
  Tailscale:        ✓ collegato (jetson-orin.tail1234.ts.net), chiave senza scadenza
  Fuori casa:       ✓ https://jetson-orin.tail1234.ts.net (prova da un telefono con i dati mobili)
  Indirizzo per l'app: jetson-orin.tail1234.ts.net
  Backup:           ✓ ultimo riuscito il 02/10/2026 03:30 in /home/mario/thevault-backup
```

Tutte le righe con **✓** vogliono dire che è tutto a posto. Una **✗** o una **⚠** spiega cosa non va (vedi «Se qualcosa
non va»).

## 6. Aggiornare il server

Quando esce una nuova versione, ripeti **lo stesso comando del punto 4.1**. Il programma si accorge che il server è già
configurato: fa un **backup di sicurezza**, installa la nuova versione, la riavvia e controlla che risponda. Se la
nuova versione non parte, **rimette da solo quella di prima** e te lo dice (se però aveva già aggiornato il database
resta installata, e il messaggio ti dice dov'è il backup fatto un attimo prima). Nessuna domanda (nemmeno la password),
dati e impostazioni restano.

## 7. Backup

- Ogni notte (alle 3:30, o appena il Jetson si riaccende se era spento) il server salva una copia nella cartella
  **thevault-backup** della tua Home. Le copie degli ultimi 30 giorni restano, quelle più vecchie vengono tolte.
- Sono dati **già cifrati**: anche se qualcuno li prendesse non potrebbe leggerli senza il tuo codice di emergenza.
- **Una copia fuori dal Jetson**: ogni tanto, dal Mac, nel Terminale:

  ```
  rsync -a mario@jetson.local:thevault-backup/ ~/"The Vault Backup Jetson"/
  ```

- **Il paracadute più semplice**: ogni tanto, dall'app, **Impostazioni › Backup › Esporta…** e conserva il file (per
  esempio su iCloud Drive). Contiene tutte le voci e gli allegati, protetti da una password che scegli tu, e si può
  reimportare in qualsiasi momento. È questo il modo previsto per ripartire da zero: le copie notturne del server
  servono per i casi gravi e vanno ripristinate a mano.
- Backup immediato: `thevault-server backup`.

## 8. Modificare la configurazione

Per cambiare email, password per le app o cartella dei backup:

```
thevault-server setup
```

Le risposte già date sono proposte tra parentesi: cambia solo quello che ti serve.

## Hai già il server sul Mac mini?

L'indirizzo del server è salvato in ogni app, quindi per passare al Jetson:

1. dall'app, **Impostazioni › Backup › Esporta…** e conserva il file;
2. installa il server sul Jetson con questa guida;
3. su ogni computer, **Impostazioni › Account › Esci da questo dispositivo**, poi ricollegalo con l'indirizzo del
   Jetson: il primo computer crea una cassaforte nuova (con un nuovo kit di emergenza) e lì fai **Importa…** del file
   del punto 1; gli altri si collegano con l'approvazione, come al solito (vedi la [guida dell'app](guida-app.md));
4. sul Mac mini, `thevault-server uninstall`.

## Se qualcosa non va

| Problema | Soluzione |
|---|---|
| L'email con il codice non arriva | Guarda nello Spam. Poi ricontrolla la password per le app con `thevault-server setup` (passo 2). |
| L'app dice «Server non raggiungibile» | Il Jetson è acceso e collegato? Controlla con `thevault-server status` e `tailscale status`. |
| `status` dice «⚠ si ferma quando chiudi la sessione» | Il passo 4 non ha avuto il permesso: `sudo loginctl enable-linger $USER` |
| `status` dice «Tailscale: ⚠ la chiave … scade il …» | Togli la scadenza come al punto 3.3. Se è già scaduta: `sudo tailscale up`, poi togli la scadenza. |
| `status` dice «Fuori casa: ⚠ … risponde solo ai dispositivi con Tailscale» | Funnel è spento: riesegui `thevault-server setup` (al passo 5 conferma Funnel se compare un link). |
| `status` dice «Fuori casa: ✗ … non raggiungibile» | Nei primi minuti dopo l'installazione è normale (certificato). Poi controlla `tailscale status`. |
| `thevault-server: command not found` | Apri un **nuovo** terminale (quello in cui hai installato non conosce ancora il comando), oppure scrivi `~/.thevault-server/bin/thevault-server status`. |
| «esegui il comando con il tuo utente, senza sudo» | Riscrivi il comando senza `sudo` davanti: il server gira con il tuo utente. |
| «La configurazione fa alcune domande: apri il Terminale…» | Il comando del punto 4.1 va scritto in un terminale vero (Terminale o `ssh`), non dentro un altro programma. |
| «non trovo i servizi del tuo utente» | Collegati direttamente con il tuo utente (`ssh mario@jetson.local`), non con `sudo` o `su`, e riprova. |
| `status` dice «Avvio automatico: ? non verificabile» | Stessa cosa: collegati direttamente con il tuo utente e riprova. |
| Backup «non è riuscito» in `status` | Esegui `thevault-server setup` e al passo 3 premi Invio per la cartella proposta. |
| Backup «⚠ … più di un giorno fa» in `status` | Il server è rimasto spento? Se il messaggio resta, guarda il registro (sotto). |

Il registro del server è in `~/.thevault-server/server.log` (per seguirlo dal vivo: `tail -f ~/.thevault-server/server.log`).

## Togliere il server

`thevault-server uninstall` toglie l'avvio automatico (i dati restano nella cartella `~/.thevault-server`). Per
spegnere anche l'accesso da fuori casa (toglie tutto quello che questo computer pubblica con Tailscale):

```
sudo tailscale funnel reset
```
