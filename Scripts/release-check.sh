#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

swift test --package-path "$project_dir"
"$project_dir/Scripts/package-app.sh" >/dev/null
app_dir="$project_dir/.build/Focus Space.app"
plutil -lint "$app_dir/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app_dir"
test -x "$app_dir/Contents/MacOS/FocusSpace"
test -f "$app_dir/Contents/Resources/AppIcon.icns"

echo "Release check passed: $app_dir"
