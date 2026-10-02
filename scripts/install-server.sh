#!/bin/bash
# The Vault — installs or updates the server on the Mac that stays on (the Mac mini).
#
# In the Terminal:
#   curl -fsSL https://github.com/simonescoca/the.vault/releases/latest/download/install-server.sh | bash
#
# First time: downloads the server and starts the guided setup (in Italian).
# Afterwards: the same command updates it, keeping data and settings (with a backup first).
# A specific version: THEVAULT_VERSION=v1.0.0 before "bash".
set -euo pipefail

REPO="simonescoca/the.vault"
VERSION="${THEVAULT_VERSION:-latest}"
CONFIG="$HOME/Library/Application Support/TheVaultServer/config.json"

say() { printf '%s\n' "$*"; }
fail() {
  printf '\n✗ %s\n' "$*" >&2
  exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "Questo programma di installazione è per macOS."
case "$(uname -m)" in
  arm64) ARCH=arm64 ;;
  x86_64) ARCH=amd64 ;;
  *) fail "Processore non supportato: $(uname -m)" ;;
esac
if [ "$VERSION" = latest ]; then
  BASE="https://github.com/$REPO/releases/latest/download"
else
  BASE="https://github.com/$REPO/releases/download/$VERSION"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FILE="thevault-server-macos-$ARCH.tar.gz"

say "The Vault — server"
say "Scarico il programma…"
curl -fsSL --retry 3 "$BASE/$FILE" -o "$TMP/$FILE" || fail "Download non riuscito: controlla la connessione e riprova."
curl -fsSL --retry 3 "$BASE/SHA256SUMS.txt" -o "$TMP/SHA256SUMS.txt" || fail "Download non riuscito: controlla la connessione e riprova."

# The file must be exactly the published one.
expected="$(awk -v f="$FILE" '$2 == f || $2 == "*"f { print $1 }' "$TMP/SHA256SUMS.txt")"
actual="$(shasum -a 256 "$TMP/$FILE" | awk '{ print $1 }')"
if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
  fail "Il file scaricato non corrisponde a quello pubblicato: riprova più tardi."
fi

tar -xzf "$TMP/$FILE" -C "$TMP"
BIN="$TMP/thevault-server"
chmod +x "$BIN"
xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true
say "✓ Scaricata la versione $("$BIN" version | awk '{ print $2 }')"
say ""

# New Terminal windows will know the command "thevault-server" (status, backup, setup…).
PROFILE="$HOME/.zprofile"
if ! grep -qs "TheVaultServer/bin" "$PROFILE"; then
  # shellcheck disable=SC2016 # $HOME and $PATH must expand when the profile runs, not now
  printf '\n# The Vault server\nexport PATH="$HOME/Library/Application Support/TheVaultServer/bin:$PATH"\n' >>"$PROFILE"
fi

if [ -f "$CONFIG" ]; then
  # Already set up: replace the program and restart the service (a backup is made first).
  "$BIN" upgrade || fail "Aggiornamento non riuscito (vedi sopra). Il server di prima è ancora installato."
  say ""
  "$BIN" status || true
else
  # First time: the guided setup asks its questions on the keyboard, not on this script.
  "$BIN" setup </dev/tty
fi
