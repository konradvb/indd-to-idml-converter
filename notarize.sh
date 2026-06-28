#!/bin/bash
#
# notarize.sh — baut, signiert und notarisiert INDDConverter für die Verteilung außerhalb des App Store.
#
# Voraussetzungen (einmalig einzurichten, siehe README-Abschnitt "Notarisierung"):
#   1) "Developer ID Application"-Zertifikat in der Keychain
#      (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application)
#   2) Notar-Profil in der Keychain unter dem Namen aus $NOTARY_PROFILE:
#      xcrun notarytool store-credentials INDD-Notary \
#        --apple-id DEINE@APPLE-ID --team-id YPTLHJD4XZ
#      (fragt nach dem App-spezifischen Passwort von appleid.apple.com)
#
# Danach einfach:  ./notarize.sh
# Ergebnis:        dist/INDDConverter-notarized.zip  (fertig für GitHub-Release)

set -euo pipefail

# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------
SCHEME="INDDConverter"
WORKSPACE="INDDConverter.xcworkspace"
CONFIG="Release"
TEAM_ID="YPTLHJD4XZ"                 # Apple-Team-ID (aus deinem Account)
SIGN_IDENTITY="Developer ID Application"   # Prefix reicht; xcodebuild findet das passende Zertifikat
NOTARY_PROFILE="INDD-Notary"         # Name des Keychain-Profils (siehe store-credentials oben)

BUILD_DIR="$(pwd)/.notarize-build"
DIST_DIR="$(pwd)/dist"
APP_NAME="INDDConverter.app"

# ---------------------------------------------------------------------------
# Vorab-Checks — klare Fehlermeldung statt kryptischem Abbruch
# ---------------------------------------------------------------------------
echo "▸ Prüfe Voraussetzungen …"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "✗ Kein 'Developer ID Application'-Zertifikat in der Keychain gefunden."
  echo "  → Xcode → Settings → Accounts → Manage Certificates → '+' → 'Developer ID Application'"
  echo "    (braucht die bezahlte Apple-Developer-Mitgliedschaft)"
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "✗ Kein Notar-Profil '$NOTARY_PROFILE' in der Keychain."
  echo "  → xcrun notarytool store-credentials $NOTARY_PROFILE \\"
  echo "       --apple-id DEINE@APPLE-ID --team-id $TEAM_ID"
  exit 1
fi

echo "✓ Zertifikat und Notar-Profil vorhanden."

# ---------------------------------------------------------------------------
# 1) Sauber bauen + mit Developer ID signieren (Hardened Runtime an)
# ---------------------------------------------------------------------------
echo "▸ Baue & signiere ($CONFIG, Hardened Runtime) …"
rm -rf "$BUILD_DIR"
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build

APP_PATH="$(find "$BUILD_DIR/Build/Products/$CONFIG" -name "$APP_NAME" -type d | head -1)"
if [ -z "$APP_PATH" ]; then echo "✗ Gebaute App nicht gefunden"; exit 1; fi
echo "✓ Gebaut: $APP_PATH"

# Signatur prüfen
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "✓ Signatur gültig (Hardened Runtime)."

# ---------------------------------------------------------------------------
# 2) ZIP für die Notarisierung erzeugen
# ---------------------------------------------------------------------------
mkdir -p "$DIST_DIR"
SUBMIT_ZIP="$DIST_DIR/INDDConverter-submit.zip"
rm -f "$SUBMIT_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$SUBMIT_ZIP"

# ---------------------------------------------------------------------------
# 3) An Apples Notar-Dienst schicken und warten
# ---------------------------------------------------------------------------
echo "▸ Reiche bei Apple ein (das dauert meist 1–5 Min.) …"
xcrun notarytool submit "$SUBMIT_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

# ---------------------------------------------------------------------------
# 4) Notar-Ticket an die App anheften ("stapeln")
# ---------------------------------------------------------------------------
echo "▸ Hefte Notar-Ticket an …"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# Gatekeeper-Check (so wie der Mac eines fremden Nutzers es sieht)
spctl -a -vvv -t install "$APP_PATH" || true

# ---------------------------------------------------------------------------
# 5) Finished, notarized DMG for distribution
# ---------------------------------------------------------------------------
rm -f "$SUBMIT_ZIP"
FINAL_DMG="$DIST_DIR/INDDConverter.dmg"
./make-dmg.sh "$APP_PATH" "$FINAL_DMG"

# The app inside is already stapled; staple the DMG too so it verifies offline.
xcrun stapler staple "$FINAL_DMG" || true

echo ""
echo "✅ Done. Notarized disk image: $FINAL_DMG"
echo "   Upload this as a GitHub release asset — it opens on any Mac with a"
echo "   double-click, no right-click workaround needed."
