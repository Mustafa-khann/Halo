#!/bin/bash
set -euo pipefail
halo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="$1"
shift
adapter="$halo_root/ThirdParty/MediaRemoteAdapter"
framework="$destination/MediaRemoteAdapter.framework"
mkdir -p "$framework/Versions/A/Resources" "$halo_root/.build/media-helper"
sources=()
for source in env get globals keys now_playing repeat seek send shuffle speed stream test; do
    sources+=("$adapter/src/adapter/$source.m")
done
sources+=("$adapter/src/private/MediaRemote.m" "$adapter/src/utility/Debounce.m" "$adapter/src/utility/helpers.m")
sources+=("$halo_root/Resources/MediaHelperParentMonitor.m")
binaries=()
for architecture in "$@"; do
    binary="$halo_root/.build/media-helper/MediaRemoteAdapter-$architecture"
    xcrun clang -arch "$architecture" -mmacosx-version-min=14.0 -dynamiclib -O2 -fobjc-arc \
        -fvisibility=default -I "$adapter/include" -I "$adapter/src" \
        -install_name '@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter' \
        -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
        "${sources[@]}" -o "$binary"
    binaries+=("$binary")
done
lipo -create "${binaries[@]}" -output "$framework/Versions/A/MediaRemoteAdapter"
cat > "$framework/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
<key>CFBundleName</key><string>MediaRemoteAdapter</string>
<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>0.1.0</string>
</dict></plist>
PLIST
ln -s A "$framework/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$framework/MediaRemoteAdapter"
ln -s Versions/Current/Resources "$framework/Resources"
