#!/usr/bin/env bash
# Runs the whole test suite (server + app). Used after every task.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/sdk/flutter/bin:$PATH"

echo "== Server: go vet + go test =="
(cd "$ROOT/server" && go vet ./... && go test -race -count=1 ./...)

echo "== App: flutter analyze + flutter test =="
(cd "$ROOT/app" && flutter analyze --no-pub && flutter test --no-pub)

echo "== ALL TESTS PASSED =="
