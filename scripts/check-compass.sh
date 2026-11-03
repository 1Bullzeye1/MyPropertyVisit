#!/bin/sh
set -eu
# Requires a booted iOS simulator. Optional first argument is its UDID.
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/propertylens-compass.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
cat "$project_root/ios/Ganesham/WalkthroughView.swift" "$project_root/tests/CompassChecks.swift" > "$check_dir/main.swift"
sdk_path=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator swiftc -sdk "$sdk_path" -target "$(uname -m)-apple-ios17.0-simulator" "$check_dir/main.swift" -o "$check_dir/checks"
xcrun simctl spawn "${1:-booted}" "$check_dir/checks"
