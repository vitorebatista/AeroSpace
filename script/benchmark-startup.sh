#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: benchmark-startup.sh --executable PATH --output-dir PATH [--runs N] [--revision LABEL]"
}

executable=""
output_dir=""
runs=7
revision=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --executable)
            if (( $# < 2 )); then usage >&2; exit 2; fi
            executable="$2"
            shift 2
            ;;
        --output-dir)
            if (( $# < 2 )); then usage >&2; exit 2; fi
            output_dir="$2"
            shift 2
            ;;
        --runs)
            if (( $# < 2 )); then usage >&2; exit 2; fi
            runs="$2"
            shift 2
            ;;
        --revision)
            if (( $# < 2 )); then usage >&2; exit 2; fi
            revision="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$executable" || -z "$output_dir" || ! -x "$executable" || ! "$runs" =~ ^[1-9][0-9]*$ ]]; then
    usage >&2
    exit 2
fi

if [[ -e "$output_dir/results.csv" ]]; then
    echo "Refusing to overwrite $output_dir/results.csv" >&2
    exit 2
fi

mkdir -p "$output_dir"
project_root="$(cd "$(dirname "$0")/.." && pwd -P)"
if [[ -z "$revision" ]]; then
    revision="$(git -C "$project_root" rev-parse --short HEAD)"
fi
results="$output_dir/results.csv"
printf 'revision,run,traced_launch_seconds,trace_file\n' > "$results"

for ((run = 1; run <= runs; run++)); do
    trace_path="$output_dir/run-$run.trace"
    toc_path="$output_dir/run-$run.toc.xml"
    xcrun xctrace record --template 'App Launch' --time-limit 15s --output "$trace_path" --launch -- "$executable"
    xcrun xctrace export --input "$trace_path" --toc --output "$toc_path"

    traced_launch_seconds="$(sed -n 's:.*<duration>\(.*\)</duration>.*:\1:p' "$toc_path" | head -1)"

    if [[ -z "$traced_launch_seconds" ]]; then
        echo "Failed to parse benchmark output for run $run" >&2
        exit 1
    fi
    printf '%s,%s,%s,%s\n' \
        "$revision" "$run" "$traced_launch_seconds" "$(basename "$trace_path")" >> "$results"
done

echo "Wrote $results"
