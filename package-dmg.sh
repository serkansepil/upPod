#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="${UPPOD_APP:-UpPod.app}"
DMG="${UPPOD_DMG:-uppod.dmg}"
VOLNAME="${UPPOD_VOLNAME:-UpPod}"
SIGN_IDENTITY="${UPPOD_SIGN_IDENTITY:-}"
DMG_BACKGROUND="${UPPOD_DMG_BACKGROUND:-Resources/dmg-background.png}"
STAGING=".dmg-staging"

if [[ ! -d "$APP" ]]; then
  echo "Missing $APP. Run ./build.sh first." >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "Missing create-dmg. Install it with: brew install create-dmg" >&2
  exit 1
fi

if [[ ! -f "$DMG_BACKGROUND" ]]; then
  echo "Missing $DMG_BACKGROUND." >&2
  exit 1
fi

while IFS= read -r mounted_volume; do
  hdiutil detach "$mounted_volume" -quiet >/dev/null 2>&1 || true
done < <(find /Volumes -maxdepth 1 -type d \( -name "$VOLNAME" -o -name "$VOLNAME [0-9]*" \) -print 2>/dev/null)

echo "→ staging DMG contents"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/$APP"

echo "→ create DMG with Finder layout"
create_dmg_args=(
  --volname "$VOLNAME"
  --background "$DMG_BACKGROUND"
  --window-pos 120 120
  --window-size 760 480
  --icon-size 104
  --text-size 13
  --icon "$APP" 190 205
  --hide-extension "$APP"
  --app-drop-link 570 205
  --format UDZO
  --filesystem HFS+
  --hdiutil-retries 10
  --no-internet-enable
)

if [[ -n "$SIGN_IDENTITY" && "$SIGN_IDENTITY" != "-" ]]; then
  create_dmg_args+=(--codesign "$SIGN_IDENTITY")
else
  echo "  DMG signing skipped. Set UPPOD_SIGN_IDENTITY for Developer ID signing."
fi

if [[ "${UPPOD_NOTARIZE:-0}" == "1" ]]; then
  : "${UPPOD_NOTARY_PROFILE:?Set UPPOD_NOTARY_PROFILE for create-dmg notarization}"
  create_dmg_args+=(--notarize "$UPPOD_NOTARY_PROFILE")
fi

create-dmg "${create_dmg_args[@]}" "$DMG" "$STAGING"

rm -rf "$STAGING"

echo "→ verify DMG"
hdiutil verify "$DMG"

echo "→ sha256"
shasum -a 256 "$DMG"

echo "✓ $DMG"
