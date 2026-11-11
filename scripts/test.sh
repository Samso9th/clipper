#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
developer_dir=$(xcode-select -p)
if [ "$(basename "$developer_dir")" = "CommandLineTools" ]; then
    # CLT ships Swift Testing, but SwiftPM does not automatically find its frameworks.
    frameworks="$developer_dir/Library/Developer/Frameworks"
    interop="$developer_dir/Library/Developer/usr/lib"
    exec swift test --disable-xctest \
        -Xswiftc -F -Xswiftc "$frameworks" \
        -Xswiftc -plugin-path -Xswiftc "$developer_dir/usr/lib/swift/host/plugins/testing" \
        -Xlinker -F -Xlinker "$frameworks" \
        -Xlinker -rpath -Xlinker "$frameworks" \
        -Xlinker -rpath -Xlinker "$interop" "$@"
else
    exec swift test "$@"
fi
