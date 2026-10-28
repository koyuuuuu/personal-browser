#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
baseline=12f15dbe922d7d6f7a5de86345b2d5ee2d2b346f
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
git archive 0064cf7d7047ba94f27b4722f88ff91641918b77 Sources/BrowserCore | tar -x -C "$directory/stable"
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

# New actions must not make the shipped 0.6.0 reader reject toolbar.json.
mkdir -p "$directory/recent"
git archive v0.6.0-build.42 Sources/BrowserCore | tar -x -C "$directory/recent"
swiftc -parse-as-library "$directory"/recent/Sources/BrowserCore/*.swift scripts/toolbar_compatibility_runner.swift -o "$directory/old-toolbar"
swiftc -parse-as-library -D CURRENT_TOOLBAR Sources/BrowserCore/*.swift scripts/toolbar_compatibility_runner.swift -o "$directory/new-toolbar"
"$directory/old-toolbar" "$directory" seed
"$directory/new-toolbar" "$directory" enhance
"$directory/old-toolbar" "$directory" verifyLegacy
"$directory/new-toolbar" "$directory" verifyEnhanced
"$directory/old-toolbar" "$directory" editLegacy
"$directory/new-toolbar" "$directory" verifyEdited
echo '0.6.0 → current → 0.6.0 → current: toolbar readable; latest rollback edits respected.'
