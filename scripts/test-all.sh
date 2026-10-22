#!/usr/bin/env bash
# Runs the whole test suite (server + app). Used after every task.
# --server-only skips the app (for a computer without Flutter, such as the server itself).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Go and Flutter from the PATH, or from where this project's guides install them.
export PATH="$PATH:$HOME/.local/go/bin:$HOME/.local/flutter/bin:/opt/sdk/flutter/bin"

# With little memory (e.g. an 8 GB NVIDIA Jetson without swap) compile fewer packages at once: the race
# detector and the SQLite driver need a lot of it.
gotest=(go test -race -count=1)
if [ "$(awk '/^MemTotal:/ { print int($2 / 1048576) }' /proc/meminfo 2>/dev/null || echo 64)" -lt 12 ]; then
  gotest+=(-p=2)
fi

echo "== Server: gofmt + go vet + go test =="
(cd "$ROOT/server" && unformatted="$(gofmt -l .)" && { [ -z "$unformatted" ] || { echo "Not gofmt-formatted: $unformatted"; exit 1; }; } \
  && go vet ./... && "${gotest[@]}" ./...)

if [ "${1:-}" = "--server-only" ]; then
  echo "== SERVER TESTS PASSED (app skipped) =="
  exit 0
fi

echo "== App: flutter analyze + flutter test =="
(cd "$ROOT/app" && flutter pub get >/dev/null && flutter analyze --no-pub && flutter test --no-pub)

echo "== ALL TESTS PASSED =="
