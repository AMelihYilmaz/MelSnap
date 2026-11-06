#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
app="${1:-MelSnap ${version%.0}.app}"
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
bundle="$temp/MelSnap.app"
mkdir -p "$bundle/Contents/MacOS"
swiftc -parse-as-library -module-cache-path "${MELSNAP_SWIFT_CACHE:-$temp/cache}" MelSnap.swift -o "$bundle/Contents/MacOS/MelSnap"
cp Info.plist "$bundle/Contents/"
if [[ -f MelSnap.icns ]]; then
    mkdir -p "$bundle/Contents/Resources"
    cp MelSnap.icns "$bundle/Contents/Resources/"
fi
codesign --force --sign - "$bundle"
ditto --norsrc "$bundle" "$app"
codesign --verify --strict "$app"
