#!/bin/bash
set -euo pipefail
halo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$halo_root"
[[ -n "${SIGNING_IDENTITY:-}" ]] || { echo "Set SIGNING_IDENTITY to your Developer ID Application identity." >&2; exit 1; }
[[ -n "${NOTARY_PROFILE:-}" ]] || { echo "Set NOTARY_PROFILE to your saved notarytool keychain profile." >&2; exit 1; }
scripts/build.sh release
scripts/package-dmg.sh
version="$(/usr/libexec/PlistBuddy -c 'Print:CFBundleShortVersionString' dist/Halo.app/Contents/Info.plist)"
filename="Halo-$version.dmg"
xcrun notarytool submit "dist/$filename" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "dist/$filename"
xcrun stapler validate "dist/$filename"
spctl --assess --type open --context context:primary-signature --verbose "dist/$filename"
(
    cd "$halo_root/dist"
    shasum -a 256 "$filename" > "$filename.sha256"
)
echo "Halo is signed, notarized, and ready to distribute."
