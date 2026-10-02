# Guida: il server di The Vault sul Mac mini

Il server è il "punto d'incontro" dei tuoi dispositivi: tiene la copia **cifrata** delle password e la passa in tempo
reale a tutti i computer collegati. Gira sul Mac mini sempre acceso. Non può leggere le tue password: conserva solo
dati illeggibili.

Tempo necessario: circa **20 minuti**, una volta sola.

**Cosa ti serve**
- il Mac mini, acceso e collegato a internet;
- la tua email (le istruzioni sono per **iCloud**; vanno bene anche Gmail o altri servizi);
- l'accesso al tuo account Apple (per creare una password per le app).

---

## 1. Prepara il Mac mini

### Che non vada mai in stop
Apri **Impostazioni di Sistema › Energia** e attiva:
- **Impedisci lo stop automatico quando lo schermo è spento**;
- **Riattiva per l'accesso alla rete**;
- **Avvia automaticamente dopo un'interruzione di corrente**.

### Dopo un riavvio
Il server parte quando sul Mac mini c'è un utente collegato. Dopo un riavvio (un aggiornamento di macOS o un'interruzione
di corrente) hai due possibilità:

| | Cosa fai | Pro | Contro |
|---|---|---|---|
| **A — consigliata** | Lasci **FileVault** attivo (Impostazioni › Privacy e sicurezza › FileVault). | Il disco del Mac mini è cifrato. | Dopo un riavvio devi fare l'accesso sul Mac mini una volta: poi riparte tutto da solo. |
| **B** | Disattivi FileVault e attivi **Impostazioni › Utenti e gruppi › Accedi automaticamente**. | Dopo un riavvio riparte tutto senza di te. | Chi rubasse il Mac mini potrebbe leggerne gli altri file. Le tue password restano comunque cifrate. |

## 2. Crea la password per le app (iCloud)

Il server invia i codici di accesso dalla tua casella email. Per farlo gli serve una **password specifica per le app**
(non la password del tuo account Apple, che non va mai data a nessun programma).

1. Vai su **[account.apple.com](https://account.apple.com)** e accedi.
2. **Accesso e sicurezza › Password specifiche per le app** › **+**.
3. Come nome scrivi `The Vault` e conferma.
4. Compare una password del tipo `abcd-efgh-ijkl-mnop`: **lasciala aperta**, ti servirà tra poco.

> Con Gmail: [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords) (serve la verifica in due
> passaggi attiva).

## 3. Installa Tailscale (per usare The Vault fuori casa)

Tailscale rende il Mac mini raggiungibile da internet **in modo sicuro**, con indirizzo e certificato HTTPS automatici,
senza toccare il router. Per uso personale è gratuito.

1. Scarica Tailscale da **[tailscale.com/download/mac](https://tailscale.com/download/mac)** e installalo.
2. Aprilo e accedi (va bene il tuo account Apple, Google o Microsoft).
3. Nel menu di Tailscale (l'icona in alto a destra) attiva **Launch at login** / **Avvia all'accesso**.

## 4. Installa il server

1. Apri il **Terminale** (premi ⌘ Spazio, scrivi `Terminale`, premi Invio).
2. Copia questa riga, incollala nel Terminale e premi **Invio**:

   ```
   curl -fsSL https://github.com/simonescoca/the.vault/releases/latest/download/install-server.sh | bash
   ```

3. Parte la **configurazione guidata** (5 passi). Per accettare la proposta tra `[parentesi quadre]` basta premere Invio.

   | Passo | Cosa fare |
   |---|---|
   | **1/5 La tua email** | Scrivi la tua email: sarà l'unica ammessa. |
   | **2/5 Invio delle email** | Premi Invio per **1) iCloud**, poi Invio per l'indirizzo proposto. Incolla la password per le app del punto 2 (**mentre la incolli non compare nulla: è normale**) e premi Invio. Ti arriva un'email di prova: controlla anche lo Spam. |
   | **3/5 Backup automatici** | Premi Invio: i backup vanno nella cartella **The Vault Backup** della tua Home. |
   | **4/5 Avvio automatico** | Non devi fare nulla. macOS può mostrare l'avviso «Elementi in background aggiunti»: è il server, va bene così. |
   | **5/5 Accesso da fuori casa** | Se compare un link, aprilo nel browser e conferma l'attivazione di **Funnel** su Tailscale (si fa una volta sola), poi torna al Terminale. |

4. Alla fine compare **Fatto! 🎉** con l'**indirizzo del server**, per esempio:

   ```
   mac-mini.tail1234.ts.net
   ```

   **Scrivilo**: lo inserirai nell'app (vedi la [guida dell'app](guida-app.md)).

> Se il certificato HTTPS non è ancora pronto, il passo 5 dice «non ancora raggiungibile»: è normale nei primi minuti.
> Controlla più tardi con il comando del punto 5.

## 5. Controllare che tutto funzioni

Apri una **nuova** finestra del Terminale e scrivi:

```
thevault-server status
```

Vedrai qualcosa come:

```
The Vault — stato del server
  Dati:             /Users/mario/Library/Application Support/TheVaultServer
  Email ammessa:    mario.rossi@icloud.com
  Invio email:      smtp.mail.me.com
  Server locale:    ✓ attivo su http://127.0.0.1:8743
  Fuori casa:       ✓ https://mac-mini.tail1234.ts.net
  Indirizzo per l'app: mac-mini.tail1234.ts.net
  Backup:           ✓ ultimo riuscito il 02/10/2026 03:30 in /Users/mario/The Vault Backup
```

Tutte le righe con **✓** vogliono dire che è tutto a posto. Una **✗** spiega cosa non va (vedi «Se qualcosa non va»).

## 6. Aggiornare il server

Quando esce una nuova versione, ripeti **lo stesso comando del punto 4.2**. Il programma si accorge che il server è già
configurato: fa un **backup di sicurezza**, installa la nuova versione, la riavvia e controlla che risponda. Nessuna
domanda, dati e impostazioni restano.

## 7. Backup

- Ogni notte (alle 3:30, o appena il Mac si riaccende se era spento) il server salva una copia nella cartella
  **The Vault Backup** della tua Home. Le copie degli ultimi 30 giorni restano, quelle più vecchie vengono tolte.
- Sono dati **già cifrati**: anche se qualcuno li prendesse non potrebbe leggerli.
- **Perché non su iCloud Drive?** macOS non permette ai programmi che lavorano in background di scrivere su iCloud Drive,
  Scrivania, Documenti, Download o dischi esterni (e non può nemmeno chiedere il permesso). Per questo la configurazione
  rifiuta quelle cartelle.
- **Una copia fuori dal Mac mini**: collega un disco esterno e attiva **Time Machine** (Impostazioni › Generali › Time
  Machine). Copierà anche la cartella dei backup e i dati del server.
- **Il paracadute più semplice**: ogni tanto, dall'app, **Impostazioni › Backup › Esporta…** e conserva il file (per
  esempio su iCloud Drive). Contiene tutte le voci e gli allegati, protetti da una password che scegli tu, e si può
  reimportare in qualsiasi momento.
- Backup immediato: `thevault-server backup`.

## 8. Modificare la configurazione

Per cambiare email, password per le app o cartella dei backup, nel Terminale:

```
thevault-server setup
```

Le risposte già date sono proposte tra parentesi: cambia solo quello che ti serve.

## Se qualcosa non va

| Problema | Soluzione |
|---|---|
| L'email con il codice non arriva | Guarda nello Spam. Poi ricontrolla la password per le app con `thevault-server setup` (passo 2). |
| L'app dice «Server non raggiungibile» | Il Mac mini è acceso e collegato? Tailscale è aperto e collegato? Controlla con `thevault-server status`. |
| Dopo un riavvio non funziona più | Fai l'accesso sul Mac mini (vedi 1. «Dopo un riavvio»). |
| `thevault-server: command not found` | Apri una **nuova** finestra del Terminale (quella vecchia non conosce ancora il comando). |
| Backup «non riuscito» in `status` | Esegui `thevault-server setup` e al passo 3 premi Invio per la cartella proposta. |

## Togliere il server

`thevault-server uninstall` toglie l'avvio automatico (i dati restano nella cartella
`~/Library/Application Support/TheVaultServer`). Per spegnere anche l'accesso da fuori casa:

```
/Applications/Tailscale.app/Contents/MacOS/Tailscale funnel reset
```
