#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_dir="$project_dir/.build/Focus Space.app"

"$project_dir/Scripts/package-app.sh" >/dev/null

if [ "$#" -gt 0 ]; then
    open -n "$app_dir" --args "$@"
else
    open -n "$app_dir"
fi
