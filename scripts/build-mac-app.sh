#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
configuration=${1:-release}
case "$configuration" in debug|release) ;; *) echo "Usage: $0 [debug|release]" >&2; exit 1 ;; esac
# SwiftUI's @State is a macro in the macOS 27 SDK; its plugin ships with Xcode, not Command Line Tools.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build -c "$configuration" --product Clipper
bin_dir=$(swift build -c "$configuration" --show-bin-path)
app_dir="$PWD/.build/Clipper.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Frameworks"
cp "$bin_dir/Clipper" "$app_dir/Contents/MacOS/Clipper"
cp Configuration/MacDevelopment-Info.plist "$app_dir/Contents/Info.plist"
# SwiftPM's resource accessor searches beside the bundle URL in an app launch.
for resource in "$bin_dir"/*.bundle; do
    [ -d "$resource" ] || continue
    cp -R "$resource" "$app_dir/"
done
# The FFmpeg frameworks are dynamic. Embed them so the app runs on Macs without this build tree.
for framework in "$bin_dir"/*.framework "$bin_dir"/PackageFrameworks/*.framework; do
    [ -d "$framework" ] || continue
    ditto "$framework" "$app_dir/Contents/Frameworks/$(basename "$framework")"
done
install_name_tool -add_rpath @executable_path/../Frameworks "$app_dir/Contents/MacOS/Clipper" 2>/dev/null || true
# Sign inside-out: nested frameworks first, then the app.
for framework in "$app_dir"/Contents/Frameworks/*.framework; do
    [ -d "$framework" ] || continue
    codesign --force --sign - "$framework"
done
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf 'App: %s\n' "$app_dir"
