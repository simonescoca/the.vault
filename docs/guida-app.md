# Guida: l'app The Vault su Mac e Windows

Prima di iniziare serve il **server** sul Mac mini (vedi la [guida del server](guida-server.md)) e il suo
**indirizzo**, quello mostrato alla fine della configurazione (per esempio `mac-mini.tail1234.ts.net`).

---

## 1. Scarica e installa

Le ultime versioni sono sempre qui: **[github.com/simonescoca/the.vault/releases/latest](https://github.com/simonescoca/the.vault/releases/latest)**

### Mac
1. Scarica **TheVault-macOS.dmg** e aprilo.
2. Trascina **The Vault** nella cartella **Applicazioni**.
3. Apri The Vault da Applicazioni. La prima volta macOS dice che **non può verificare l'app**: è normale, perché l'app
   non è distribuita tramite l'App Store. Fai così, una volta sola:
   1. premi **Fine**;
   2. apri **Impostazioni di Sistema › Privacy e sicurezza** e scorri in basso fino a «The Vault è stata bloccata…»;
   3. premi **Apri comunque**, conferma con la password del Mac (o Touch ID) e poi ancora **Apri comunque**.

### Windows
1. Scarica **TheVault-Windows-Setup.exe** e aprilo.
2. Se compare «**Windows ha protetto il PC**»: premi **Ulteriori informazioni** e poi **Esegui comunque** (succede perché
   l'app non ha una firma a pagamento di Microsoft).
3. Segui l'installazione: non serve la password di amministratore. Alla fine The Vault si apre da solo; lo trovi poi nel
   menu Start.

## 2. Il primo computer

1. **Inizia**.
2. **Il tuo server**: scrivi l'indirizzo del Mac mini (es. `mac-mini.tail1234.ts.net`).
3. **La tua email** › **Invia codice**.
4. **Controlla la posta**: scrivi il codice di 6 cifre arrivato via email (puoi anche incollarlo).
5. **Il tuo codice di emergenza** — il passo più importante:
   - premi **Salva PDF** e conserva il file in un posto sicuro (meglio ancora: stampalo e tienilo con i documenti);
   - serve se un giorno avrai un computer nuovo e **nessun altro dispositivo** per approvarlo;
   - spunta **Ho conservato il codice in un posto sicuro** e continua.
6. **Scegli un PIN di 6 cifre** e ripetilo. Ti servirà quando impronta o volto non sono disponibili.
7. Se il computer ha **Touch ID** o **Windows Hello**, l'app ti chiede se vuoi usarlo per sbloccare. Consigliato.

Fatto: la tua cassaforte è pronta.

## 3. Un altro computer (es. il PC Windows)

1. Installa l'app e ripeti i passi 2.1 – 2.4 (stesso server, stessa email).
2. Compare **Conferma questo dispositivo** con un **codice di verifica**.
3. Sul computer che usi già, The Vault mostra **Nuovo accesso**: «PC di casa» vuole accedere.
4. **Controlla che il codice sia lo stesso sui due schermi**, poi premi **Approva**.
   Se i codici sono diversi premi **Rifiuta**: qualcuno potrebbe tentare di intromettersi.
5. Scegli il PIN del nuovo computer. Le password compaiono subito, e da qui in poi ogni modifica arriva in tempo reale.

> **Non hai un altro dispositivo a portata di mano?** Nella schermata di conferma scegli **Non ho altri dispositivi** e
> scrivi il codice di emergenza del PDF (24 caratteri, in gruppi di quattro).

## 4. Uso di tutti i giorni

**La finestra**: a sinistra *Tutte*, *Preferiti* e *Cestino*; al centro l'elenco con la ricerca; a destra la voce scelta.

**Leggere una voce**
- **Clic su un valore = copiato.** Si svuota dagli appunti dopo 1 minuto (modificabile).
- Gli **indirizzi web** e i **testi con link** si aprono nel browser; le **email** si copiano soltanto.
- L'**occhio** nasconde o mostra un valore con i pallini; la scelta resta salvata. Un valore nascosto si copia comunque
  con un clic.
- La **stella** aggiunge ai Preferiti.

**Creare o modificare**
- **+** (o ⌘N) crea una voce con tre righe già pronte: *sito web*, *email*, *password*.
- Le chiavi sono libere: scrivi quello che vuoi (es. «PIN», «codice cliente»). **Aggiungi riga** per averne altre.
- Accanto a ogni valore: 👁 occhio, 🔗 **link** (per trasformare un testo in un link), ✨ **generatore di password**,
  — togli la riga. Trascina la maniglia ⠿ a sinistra per riordinare le righe.
- **Descrizione** e **Allegati** sono in fondo: trascina i file nella zona tratteggiata o premi «scegli…».
- **Salva** (⌘S). Le righe vuote spariscono da sole; se scrivi solo il sito, il titolo viene dal nome del sito.

**Cestino**: «Sposta nel cestino» (dal menu ⋯) si può annullare subito con **Annulla**. Dal Cestino puoi **ripristinare**
o **eliminare definitivamente** (con conferma).

**Scorciatoie** (su Windows usa Ctrl al posto di ⌘)

| | |
|---|---|
| ⌘N | nuova voce |
| ⌘F | cerca |
| ⌘E | modifica |
| ⌘S | salva |
| Esc | annulla la modifica / svuota la ricerca |
| ↑ ↓ | voce precedente / successiva |
| ⌘⌫ (Windows: Canc) | sposta nel cestino |
| ⌘, | impostazioni |
| ⌘L | blocca subito |

## 5. Impostazioni

- **Generale**: aspetto (Sistema / Chiaro / Scuro) e lingua (Sistema / Italiano / English).
- **Sicurezza**: sblocco con Touch ID / Windows Hello, **Cambia PIN**, **Blocca dopo** (5 minuti di inattività,
  modificabile), **Svuota appunti dopo**, **Kit di emergenza** (puoi generare un nuovo codice: il vecchio smette di
  funzionare).
- **Dispositivi**: tutti i computer collegati. Puoi **rinominarli** o **disconnetterne** uno (per esempio se lo perdi):
  perde subito l'accesso e cancella i suoi dati appena si ricollega a internet.
- **Backup**: **Esporta…** crea un file con tutte le voci e gli allegati, protetto da una password che scegli tu;
  **Importa…** lo ripristina. Fallo ogni tanto e conserva il file: è il paracadute più semplice.
- **Account**: email e server. **Esci da questo dispositivo** cancella tutto da questo computer (le password restano sul
  server e sugli altri dispositivi).

## 6. Aggiornare l'app

Scarica la nuova versione dalla pagina delle release e installala sopra la vecchia (Mac: trascinala di nuovo in
Applicazioni e scegli **Sostituisci**; Windows: apri il nuovo installer). Le password e le impostazioni restano.

> **Mac**: dopo un aggiornamento macOS chiede **una volta** la password del Mac perché The Vault possa leggere le sue
> chiavi nel Portachiavi. Scrivila e premi **Consenti sempre**.

## Se qualcosa non va

| Problema | Soluzione |
|---|---|
| «Server non raggiungibile» | Controlla l'indirizzo e che il Mac mini sia acceso (guida del server, «Se qualcosa non va»). |
| Il codice email non arriva | Guarda nello Spam; puoi chiedere **Invia un nuovo codice** dopo 30 secondi. |
| PIN dimenticato | Dopo 10 tentativi sbagliati il computer si scollega da solo per sicurezza (le password restano al sicuro): ricollegalo come al punto 3. |
| Sono offline | Puoi consultare e modificare tutto: le modifiche partono appena torna la connessione. In basso a sinistra vedi lo stato. |
| Ho modificato la stessa voce su due computer insieme | Non si perde nulla: se le modifiche sono diverse, una delle due diventa una copia con «(conflitto)» nel titolo. |
