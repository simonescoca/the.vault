# Guida: il server di The Vault su un NVIDIA Jetson

Il server è il "punto d'incontro" dei tuoi dispositivi: tiene la copia **cifrata** delle password e la passa in tempo
reale a tutti i computer collegati. Invece del Mac mini può farlo un **NVIDIA Jetson** (per esempio un Jetson Orin
Nano 8 GB) sempre acceso. Non può leggere le tue password: conserva solo dati illeggibili.

Il server è lo stesso del Mac mini, con le stesse funzioni (backup notturni, accesso da fuori casa, aggiornamenti con un
comando). Cambia solo il modo di installarlo: questa guida. Va bene anche un altro computer Linux con systemd (per
esempio Ubuntu o Debian, a 64 bit).

Tempo necessario: circa **30 minuti**, una volta sola.

**Cosa ti serve**
- il Jetson con **JetPack 6 o più recente** (cioè Ubuntu), già configurato con il tuo utente, acceso e collegato a
  internet (meglio con il cavo di rete);
- meglio se il sistema è su un **SSD NVMe** invece che sulla scheda microSD: è più veloce e dura di più;
- un computer da cui collegarti al Jetson (oppure tastiera e schermo collegati al Jetson);
- un indirizzo email per inviare i codici di accesso (vedi il punto 2: ti consiglio una casella **dedicata**).

---

## 1. Prepara il Jetson

### Collegati
Dal Mac, apri il **Terminale** e collegati al Jetson con il tuo utente (al posto di `mario` e `jetson` metti il tuo
nome utente e il nome del Jetson):

```
ssh mario@jetson.local
```

Se invece usi tastiera e schermo collegati al Jetson, apri l'app **Terminale**. Tutti i comandi di questa guida si
scrivono lì, **con il tuo utente**: `sudo` solo dove è scritto.

### Che non vada mai in stop
Copia questa riga e premi **Invio** (chiede la password del tuo utente):

```
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

### Dopo un riavvio o un'interruzione di corrente
Il Jetson Orin Nano Developer Kit si riaccende da solo quando torna la corrente, e il server riparte da solo **senza che
nessuno faccia l'accesso** (sul Mac mini con FileVault, invece, serve un accesso).

### E la cifratura del disco?
Le tue password sono **sempre cifrate** sui tuoi dispositivi prima di partire: sul Jetson arrivano già illeggibili.
In chiaro, sul disco del Jetson, c'è solo la configurazione del server, che contiene la **password per le app** della
casella che invia i codici. Chi rubasse il Jetson potrebbe usarla per entrare in quella casella. Due possibilità:

| | Cosa fai | Pro | Contro |
|---|---|---|---|
| **A — consigliata** | Per inviare i codici usi una **casella email creata apposta** (per esempio un nuovo account Gmail gratuito). I codici arrivano comunque alla **tua** email. | Chi rubasse il Jetson troverebbe solo la chiave di quella casella vuota. | Un account email in più. |
| **B — per esperti** | Cifri il disco del Jetson con la funzione **Disk Encryption** di NVIDIA (guida *Jetson Linux Developer Guide › Security*). | Tutto il disco è cifrato e il Jetson riparte da solo. | Si fa **reinstallando il sistema** da un PC con Ubuntu, e protegge davvero solo se sostituisci la chiave d'esempio di NVIDIA con una tua. |

Puoi anche usare la tua casella di sempre, come sul Mac mini: funziona allo stesso modo.

## 2. Crea la password per le app

Il server invia i codici di accesso da una casella email. Per farlo gli serve una **password specifica per le app**
(non la password normale dell'account, che non va mai data a nessun programma).

- **Gmail** (consigliata per una casella dedicata): attiva la verifica in due passaggi, poi vai su
  **[myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)**, scrivi `The Vault` e conferma.
- **iCloud**: **[account.apple.com](https://account.apple.com)** › **Accesso e sicurezza › Password specifiche per le
  app** › **+**, scrivi `The Vault` e conferma.

Compare una password del tipo `abcd-efgh-ijkl-mnop`: **lasciala aperta**, ti servirà tra poco.

## 3. Installa Tailscale (per usare The Vault fuori casa)

Tailscale rende il Jetson raggiungibile da internet **in modo sicuro**, con indirizzo e certificato HTTPS automatici,
senza toccare il router. Per uso personale è gratuito.

1. Installalo:

   ```
   curl -fsSL https://tailscale.com/install.sh | sh
   ```

2. Collegalo al tuo account:

   ```
   sudo tailscale up
   ```

   Compare un link: aprilo nel browser (anche dal Mac) e accedi (va bene il tuo account Apple, Google o Microsoft).
   Da questo momento Tailscale parte da solo a ogni accensione.

## 4. Installa il server

1. Copia questa riga, incollala nel terminale e premi **Invio** (**senza** `sudo` davanti):

   ```
   curl -fsSL https://github.com/simonescoca/the.vault/releases/latest/download/install-server.sh | bash
   ```

2. Parte la **configurazione guidata** (5 passi). Per accettare la proposta tra `[parentesi quadre]` basta premere Invio.

   | Passo | Cosa fare |
   |---|---|
   | **1/5 La tua email** | Scrivi la **tua** email: sarà l'unica ammessa, e lì arriveranno i codici. |
   | **2/5 Invio delle email** | Scegli **2) Gmail** o **1) iCloud**, poi scrivi l'indirizzo **da cui** inviare (la casella dedicata, se l'hai creata). Incolla la password per le app del punto 2 (**mentre la incolli non compare nulla: è normale**) e premi Invio. Ti arriva un'email di prova: controlla anche lo Spam. |
   | **3/5 Backup automatici** | Premi Invio: i backup vanno nella cartella **thevault-backup** della tua Home. |
   | **4/5 Avvio automatico** | Se te la chiede, scrivi la **password del tuo utente** (quella di `sudo`): serve una volta sola, perché il server parta da solo a ogni accensione. |
   | **5/5 Accesso da fuori casa** | Se te la chiede, di nuovo la password del tuo utente. Se compare un link, aprilo nel browser e conferma l'attivazione di **Funnel** su Tailscale (si fa una volta sola), poi torna al terminale. |

3. Alla fine compare **Fatto! 🎉** con l'**indirizzo del server**, per esempio:

   ```
   jetson.tail1234.ts.net
   ```

   **Scrivilo**: lo inserirai nell'app (vedi la [guida dell'app](guida-app.md)).

> Se il certificato HTTPS non è ancora pronto, il passo 5 dice «non ancora raggiungibile»: è normale nei primi minuti.
> Controlla più tardi con il comando del punto 5.

## 5. Controllare che tutto funzioni

Apri una **nuova** sessione (un nuovo `ssh mario@jetson.local`, o un nuovo terminale) e scrivi:

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
  Fuori casa:       ✓ https://jetson.tail1234.ts.net
  Indirizzo per l'app: jetson.tail1234.ts.net
  Backup:           ✓ ultimo riuscito il 02/10/2026 03:30 in /home/mario/thevault-backup
```

Tutte le righe con **✓** vogliono dire che è tutto a posto. Una **✗** o una **⚠** spiega cosa non va (vedi «Se qualcosa
non va»).

## 6. Aggiornare il server

Quando esce una nuova versione, ripeti **lo stesso comando del punto 4.1**. Il programma si accorge che il server è già
configurato: fa un **backup di sicurezza**, installa la nuova versione, la riavvia e controlla che risponda. Nessuna
domanda (nemmeno la password), dati e impostazioni restano.

## 7. Backup

- Ogni notte (alle 3:30, o appena il Jetson si riaccende se era spento) il server salva una copia nella cartella
  **thevault-backup** della tua Home. Le copie degli ultimi 30 giorni restano, quelle più vecchie vengono tolte.
- Sono dati **già cifrati**: anche se qualcuno li prendesse non potrebbe leggerli.
- **Una copia fuori dal Jetson**: ogni tanto, dal Mac, nel Terminale:

  ```
  rsync -a mario@jetson.local:thevault-backup/ ~/"The Vault Backup Jetson"/
  ```

- **Il paracadute più semplice**: ogni tanto, dall'app, **Impostazioni › Backup › Esporta…** e conserva il file (per
  esempio su iCloud Drive). Contiene tutte le voci e gli allegati, protetti da una password che scegli tu, e si può
  reimportare in qualsiasi momento.
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
| `thevault-server: command not found` | Apri una **nuova** sessione (quella vecchia non conosce ancora il comando), oppure scrivi `~/.thevault-server/bin/thevault-server status`. |
| «esegui il comando con il tuo utente, senza sudo» | Riscrivi il comando senza `sudo` davanti: il server gira con il tuo utente. |
| «non trovo i servizi del tuo utente» | Collegati direttamente con il tuo utente (`ssh mario@jetson.local`), non con `sudo` o `su`, e riprova. |
| Backup «non riuscito» in `status` | Esegui `thevault-server setup` e al passo 3 premi Invio per la cartella proposta. |

Il registro del server è in `~/.thevault-server/server.log` (per seguirlo dal vivo: `tail -f ~/.thevault-server/server.log`).

## Togliere il server

`thevault-server uninstall` toglie l'avvio automatico (i dati restano nella cartella `~/.thevault-server`). Per
spegnere anche l'accesso da fuori casa:

```
sudo tailscale funnel reset
```
