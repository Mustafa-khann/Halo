#!/bin/bash
set -euo pipefail
halo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$halo_root"
halo_swift="$(xcrun --find swiftc)"
testing_plugin="$(dirname "$halo_swift")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$testing_plugin" ]]; then
    swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$testing_plugin"
else
    swift test --disable-xctest
fi
