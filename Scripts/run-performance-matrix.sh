#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
report_dir=${1:-"$project_dir/.build/performance-u5"}
app_dir="$project_dir/.build/Focus Space.app"
binary="$app_dir/Contents/MacOS/FocusSpace"

"$project_dir/Scripts/package-app.sh" >/dev/null
mkdir -p "$report_dir"

read_json() {
    plutil -extract "$2" raw -o - "$1"
}

assert_number() {
    value=$1
    comparison=$2
    limit=$3
    message=$4
    if ! awk "BEGIN { exit !($value $comparison $limit) }"; then
        echo "FAILED: $message ($value $comparison $limit)" >&2
        exit 1
    fi
}

printf "%-8s %-9s %7s %9s %8s %8s %8s %8s %7s\n" \
    "fixture" "window" "nodes" "launch" "fps" "preview" "search" "arrange" "AX"

for fixture in dense animals large; do
    case "$fixture" in
        dense) expected_nodes=32; launch_budget=1100 ;;
        animals) expected_nodes=65; launch_budget=1100 ;;
        large) expected_nodes=180; launch_budget=2000 ;;
    esac

    for window_size in compact standard large; do
        case "$window_size" in
            compact) expected_width=980; expected_height=702 ;;
            standard) expected_width=1240; expected_height=780 ;;
            large) expected_width=1260; expected_height=820 ;;
        esac

        report="$report_dir/$fixture-$window_size.json"
        log="$report_dir/$fixture-$window_size.log"
        "$binary" \
            -ApplePersistenceIgnoreState YES \
            --demo "$fixture" \
            --window-size "$window_size" \
            --performance-seconds 3 \
            --performance-report "$report" >"$log" 2>&1

        test -s "$report"
        node_count=$(read_json "$report" nodeCount)
        launch=$(read_json "$report" launchMilliseconds)
        fps=$(read_json "$report" framesPerSecond)
        preview_fps=$(read_json "$report" diagnosticPreviewFramesPerSecond)
        search=$(read_json "$report" operations.search_framing.maximumMilliseconds)
        arrange=$(read_json "$report" operations.arrange.maximumMilliseconds)
        accessibility_count=$(read_json "$report" spatialAccessibilityItemCount)
        complete_count=$(read_json "$report" completeListItemCount)
        width=$(read_json "$report" windowWidth)
        height=$(read_json "$report" windowHeight)

        test "$node_count" -eq "$expected_nodes"
        test "$complete_count" -eq "$expected_nodes"
        assert_number "$launch" "<" "$launch_budget" "$fixture $window_size launch budget"
        assert_number "$fps" ">=" 30 "$fixture $window_size presentation cadence"
        assert_number "$preview_fps" ">=" 30 "$fixture $window_size diagnostic preview cadence"
        assert_number "$search" "<" 100 "$fixture $window_size search budget"
        assert_number "$arrange" "<" 250 "$fixture $window_size Arrange budget"
        assert_number "$accessibility_count" "<=" 48 "$fixture $window_size spatial accessibility limit"
        assert_number "$width" "==" "$expected_width" "$fixture $window_size requested width"
        assert_number "$height" "==" "$expected_height" "$fixture $window_size requested height"

        for operation in \
            launch_to_interactive \
            snapshot_derivation \
            renderer_reconciliation \
            relationship_reconciliation \
            accessibility_representation \
            arrange \
            search_framing \
            option_drag_preview
        do
            samples=$(read_json "$report" "operations.$operation.sampleCount")
            test "$samples" -gt 0
        done

        printf "%-8s %-9s %7s %7.0fms %7.1f %8.1f %6.2fms %6.2fms %7s\n" \
            "$fixture" "$window_size" "$node_count" "$launch" "$fps" "$preview_fps" \
            "$search" "$arrange" "$accessibility_count"
    done
done

echo "Performance matrix passed: $report_dir"
