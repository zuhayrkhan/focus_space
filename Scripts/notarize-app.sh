#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_dir="$project_dir/.build/Focus Space.app"
archive="$project_dir/.build/Focus-Space-notarization.zip"
signing_identity=${SIGNING_IDENTITY:-}
notary_profile=${NOTARY_PROFILE:-}

case "$signing_identity" in
    "Developer ID Application:"*) ;;
    *) echo "SIGNING_IDENTITY must name an installed Developer ID Application certificate." >&2; exit 2 ;;
esac
[ -n "$notary_profile" ] || { echo "NOTARY_PROFILE must name a notarytool keychain profile." >&2; exit 2; }

SIGNING_IDENTITY="$signing_identity" "$project_dir/Scripts/package-app.sh" >/dev/null
rm -f "$archive"
/usr/bin/ditto -c -k --keepParent "$app_dir" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$app_dir"
xcrun stapler validate "$app_dir"
spctl --assess --type execute --verbose=2 "$app_dir"

echo "$app_dir"
