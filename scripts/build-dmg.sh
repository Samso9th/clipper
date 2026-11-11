#!/bin/sh
# Builds .build/Clipper-<version>.dmg: Clipper.app plus an Applications shortcut to drag onto.
set -eu
cd "$(dirname "$0")/.."
./scripts/build-mac-app.sh release
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Configuration/MacDevelopment-Info.plist)
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
ditto .build/Clipper.app "$staging/Clipper.app"
ln -s /Applications "$staging/Applications"
dmg="$PWD/.build/Clipper-$version.dmg"
rm -f "$dmg"
hdiutil create -volname "Clipper" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
codesign --force --sign - "$dmg"
printf 'DMG: %s\n' "$dmg"
