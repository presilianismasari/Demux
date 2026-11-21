#!/usr/bin/env bash
# Print "<reads>\t<bases>" for the given FASTQ files (plain or .gz). No files -> "0\t0".
set -euo pipefail

for f in "$@"; do
    case "$f" in
        *.gz) gzip -dc -- "$f" ;;
        *)    cat -- "$f" ;;
    esac
done | awk 'NR % 4 == 2 { b += length($0) } END { printf "%d\t%d\n", NR / 4, b }'
