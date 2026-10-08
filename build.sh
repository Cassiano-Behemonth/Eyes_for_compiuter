#!/bin/bash
# Compila o Eye.app em ./build e instala em /Applications (NO_INSTALL=1 pula a instalação)
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Eye.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 \
  -target "$(uname -m)-apple-macos14.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Eye"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null

echo "OK: $APP"

[ "${NO_INSTALL:-}" = 1 ] && exit 0

# Instala por cima da versão anterior; se o Eye estava aberto, fecha e abre o novo.
DEST=/Applications/Eye.app
WAS_RUNNING=0
if pgrep -xq Eye; then
  WAS_RUNNING=1
  killall Eye
  while pgrep -xq Eye; do sleep 0.2; done
fi
rm -rf "$DEST"
ditto "$APP" "$DEST"
echo "Instalado: $DEST"
if [ "$WAS_RUNNING" = 1 ]; then
  # Logo depois de copiar, o LaunchServices às vezes ainda não registrou o app (erro -600).
  for _ in 1 2 3 4 5; do open "$DEST" 2>/dev/null && break; sleep 1; done
fi
exit 0
