#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${CONFIGURATION:-release}
app_dir="$project_dir/.build/Focus Space.app"
executable="$project_dir/.build/$configuration/FocusSpace"

swift build --package-path "$project_dir" --configuration "$configuration"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$executable" "$app_dir/Contents/MacOS/FocusSpace"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
