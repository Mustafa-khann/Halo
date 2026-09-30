#!/bin/bash
set -euo pipefail
halo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-release}"
if [[ "$configuration" != debug && "$configuration" != release ]]; then
    echo "Usage: scripts/build.sh [debug|release]" >&2; exit 1
fi
cd "$halo_root"
mkdir -p dist
if [[ "$configuration" == release ]]; then
    architectures=(arm64 x86_64)
else
    architectures=("$(uname -m)")
fi
binaries=()
mkdir -p .build/release-binaries
for architecture in "${architectures[@]}"; do
    swift build -c "$configuration" --triple "$architecture-apple-macosx14.0"
    binary_path="$(swift build -c "$configuration" --triple "$architecture-apple-macosx14.0" --show-bin-path)"
    lipo -verify_arch "$architecture" "$binary_path/Halo"
    architecture_binary="$halo_root/.build/release-binaries/Halo-$architecture"
    cp "$binary_path/Halo" "$architecture_binary"
    binaries+=("$architecture_binary")
done
app="$halo_root/.build/bundle/Halo.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ ${#binaries[@]} -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/Halo"
else
    cp "${binaries[0]}" "$app/Contents/MacOS/Halo"
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/artwork.swift "$halo_root"
iconutil -c icns Resources/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
cp Resources/AppIcon.png "$app/Contents/Resources/AppIcon.png"
identity="${SIGNING_IDENTITY:--}"
if [[ "$identity" == "-" ]]; then
    codesign --force --sign - --options runtime --entitlements Resources/Halo.entitlements "$app"
else
    codesign --force --sign "$identity" --timestamp --options runtime --entitlements Resources/Halo.entitlements "$app"
fi
codesign --verify --deep --strict "$app"
rm -rf "$halo_root/dist/Halo.app"
mv "$app" "$halo_root/dist/Halo.app"
app="$halo_root/dist/Halo.app"
echo "Built: $app"
lipo -archs "$app/Contents/MacOS/Halo"
