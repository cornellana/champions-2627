#!/usr/bin/env bash
#
# subir_testflight.sh — compila, firma y sube la app a TestFlight.
#
# Usa la clave de API de App Store Connect que ya está en el Mac
# (~/.appstoreconnect/), así que no pide contraseñas ni códigos de verificación.
#
#   ./scripts/subir_testflight.sh            sube con el número de build siguiente
#   ./scripts/subir_testflight.sh --solo-archivar   compila y firma, sin subir
#
# Requisito previo: la ficha de la app tiene que existir en App Store Connect.
# Apple no deja crearla por API — ver `scripts/asc.py crear`.

set -euo pipefail

cd "$(dirname "$0")/.."

ESQUEMA="Champions"
PROYECTO="Champions.xcodeproj"
ARCHIVO="build/Champions.xcarchive"
EXPORTACION="build/export"
CONFIG_ASC="$HOME/.appstoreconnect/config.json"
CLAVES_ASC="$HOME/.appstoreconnect/private_keys"

SOLO_ARCHIVAR=false
[[ "${1:-}" == "--solo-archivar" ]] && SOLO_ARCHIVAR=true

# -- Número de build ---------------------------------------------------------
#
# Apple rechaza una build cuyo número ya se haya subido, aunque sea idéntica.
# Se toma el que hay en project.yml y se sube uno; así nunca hay colisión y
# queda registrado en el repositorio qué build es cuál.

BUILD_ACTUAL=$(grep -E "^\s+CURRENT_PROJECT_VERSION:" project.yml | grep -oE "[0-9]+")
BUILD_NUEVA=$((BUILD_ACTUAL + 1))
echo "▸ Build $BUILD_ACTUAL → $BUILD_NUEVA"
sed -i '' "s/CURRENT_PROJECT_VERSION: $BUILD_ACTUAL/CURRENT_PROJECT_VERSION: $BUILD_NUEVA/" project.yml
xcodegen generate >/dev/null

# -- Icono y datos frescos ---------------------------------------------------

echo "▸ Regenerando el icono"
swift scripts/render_icon.swift >/dev/null

echo "▸ Refrescando el calendario que viaja dentro de la app"
python3 scripts/fetch_season.py >/dev/null
cp data/champions2627.json Champions/champions2627-seed.json

# -- Archivar ----------------------------------------------------------------

echo "▸ Archivando (esto tarda un par de minutos)"
rm -rf "$ARCHIVO" "$EXPORTACION"
xcodebuild archive \
  -project "$PROYECTO" \
  -scheme "$ESQUEMA" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVO" \
  -allowProvisioningUpdates \
  -quiet

echo "▸ Exportando el .ipa"
cat > build/ExportOptions.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>            <string>app-store-connect</string>
    <key>teamID</key>            <string>TJ6V4QM3GB</string>
    <key>uploadSymbols</key>     <true/>
    <key>signingStyle</key>      <string>automatic</string>
    <key>destination</key>       <string>export</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVO" \
  -exportPath "$EXPORTACION" \
  -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates \
  -quiet

IPA=$(find "$EXPORTACION" -name "*.ipa" | head -1)
echo "▸ Listo: $IPA"

if $SOLO_ARCHIVAR; then
  echo "  (--solo-archivar: no se sube)"
  exit 0
fi

# -- Subir -------------------------------------------------------------------

KEY_ID=$(python3 -c "import json;print(json.load(open('$CONFIG_ASC'))['key_id'])")
ISSUER=$(python3 -c "import json;print(json.load(open('$CONFIG_ASC'))['issuer_id'])")

echo "▸ Validando contra App Store Connect"
# `altool` busca la clave en ~/.appstoreconnect/private_keys por convención,
# así que basta con el identificador: la clave privada nunca pasa por la línea
# de órdenes ni queda en el historial del intérprete.
xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER"

echo "▸ Subiendo"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER"

echo
echo "✅ Subida. Apple tarda de 5 a 15 minutos en procesarla."
echo "   Seguimiento:  python3 scripts/asc.py testflight"
