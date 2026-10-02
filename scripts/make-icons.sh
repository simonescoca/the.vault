#!/usr/bin/env bash
# Regenerates the app icons (macOS icon set, Windows .ico, in-app PNG) from the drawing in
# app/test/tools/render_icons_test.dart. Needs Flutter and ImageMagick.
set -euo pipefail
cd "$(dirname "$0")/../app"
THEVAULT_RENDER_ICONS=1 flutter test --no-pub test/tools/render_icons_test.dart
convert build/icons/windows/{16,20,24,32,40,48,64,256}.png windows/runner/resources/app_icon.ico
echo "Icons updated."
