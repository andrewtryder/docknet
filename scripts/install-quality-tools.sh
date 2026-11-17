#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tools_dir="$root/build/tools"
mkdir -p "$tools_dir/bin" "$tools_dir/downloads"
install_tool() {
    local name="$1" version="$2" url="$3" digest="$4"
    local archive="$tools_dir/downloads/$name-$version.zip"
    local version_arg=--version
    [ "$name" = swiftlint ] && version_arg=version
    if [ -x "$tools_dir/bin/$name" ] && [ "$("$tools_dir/bin/$name" "$version_arg" 2>/dev/null || true)" = "$version" ]; then
        return
    fi
    curl --fail --location --silent --show-error "$url" -o "$archive"
    printf "%s  %s\n" "$digest" "$archive" | shasum -a 256 -c -
    unzip -oq "$archive" "$name" -d "$tools_dir/bin"
    chmod +x "$tools_dir/bin/$name"
}
install_tool swiftlint 0.65.1 https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0
install_tool swiftformat 0.64.7 https://github.com/nicklockwood/SwiftFormat/releases/download/0.64.7/swiftformat.zip e82e224325cbd3403fc7b68caf6c917926dc106de3af875fca4b87e3c4634038
