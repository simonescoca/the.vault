# The Vault

Gestore di password personale, minimal e intuitivo, sincronizzato in tempo reale tra i tuoi dispositivi
tramite un server tuo (un Mac mini sempre acceso). Cifratura end-to-end: il server conserva solo dati illeggibili.

## Installazione

1. **Server sul Mac mini**: [guida passo passo](docs/guida-server.md).
2. **App su Mac e Windows**: [guida passo passo](docs/guida-app.md) — download nella pagina
   [Releases](https://github.com/simonescoca/the.vault/releases/latest).

## Struttura

- **App desktop**: macOS e Windows (Flutter) — cartella [`app/`](app/)
- **Server**: per il Mac mini (Go) — cartella [`server/`](server/)
- **Documentazione**: cartella [`docs/`](docs/)
- **Piano di lavoro e diario di sviluppo**: [`todo.md`](todo.md)

## Sviluppo

```bash
./scripts/test-all.sh    # tutti i test: server + app
./scripts/make-icons.sh  # rigenera le icone dell'app
```

Una nuova versione si pubblica creando il tag `vX.Y.Z` (vedi [`.github/workflows/release.yml`](.github/workflows/release.yml)).
