#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
baseline=438292f5622801bf56525381576b789f65e4d203
directory="$(mktemp -d "${TMPDIR:-/tmp}/browser-compatibility.XXXXXX")"
trap 'rm -rf "$directory"' EXIT
mkdir -p "$directory/legacy"
git archive "$baseline" Sources/BrowserCore | tar -x -C "$directory/legacy"
swiftc -parse-as-library "$directory"/legacy/Sources/BrowserCore/*.swift scripts/compatibility_runner.swift -o "$directory/old-app"
swiftc -parse-as-library Sources/BrowserCore/*.swift scripts/compatibility_runner.swift -o "$directory/new-app"
file="$directory/browser.json"
"$directory/old-app" write "$file" 1
"$directory/new-app" verify "$file" 1
"$directory/new-app" write "$file" 2
"$directory/old-app" verify "$file" 2
"$directory/old-app" write "$file" 3
"$directory/new-app" verify "$file" 3
echo 'Legacy → current → legacy → current: latest bookmarks and history preserved.'
