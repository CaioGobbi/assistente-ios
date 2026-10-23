#!/usr/bin/env bash
# Compila o app sem assinatura e empacota em Assistente.ipa.
# O SideStore (ou AltStore) assina com a sua conta Apple na hora de instalar.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
mkdir -p build
LOG="build/xcodebuild.log"
if ! xcodebuild -project Assistente.xcodeproj -scheme Assistente -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build > "$LOG" 2>&1; then
  # No GitHub Actions, cada erro vira uma anotação visível no PR.
  grep -E ": error:" "$LOG" | sort -u | head -n 40 | sed 's/^/::error::/' || true
  tail -n 40 "$LOG"
  exit 1
fi

APP="build/Build/Products/Release-iphoneos/Assistente.app"
[ -d "$APP" ] || { echo "Build falhou: $APP não existe." >&2; exit 1; }

SAIDA="$PWD/Assistente.ipa"
TMP="$(mktemp -d)"
mkdir -p "$TMP/Payload"
cp -R "$APP" "$TMP/Payload/"
rm -f "$SAIDA"
(cd "$TMP" && zip -qry "$SAIDA" Payload)
rm -rf "$TMP"
echo "Pronto: $SAIDA"
