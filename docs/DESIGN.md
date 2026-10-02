# The Vault — Design visivo

Principi: **minimal, pulito, intuitivo**. Monocromatico: bianco, nero e grigi; il colore compare solo per gli avvisi
(rosso per le azioni irreversibili). Tanto spazio bianco, gerarchia data dalla tipografia e non da riquadri o colori.
Nessun elemento decorativo che non serva.

## 1. Font

Scelta fatta confrontando due coppie renderizzate con l'app (`docs/design/font-specimen.png`):

| Elemento | Font | Dimensione / interlinea | Peso | Colore |
|---|---|---|---|---|
| **Titolo** della voce | Geist | 28 / 34, spaziatura −0,5 | 600 | primario |
| **Chiave** | Geist | 13 / 20 | 400 | secondario |
| **Valore** | **Geist Mono** | 13 / 20 | 400 | primario |
| **Descrizione** | Geist | 14 / 22 | 400 | primario |
| Titolo nell'elenco | Geist | 13,5 / 18 | 500 | primario |
| Sottotitolo nell'elenco | Geist | 12 / 16 | 400 | secondario |
| Menu laterale | Geist | 13 / 18 | 500 | primario / secondario |
| Testo di interfaccia | Geist | 13 / 20 | 400 | primario |
| Titoli delle schermate di avvio | Geist | 24 / 30 | 600 | primario |

- **Geist / Geist Mono** (licenza SIL Open Font License 1.1) sono incluse nell'app: niente download, funzionano offline.
- Geist Mono ha lo **zero barrato** e distingue bene `1 l I |`: fondamentale per leggere le password
  (`docs/design/mono-ambiguous-chars.png`).
- Caratteri mancanti nei font (es. emoji, alfabeti non latini) usano il font di sistema.

## 2. Colori

| Token | Chiaro | Scuro | Uso |
|---|---|---|---|
| `bg` | `#FFFFFF` | `#0F0F10` | dettaglio, elenco |
| `sidebar` | `#F5F5F5` | `#161617` | menu laterale |
| `hover` | `#F2F2F2` | `#1A1A1C` | passaggio del mouse |
| `selected` | `#EBEBEB` | `#252527` | voce selezionata |
| `divider` | `#EBEBEB` | `#232325` | separatori |
| `inputBg` | `#FAFAFA` | `#151517` | campi in modifica |
| `inputBorder` | `#E3E3E3` | `#2C2C2E` | bordo dei campi |
| `text` | `#111111` | `#EDEDED` | testo primario |
| `text2` | `#707070` | `#9A9A9A` | chiavi, sottotitoli |
| `text3` | `#A8A8A8` | `#5E5E5E` | suggerimenti, icone tenui |
| `primary` | `#111111` | `#EDEDED` | pulsante principale, selezione, focus |
| `onPrimary` | `#FFFFFF` | `#111111` | testo sul pulsante principale |
| `danger` | `#D93025` | `#FF6B5E` | elimina definitivamente, errori |

- I **link** sono nel colore del testo, con sottolineatura sottile `text3`; più scura al passaggio del mouse.
- Il **focus** da tastiera è un anello di 2 px `primary` al 25%.
- Tema: segue il sistema; si può forzare da Impostazioni.

## 3. Spazi, forme, movimento

- Griglia di **4 px**. Margini del dettaglio: 40 px ai lati, 28 px in alto.
- Raggi: 6 px (campi, pulsanti piccoli), 8 px (voci dell'elenco, riquadri), 12 px (finestre, pannelli).
- Righe chiave/valore: 34 px di altezza minima; colonna delle chiavi larga quanto la chiave più lunga, tra 96 e 180 px.
- Elenco: righe da 52 px (titolo + sottotitolo), icona 28 px con raggio 7 px.
- Ombre solo per pannelli e finestre in primo piano (morbide e molto leggere); nel tema scuro, bordo sottile al posto
  dell'ombra.
- Animazioni brevi e discrete: 150 ms (passaggio del mouse, comparse), 220 ms (passaggio a modifica, pannelli),
  messaggi che salgono dal basso in 200 ms. Nessuna animazione "giocosa".

## 4. Icone

- Set **Lucide**: tratto sottile, 16 px nelle barre, 15 px dentro le righe, colore `text3` (`text` al passaggio del mouse).
- Occhio: `eye` / `eye-off`. Copia: `copy`. Link: `link`. Genera: `wand-sparkles`. Trascina: `grip-vertical`.
  Rimuovi riga: `minus`. Preferito: `star` (piena quando attivo). Allegato: icona del tipo di file.

## 5. Finestra

- Minimo 960 × 620, all'avvio 1180 × 760 (ricorda dimensione e posizione).
- **macOS**: barra del titolo nascosta, semafori dentro il menu laterale.
- **Windows**: barra del titolo di sistema, chiara o scura in base al tema.
- Colonne: menu 220 px · elenco 300 px · dettaglio il resto.

## 6. Componenti chiave

- **Riga in visualizzazione**: `chiave` (sinistra, `text2`) · `valore` (mono, `text`) · a destra, al passaggio del mouse,
  `occhio` e `copia` (o `apri` per i link). Il clic sul valore copia: un piccolo "Copiato" compare accanto per un attimo
  oltre al messaggio in basso.
- **Riga in modifica**: `⋮⋮` · campo chiave (aiuto grigio) · campo valore (mono) · `occhio` · `link` · `genera` · `−`.
  I campi hanno sfondo `inputBg` e bordo `inputBorder`; al focus bordo `primary`.
- **Pulsanti**: principale pieno `primary`; secondario trasparente con bordo; testuale; pericolo in `danger`.
- **Messaggi**: pillola scura (chiara nel tema scuro) in basso al centro.
- **Finestre di conferma**: piccole, centrate, titolo in Geist 600, pulsante distruttivo a destra in `danger`.
- **Iniziale**: quadratino 28 px, sfondo `selected`, lettera Geist 600 in `text2`.

## 7. Icona dell'app

Quadrato arrotondato nero (bianco nel tema scuro di Windows non serve: l'icona è unica) con un **disco da cassaforte**
minimale bianco: un cerchio sottile con una tacca. Disegnata in SVG e convertita in `.icns` (macOS) e `.ico` (Windows).
