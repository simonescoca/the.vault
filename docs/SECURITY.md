# The Vault — Progetto di sicurezza

## In breve (linguaggio semplice)

- **Le password si cifrano sul tuo dispositivo, prima di partire.** Il Mac mini riceve e conserva solo dati illeggibili.
  Anche chi rubasse il Mac mini o ci entrasse da internet non potrebbe leggere nulla.
- **La chiave della cassaforte** esiste solo sui tuoi dispositivi, custodita nel portachiavi del sistema
  (Portachiavi di macOS, protezione dati di Windows).
- **Un nuovo dispositivo** riceve la chiave **solo** se lo approvi da un dispositivo già collegato, dopo aver controllato
  che il **codice di verifica** di 6 cifre sia uguale sui due schermi, oppure con il tuo **codice di emergenza**.
  Il codice email da solo non basta: chi entrasse nella tua email non vedrebbe nulla.
- **Codice di emergenza**: è l'unico modo per recuperare i dati se perdi tutti i dispositivi. Non c'è una "porta di
  servizio": se perdi tutti i dispositivi **e** il codice di emergenza, i dati non sono recuperabili, nemmeno da me.
- **Sul computer** l'app si sblocca con Touch ID / Windows Hello o con il PIN, e si richiude da sola dopo qualche minuto.

### Da cosa ti protegge
- Furto del Mac mini, o qualcuno che lo controlla da remoto.
- Qualcuno che intercetta la connessione (oltre alla cifratura delle voci c'è HTTPS).
- Qualcuno che entra nella tua email.
- Furto di un computer spento o bloccato (con FileVault / BitLocker attivi, come consigliato).
- Sguardi indiscreti: l'app si blocca da sola e i valori si possono nascondere.

### Da cosa non può proteggerti
- Un virus o programma spia sul tuo computer mentre The Vault è sbloccato.
- Qualcuno che conosce il tuo PIN e usa il tuo computer sbloccato.
- La perdita di tutti i dispositivi **e** del codice di emergenza.

---

## 1. Primitive crittografiche

Tutte da **libsodium** (1.0.22), libreria standard e verificata da audit.

| Uso | Primitiva |
|---|---|
| Cifratura voci, avvolgimento chiavi | `crypto_aead_xchacha20poly1305_ietf` (nonce casuale di 24 byte, tag 16 byte) |
| Cifratura allegati (a flusso) | `crypto_secretstream_xchacha20poly1305`, blocchi di 64 KiB |
| Consegna della chiave al nuovo dispositivo | `crypto_box_easy` (X25519 + XSalsa20-Poly1305) |
| Impegni (commitment), codice di verifica | `crypto_generichash` (BLAKE2b-256) |
| Sottochiavi | `crypto_kdf_derive_from_key` (BLAKE2b) |
| Password del backup, PIN, codice di emergenza | `crypto_pwhash` Argon2id13 |
| Casualità | `randombytes_buf` |

Lato server (Go, standard library): `crypto/rand`, SHA-256, HMAC-SHA256, confronti a tempo costante.

## 2. Chiavi

| Chiave | Dove nasce | Dove vive | Note |
|---|---|---|---|
| **VK** — chiave della cassaforte (32 byte) | primo dispositivo | portachiavi di ogni dispositivo collegato | mai in chiaro sul server |
| `K_items` = KDF(VK, 1, `tv_items`) | derivata | memoria, solo da sbloccato | cifra le voci |
| `K_check` = KDF(VK, 2, `tv_check`) | derivata | memoria | per il controllo chiave |
| **FK** — chiave di un allegato (32 byte) | dispositivo che allega | dentro la voce cifrata | una per file |
| Coppia X25519 del dispositivo | ogni dispositivo | portachiavi del dispositivo | la parte pubblica va al server |
| Codice di emergenza (120 bit) | primo dispositivo | **solo su carta/PDF** | mai salvato dall'app |
| Token del dispositivo (256 bit) | server | portachiavi del dispositivo | il server conserva solo lo SHA-256 |

**Controllo chiave** (`keyCheck`): `BLAKE2b-128(key=K_check, "thevault/key-check/v1")`, salvato sul server alla creazione
della cassaforte. Un nuovo dispositivo lo usa per verificare di aver ricevuto la chiave giusta (rileva errori; la sicurezza
vera la danno l'autenticazione della consegna e l'AEAD).

## 3. Formato delle voci

- Contenuto in chiaro: JSON (vedi `PROTOCOL.md` §6), con riempimento ISO/IEC 7816-4 a multipli di 256 byte
  (`sodium_pad`), per non rivelare la lunghezza esatta.
- Cifrato: `0x01 ‖ nonce(24) ‖ XChaCha20-Poly1305(K_items, nonce, pad(json), AAD)` con
  `AAD = "thevault/item/v1/" ‖ recordId`. L'AAD lega il contenuto al suo identificativo: il server non può scambiare
  il contenuto di due voci senza che la decifratura fallisca.
- Il server conosce solo: identificativo casuale della voce, revisione, dimensione (arrotondata), data di modifica,
  elenco degli identificativi degli allegati (per poterli cancellare quando non servono più).

## 4. Allegati

- Ogni file ha una chiave FK casuale. Cifratura a flusso: `header(24) ‖ blocco₁ ‖ … ‖ blocco_n`, blocchi da 64 KiB di
  contenuto (+17 byte), l'ultimo con il tag `FINAL` (un file troncato viene rifiutato).
- Il blob cifrato ha un identificativo casuale (UUID v4) generato dal dispositivo; nome, tipo, dimensione e FK stanno
  **dentro la voce cifrata**.
- Per aprire un allegato, il dispositivo lo decifra in una cartella temporanea dell'app e lo passa all'app predefinita
  del sistema. La cartella viene svuotata quando l'app si blocca, si chiude o riparte (limite noto: mentre un file è aperto
  in un'altra app, una copia in chiaro esiste sul disco).

## 5. Accesso con codice email (OTP)

- Codice di 6 cifre casuale uniforme, valido **10 minuti**, al massimo **5 tentativi**; il server ne conserva solo
  `HMAC-SHA256(chiave_server, email ‖ codice)`.
- Limiti: 5 richieste di codice all'ora per email, 30 all'ora per indirizzo IP. Risposte identiche per email ammesse
  e non ammesse (non si scopre quali email esistono).
- Sono ammesse solo le email configurate sul server (`allowed_emails`).
- Il codice email dà al dispositivo un **token** con permessi minimi: può solo chiedere l'approvazione o usare il
  codice di emergenza. Nessun accesso ai dati finché non è approvato.

## 6. Primo dispositivo (creazione della cassaforte)

1. OTP verificato, account senza cassaforte → stato `setup`.
2. Il dispositivo genera VK e il codice di emergenza RC (15 byte casuali → 24 caratteri Crockford Base32,
   `XXXX-XXXX-XXXX-XXXX-XXXX-XXXX`).
3. `RK = Argon2id(RC, salt_r, ops=INTERACTIVE, mem=INTERACTIVE)`; `RK_wrap = KDF(RK, 1, "tv_rcvry")`;
   `RK_auth = KDF(RK, 2, "tv_rauth")`.
4. Invia al server: `recovery = {salt_r, ops, mem, wrap = nonce ‖ AEAD(RK_wrap, nonce, VK, "thevault/recovery/v1/" ‖ userId)}`,
   `recoveryAuth = RK_auth` (il server ne salva solo lo SHA-256), `keyCheck`.
5. Il server crea la cassaforte (operazione atomica: una sola volta) e attiva il dispositivo.

## 7. Nuovo dispositivo: approvazione con codice di verifica

Protocollo di **confronto numerico con impegno** (*commitment*), come nel Bluetooth "Numeric Comparison": un server
malintenzionato che si mette in mezzo ha **1 possibilità su un milione** per tentativo, e ogni tentativo fallito è visibile
(codici diversi → l'utente rifiuta).

Notazione: `H = BLAKE2b-256`, `D2` = nuovo dispositivo, `D1` = dispositivo già collegato, `S` = server (solo inoltro).

1. **D2 → S**: `pk2` (chiave pubblica del dispositivo, già registrata con l'OTP) e `c2 = H("thevault/approval/commit/v1" ‖ pk2 ‖ n2)`
   con `n2` 32 byte casuali **tenuti segreti**. S crea la richiesta `approvalId` e la segnala ai dispositivi attivi.
2. **D1** (l'utente ha aperto la richiesta) genera una coppia **effimera** `(pk1, sk1)` e `n1` casuale. **D1 → S → D2**: `pk1, n1`.
3. **D2 → S → D1**: `n2` (solo ora rivelato).
4. **D1** verifica `c2 == H(... ‖ pk2 ‖ n2)`; se no, la richiesta è rifiutata.
5. Entrambi calcolano `sas = H("thevault/approval/sas/v1" ‖ approvalId ‖ pk2 ‖ pk1 ‖ n1 ‖ n2)` e mostrano
   `codice = uint32_be(sas[0..4]) mod 1 000 000` (6 cifre).
6. L'utente confronta i codici e preme **Approva** su D1.
7. **D1 → S → D2**: `box = crypto_box_easy({"vk", "userId", "approvalId"}, nonce, pk2, sk1)`. D1 cancella `sk1`.
8. **D2** apre `box` con `(pk1, sk2)`, controlla `userId`, `approvalId` e `keyCheck`, salva VK. S attiva D2 **solo** se
   l'approvazione arriva da un dispositivo attivo dello stesso utente.

Perché funziona: S deve "impegnarsi" verso D1 su una chiave falsa prima di conoscere `n1`, e scegliere cosa mandare a D2
prima di conoscere `n2`; quindi non può far coincidere i due codici se non per caso. `pk1` è coperta dal codice, quindi D2
sa che la chiave arriva davvero da D1 e non da un impostore.

Limiti: una richiesta aperta per dispositivo, scadenza 10 minuti; dopo 3 rifiuti in un'ora le richieste per
quell'account si sospendono per un'ora. Ogni nuovo collegamento genera un'email di avviso.

## 8. Nuovo dispositivo: codice di emergenza

1. D2 (token `pending`) chiede a S il pacchetto di recupero `{salt_r, ops, mem, wrap}`.
2. D2 ricava `RK` dal codice inserito, decifra `wrap` → VK (se il codice è sbagliato la decifratura fallisce, in locale).
3. D2 invia `RK_auth`; S confronta `SHA-256(RK_auth)` a tempo costante e attiva il dispositivo.
   Massimo 5 tentativi all'ora per account.
4. Con "Genera un nuovo codice" (Impostazioni) un dispositivo attivo sostituisce il pacchetto: il vecchio codice
   smette di funzionare.

## 9. Sul dispositivo

- **Portachiavi**: VK, chiave privata del dispositivo, token, hash del PIN, contatore errori.
  - macOS: Portachiavi "classico" (l'app non ha una firma Apple Developer; con una firma ufficiale si potrà passare al
    portachiavi moderno). Limite noto: dopo un aggiornamento dell'app non firmata, macOS può chiedere una volta la
    password del Mac per consentire l'accesso al portachiavi ("Consenti sempre").
  - Windows: protezione dati di Windows (DPAPI) legata al tuo utente.
- **Database locale** (SQLite): contiene le voci **già cifrate** (lo stesso formato del server), le modifiche in attesa
  e le impostazioni non sensibili. Gli allegati scaricati restano cifrati.
- **Sblocco**:
  - Touch ID (macOS, solo biometria: niente ripiego sulla password del Mac) o Windows Hello (impronta/volto, oppure il
    PIN di Windows Hello se è l'unico metodo configurato); se non disponibile o annullato → **PIN dell'app**.
  - PIN: 6 cifre, salvato come `crypto_pwhash_str` (Argon2id). Dal 5° errore attese crescenti; al 10° il dispositivo si
    scollega e cancella i dati locali.
  - Il blocco è un "cancello" dell'app: la protezione dei dati a riposo è data dal portachiavi del sistema e dalla
    cifratura del disco (FileVault / BitLocker, da tenere attivi).
- **Memoria**: VK sta in memoria protetta di libsodium (`sodium_malloc`) e viene distrutta al blocco. I dati decifrati
  delle voci vengono rilasciati al blocco (Dart non permette di azzerarli in modo garantito: limite noto).
- **Appunti**: svuotati dopo il tempo impostato (default 1 minuto), solo se contengono ancora il valore copiato.

## 10. Server (Mac mini)

- Ascolta solo su `127.0.0.1`; è esposto su internet da **Tailscale Funnel**, che fornisce HTTPS con certificato valido.
- Token dei dispositivi salvati come SHA-256; confronti a tempo costante; limiti di velocità sugli endpoint di accesso;
  dimensioni massime delle richieste (JSON 1 MiB, blocchi di allegato 8 MiB, allegato intero 200 MiB + margine).
- I log non contengono codici, token o contenuti.
- Cartella dati con permessi `0700`. Backup giornalieri (già cifrati end-to-end) in una cartella a scelta.
- Un dispositivo disconnesso perde subito l'accesso: il suo token viene cancellato e, se è connesso, riceve l'ordine di
  cancellare i dati locali.

## 11. Backup su file (Esporta)

- `TheVault-Backup-AAAA-MM-GG.thevault`: intestazione in chiaro (`THEVAULT-BACKUP`, versione, parametri Argon2id, sale),
  poi tutto il contenuto cifrato a flusso con `KB = Argon2id(password, sale, ops=MODERATE, mem=MODERATE)`.
- Contenuto: manifest, voci in chiaro (JSON), allegati in chiaro; tutto dentro il flusso cifrato.
- La password del backup non viene salvata da nessuna parte.
