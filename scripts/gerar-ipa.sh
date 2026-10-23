#!/usr/bin/env bash
# Compila o app sem assinatura e empacota em Assistente.ipa.
# O SideStore (ou AltStore) assina com a sua conta Apple na hora de instalar.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -project Assistente.xcodeproj -scheme Assistente -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build | tail -n 50

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
