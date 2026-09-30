#!/bin/bash
set -euo pipefail
halo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$halo_root"
[[ -d dist/Halo.app ]] || { echo "Build Halo first with scripts/build.sh" >&2; exit 1; }
halo_python="${HALO_PYTHON:-python3.11}"
if [[ ! -x .build/dmg-tools/bin/python ]]; then
    "$halo_python" -m venv .build/dmg-tools
    .build/dmg-tools/bin/python -m pip install --quiet 'ds-store==1.3.3' 'mac-alias==2.2.3'
fi
work="$halo_root/.build/dmg"
mount="$work/mount"
stage="$work/stage"
mkdir -p "$mount"
rm -rf "$stage"
mkdir -p "$stage/.background"
ditto dist/Halo.app "$stage/Halo.app"
ln -sfn /Applications "$stage/Applications"
cp Resources/InstallerBackground.png "$stage/.background/background.png"
cp dist/Halo.app/Contents/Resources/AppIcon.icns "$stage/.VolumeIcon.icns"
temporary="$work/Halo-rw.dmg"
version="$(/usr/libexec/PlistBuddy -c 'Print:CFBundleShortVersionString' dist/Halo.app/Contents/Info.plist)"
filename="Halo-$version.dmg"
output="$halo_root/dist/$filename"
mounted=false
cleanup() { if $mounted; then hdiutil detach "$mount" -quiet || true; fi; }
trap cleanup EXIT
hdiutil create -srcfolder "$stage" -fs HFS+ -volname Halo -format UDRW -ov "$temporary" -quiet
hdiutil attach "$temporary" -mountpoint "$mount" -nobrowse -quiet
mounted=true
xattr -wx com.apple.FinderInfo 0000000000000000040000000000000000000000000000000000000000000000 "$mount"
.build/dmg-tools/bin/python scripts/dmg-layout.py "$mount"
hdiutil detach "$mount" -quiet
mounted=false
hdiutil convert "$temporary" -format UDZO -o "$output" -ov -quiet
rm "$temporary"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$output"; fi
hdiutil verify "$output" -quiet
(
    cd "$halo_root/dist"
    shasum -a 256 "$filename" > "$filename.sha256"
)
echo "Installer: $output"
