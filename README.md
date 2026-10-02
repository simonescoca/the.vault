# The Vault

Gestore di password personale, minimal e intuitivo, sincronizzato in tempo reale tra i tuoi dispositivi
tramite un server tuo (un Mac mini sempre acceso). Cifratura end-to-end: il server conserva solo dati illeggibili.

- **App desktop**: macOS e Windows (Flutter) — cartella [`app/`](app/)
- **Server**: per il Mac mini (Go) — cartella [`server/`](server/)
- **Documentazione**: cartella [`docs/`](docs/)
- **Piano di lavoro e diario di sviluppo**: [`todo.md`](todo.md)

## Sviluppo

```bash
./scripts/test-all.sh   # tutti i test: server + app
```
