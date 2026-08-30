#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: benchmark-startup.sh --executable PATH --output-dir PATH [--runs N]"
}

executable=""
output_dir=""
runs=7

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
revision="$(git -C "$project_root" rev-parse --short HEAD)"
results="$output_dir/results.csv"
printf 'revision,run,traced_launch_seconds,direct_real_seconds,direct_user_seconds,direct_system_seconds,direct_max_rss_bytes,trace_file\n' > "$results"

for ((run = 1; run <= runs; run++)); do
    trace_path="$output_dir/run-$run.trace"
    toc_path="$output_dir/run-$run.toc.xml"
    time_path="$output_dir/run-$run.time.txt"

    xcrun xctrace record --template 'App Launch' --time-limit 15s --output "$trace_path" --launch -- "$executable"
    xcrun xctrace export --input "$trace_path" --toc --output "$toc_path"
    /usr/bin/time -l "$executable" 2> "$time_path"

    traced_launch_seconds="$(sed -n 's:.*<duration>\(.*\)</duration>.*:\1:p' "$toc_path" | head -1)"
    direct_real_seconds="$(awk 'NR == 1 { print $1 }' "$time_path")"
    direct_user_seconds="$(awk 'NR == 1 { print $3 }' "$time_path")"
    direct_system_seconds="$(awk 'NR == 1 { print $5 }' "$time_path")"
    direct_max_rss_bytes="$(awk '/maximum resident set size/ { print $1 }' "$time_path")"

    if [[ -z "$traced_launch_seconds" || -z "$direct_real_seconds" || -z "$direct_user_seconds" || -z "$direct_system_seconds" || -z "$direct_max_rss_bytes" ]]; then
        echo "Failed to parse benchmark output for run $run" >&2
        exit 1
    fi
    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$revision" "$run" "$traced_launch_seconds" "$direct_real_seconds" \
        "$direct_user_seconds" "$direct_system_seconds" "$direct_max_rss_bytes" "$(basename "$trace_path")" >> "$results"
done

echo "Wrote $results"
