#!/bin/bash
# The Vault — installs or updates the server on the computer that stays on: the Mac mini, or a Linux computer
# with systemd such as an NVIDIA Jetson.
#
# In the Terminal (on Linux: with your user, without sudo):
#   curl -fsSL https://github.com/simonescoca/the.vault/releases/latest/download/install-server.sh | bash
#
# First time: downloads the server and starts the guided setup (in Italian).
# Afterwards: the same command updates it, keeping data and settings (with a backup first).
# A specific version: THEVAULT_VERSION=v1.2.0 before "bash".
set -euo pipefail

# Everything is in a function called on the last line: if the download of this script stops halfway,
# bash runs nothing.
main() {
  REPO="simonescoca/the.vault"
  VERSION="${THEVAULT_VERSION:-latest}"
  case "$VERSION" in
    latest | v*) ;;
    *) VERSION="v$VERSION" ;;
  esac

  # The data folder is the default of the server (config.DefaultDataDir).
  case "$(uname -s)" in
    Darwin)
      OS=macos
      DATA="$HOME/Library/Application Support/TheVaultServer"
      ;;
    Linux)
      OS=linux
      DATA="$HOME/.thevault-server"
      [ "$(id -u)" -ne 0 ] || fail "Esegui il comando con il tuo utente, senza sudo: il server gira con il tuo account."
      [ -d /run/systemd/system ] || fail "Serve un sistema Linux con systemd (per esempio Ubuntu, come sul Jetson)."
      ;;
    *) fail "Questo programma di installazione è per macOS e Linux." ;;
  esac
  CONFIG="$DATA/config.json"
  case "$(uname -m)" in
    arm64 | aarch64) ARCH=arm64 ;;
    x86_64) ARCH=amd64 ;;
    *) fail "Processore non supportato: $(uname -m)" ;;
  esac
  # The first time the setup asks some questions: it needs a terminal to type in.
  if [ ! -f "$CONFIG" ] && ! { : </dev/tty; } 2>/dev/null; then
    fail "La configurazione fa alcune domande: apri il Terminale ed esegui lì questo comando."
  fi
  if [ "$VERSION" = latest ]; then
    BASE="https://github.com/$REPO/releases/latest/download"
  else
    BASE="https://github.com/$REPO/releases/download/$VERSION"
  fi

  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  FILE="thevault-server-$OS-$ARCH.tar.gz"

  say "The Vault — server"
  say "Scarico il programma…"
  download "$BASE/$FILE" "$TMP/$FILE"
  download "$BASE/SHA256SUMS.txt" "$TMP/SHA256SUMS.txt"

  # The file must be exactly the published one.
  expected="$(awk -v f="$FILE" '$2 == f || $2 == "*"f { print $1 }' "$TMP/SHA256SUMS.txt")"
  if [ "$OS" = macos ]; then
    actual="$(shasum -a 256 "$TMP/$FILE" | awk '{ print $1 }')"
  else
    actual="$(sha256sum "$TMP/$FILE" | awk '{ print $1 }')"
  fi
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    fail "Il file scaricato non corrisponde a quello pubblicato: riprova più tardi."
  fi

  tar -xzf "$TMP/$FILE" -C "$TMP"
  BIN="$TMP/thevault-server"
  chmod +x "$BIN"
  if [ "$OS" = macos ]; then
    xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true
  fi
  say "✓ Scaricata la versione $("$BIN" version | awk '{ print $2 }')"
  say ""

  # New Terminal windows will know the command "thevault-server" (status, backup, setup…). On Linux the
  # program does it itself when it installs the service (a link in ~/.local/bin).
  if [ "$OS" = macos ]; then
    PROFILE="$HOME/.zprofile"
    if ! grep -qs "TheVaultServer/bin" "$PROFILE"; then
      # shellcheck disable=SC2016 # $HOME and $PATH must expand when the profile runs, not now
      printf '\n# The Vault server\nexport PATH="$HOME/Library/Application Support/TheVaultServer/bin:$PATH"\n' >>"$PROFILE"
    fi
  fi

  if [ -f "$CONFIG" ]; then
    # Already set up: replace the program and restart the service (a backup is made first; if the new version
    # does not start, the program puts the previous one back).
    "$BIN" upgrade || fail "Aggiornamento non riuscito: vedi i messaggi qui sopra."
    say ""
    "$BIN" status || true
  else
    # First time: the guided setup asks its questions on the keyboard, not on this script.
    "$BIN" setup </dev/tty
  fi
}

say() { printf '%s\n' "$*"; }
fail() {
  printf '\n✗ %s\n' "$*" >&2
  exit 1
}

download() {
  local rc=0
  curl -fsSL --retry 3 "$1" -o "$2" || rc=$?
  case "$rc" in
    0) ;;
    22) fail "File non trovato: $1 (la versione ${VERSION} esiste e ha il server per questo computer?)" ;;
    *) fail "Download non riuscito: controlla la connessione e riprova." ;;
  esac
}

main "$@"
