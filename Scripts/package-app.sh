#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${CONFIGURATION:-release}
app_dir="$project_dir/.build/Focus Space.app"
executable="$project_dir/.build/$configuration/FocusSpace"
signing_identity=${SIGNING_IDENTITY:--}
release_version=${RELEASE_VERSION:-0.1.0}
release_build=${RELEASE_BUILD:-1}

swift build --package-path "$project_dir" --configuration "$configuration"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$executable" "$app_dir/Contents/MacOS/FocusSpace"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $release_version" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $release_build" "$app_dir/Contents/Info.plist"

if [ "$signing_identity" = "-" ]; then
    codesign --force --deep --sign - "$app_dir"
else
    codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$app_dir"
fi
codesign --verify --deep --strict --verbose=2 "$app_dir"

echo "$app_dir"
