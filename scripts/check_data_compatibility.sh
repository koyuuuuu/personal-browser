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

# The user's accepted rollback baseline: preserve current favorites and ordering.
mkdir -p "$directory/stable"
git archive 70052bb73a2170eb516bb99aece43b13918a0553 Sources/BrowserCore | tar -x -C "$directory/stable"
swiftc -parse-as-library "$directory"/stable/Sources/BrowserCore/*.swift scripts/favorites_compatibility_runner.swift -o "$directory/stable-app"
swiftc -parse-as-library Sources/BrowserCore/*.swift scripts/favorites_compatibility_runner.swift -o "$directory/current-favorites"
extras="$directory/library-extras.json"
"$directory/stable-app" write "$extras" 1
"$directory/current-favorites" verify "$extras" 1
"$directory/current-favorites" write "$extras" 2
"$directory/stable-app" verify "$extras" 2
"$directory/stable-app" write "$extras" 3
"$directory/current-favorites" verify "$extras" 3
echo '0.4.2 → current → 0.4.2 → current: latest favorites and order preserved.'
