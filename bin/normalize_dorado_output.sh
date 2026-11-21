#!/usr/bin/env bash
# Flatten dorado demux output, however it is nested
# (<dorado_out>/<experiment|no_sample>/<run_id>/fastq_pass/barcodeNN/*.fastq), into
#   <outdir>/classified/<barcode>.fastq.gz
#   <outdir>/unclassified.fastq.gz
# and write one "<stage>\t<parent>\t<barcode>\t<reads>\t<bases>" row per barcode to <counts.tsv>.
# Same-named folders from different run ids are merged; barcodes without reads are not written.
#
# Usage: normalize_dorado_output.sh <dorado_out> <outdir> <stage> <parent> <counts.tsv> [threads]
set -euo pipefail

src=$1
out=$2
stage=$3
parent=$4
counts=$5
threads=${6:-1}

if command -v pigz >/dev/null 2>&1; then
    gz=(pigz -p "$threads" -c)
else
    gz=(gzip -c)
fi

emit_plain() {
    for f in "$@"; do
        case "$f" in
            *.gz) gzip -dc -- "$f" ;;
            *)    cat -- "$f" ;;
        esac
    done
}

mkdir -p "$out/classified"
: > "$counts"

names=()
if [[ -d "$src" ]]; then
    mapfile -t names < <(find "$src" -type d \( -name 'barcode*' -o -name unclassified \) -printf '%f\n' | sort -u)
fi

for name in "${names[@]}"; do
    mapfile -d '' -t files < <(
        find "$src" -type d -name "$name" -print0 |
            xargs -0 -r -I{} find {} -maxdepth 1 -type f \( -name '*.fastq' -o -name '*.fastq.gz' \) -print0 |
            sort -z
    )
    [[ ${#files[@]} -gt 0 ]] || continue

    read -r reads bases < <(count_fastq.sh "${files[@]}")
    printf '%s\t%s\t%s\t%s\t%s\n' "$stage" "$parent" "$name" "$reads" "$bases" >> "$counts"
    [[ "$reads" -gt 0 ]] || continue

    if [[ "$name" == unclassified ]]; then
        target="$out/unclassified.fastq.gz"
    else
        target="$out/classified/$name.fastq.gz"
    fi
    emit_plain "${files[@]}" | "${gz[@]}" > "$target"
done
