#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/mypropertyvisit-sessions.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
cat "$project_root/ios/MyPropertyVisit/ContentView.swift" "$project_root/ios/MyPropertyVisit/WalkthroughView.swift" "$project_root/ios/MyPropertyVisit/RoomPhotos.swift" "$project_root/tests/CaptureSessionChecks.swift" > "$check_dir/main.swift"
sdk_path=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator swiftc -sdk "$sdk_path" -target "$(uname -m)-apple-ios17.0-simulator" "$check_dir/main.swift" -o "$check_dir/checks"
xcrun simctl spawn "${1:-booted}" "$check_dir/checks"
