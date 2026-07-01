#!/bin/bash
#
# notarize.sh — builds, signs, and notarizes INDDConverter for distribution outside the App Store.
#
# One-time setup (see README section "Notarized release"):
#   1) "Developer ID Application" certificate in Keychain
#      (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application)
#   2) Notary profile in Keychain under the name from $NOTARY_PROFILE:
#      xcrun notarytool store-credentials INDD-Notary \
#        --apple-id YOUR@APPLE-ID --team-id YOURTEAMID
#      (prompts for an app-specific password from appleid.apple.com)
#
# Then simply run:  ./notarize.sh
# Output:          dist/INDDConverter.dmg  (ready for GitHub release)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCHEME="INDDConverter"
WORKSPACE="INDDConverter.xcworkspace"
CONFIG="Release"
TEAM_ID="7A5RH5V7ZB"                 # Apple Team ID (from your account)
SIGN_IDENTITY="Developer ID Application"   # Prefix is enough; xcodebuild finds the matching certificate
NOTARY_PROFILE="INDD-Notary"         # Name of the Keychain profile (see store-credentials above)

BUILD_DIR="$(pwd)/.notarize-build"
DIST_DIR="$(pwd)/dist"
APP_NAME="INDDConverter.app"

# ---------------------------------------------------------------------------
# Pre-flight checks — clear error messages instead of cryptic failures
# ---------------------------------------------------------------------------
echo "▸ Checking prerequisites …"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "✗ No 'Developer ID Application' certificate found in Keychain."
  echo "  → Xcode → Settings → Accounts → Manage Certificates → '+' → 'Developer ID Application'"
  echo "    (requires a paid Apple Developer membership)"
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "✗ No notary profile '$NOTARY_PROFILE' found in Keychain."
  echo "  → xcrun notarytool store-credentials $NOTARY_PROFILE \\"
  echo "       --apple-id YOUR@APPLE-ID --team-id $TEAM_ID"
  exit 1
fi

echo "✓ Certificate and notary profile found."

# ---------------------------------------------------------------------------
# 1) Clean build (no signing yet — sign after stripping xattrs)
# ---------------------------------------------------------------------------
echo "▸ Building ($CONFIG) …"
rm -rf "$BUILD_DIR"
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  build

APP_PATH="$(find "$BUILD_DIR/Build/Products/$CONFIG" -name "$APP_NAME" -type d | head -1)"
if [ -z "$APP_PATH" ]; then echo "✗ Built app not found"; exit 1; fi
echo "✓ Built: $APP_PATH"

# Copy without extended attributes — RegisterWithLaunchServices (part of the build)
# adds com.apple.FinderInfo to the .app dir, which codesign rejects.
# ditto --noextattr gives us a pristine copy.
echo "▸ Creating clean copy (stripping xattrs) …"
CLEAN_DIR="$(mktemp -d)"
CLEAN_APP="$CLEAN_DIR/$APP_NAME"
ditto --noextattr --norsrc "$APP_PATH" "$CLEAN_APP"
APP_PATH="$CLEAN_APP"

# Sign with Developer ID + Hardened Runtime
echo "▸ Signing with Developer ID (Hardened Runtime) …"
ENTITLEMENTS="$(pwd)/Config/INDDConverter.entitlements"
codesign \
  --force --deep \
  --sign "$SIGN_IDENTITY" \
  --timestamp \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  "$APP_PATH"

# Verify signature
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "✓ Signature valid (Hardened Runtime)."

# ---------------------------------------------------------------------------
# 2) Create ZIP for notarization submission
# ---------------------------------------------------------------------------
mkdir -p "$DIST_DIR"
SUBMIT_ZIP="$DIST_DIR/INDDConverter-submit.zip"
rm -f "$SUBMIT_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$SUBMIT_ZIP"

# ---------------------------------------------------------------------------
# 3) Submit to Apple's notary service and wait
# ---------------------------------------------------------------------------
echo "▸ Submitting to Apple (usually takes 1–5 min.) …"
xcrun notarytool submit "$SUBMIT_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

# ---------------------------------------------------------------------------
# 4) Staple the notarization ticket to the app
# ---------------------------------------------------------------------------
echo "▸ Stapling notarization ticket …"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# Gatekeeper check (as a user's Mac would see it)
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
