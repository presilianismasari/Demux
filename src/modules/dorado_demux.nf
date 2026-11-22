/*
 * One dorado demux run. main.nf aliases this process as FWD_DEMUX, RC_REV_DEMUX,
 * REV_DEMUX and RC_FWD_DEMUX; only the arrangement/barcodes/kit differ.
 *
 * Output is flattened regardless of how dorado nests it
 * (<out>/<experiment|no_sample>/<run_id>/fastq_pass/barcodeNN/*.fastq):
 *   demux/classified/barcodeNN.fastq.gz
 *   demux/unclassified.fastq.gz
 */
process DORADO_DEMUX {
    tag { "${meta.id}" }
    label 'dorado'

    publishDir path: { "${params.outdir}/logs/${meta.id}" }, mode: params.publish_dir_mode, pattern: '*.log'
    publishDir path: { "${params.outdir}/intermediate/${meta.id}" }, mode: params.publish_dir_mode, pattern: 'demux',
        enabled: params.save_intermediate

    input:
    tuple val(meta), path(reads, stageAs: 'input?/*')
    path arrangement
    path barcodes
    val kit

    output:
    tuple val(meta), path('demux/classified/*.fastq.gz'), optional: true, emit: classified
    tuple val(meta), path('demux/unclassified.fastq.gz'), optional: true, emit: unclassified
    path 'counts.tsv'                                                   , emit: counts
    path 'demux'                                                        , emit: demux
    path '*.log'                                                        , emit: logs

    script:
    def args = params.dorado_args ?: ''
    """
    set -o pipefail
    mkdir -p reads dorado_out

    for f in input*/*; do
        case "\$f" in
            *.gz) gzip -dc -- "\$f" ;;
            *)    cat -- "\$f" ;;
        esac
    done > reads/${meta.id}.fastq

    if [ -s reads/${meta.id}.fastq ]; then
        dorado demux \\
            --barcode-arrangement ${arrangement} \\
            --barcode-sequences ${barcodes} \\
            --kit-name ${kit} \\
            --emit-fastq \\
            --emit-summary \\
            --threads ${task.cpus} \\
            ${args} \\
            --output-dir dorado_out \\
            reads 2>&1 | tee ${meta.id}.log
    else
        echo "No input reads for ${meta.id}; skipping dorado" | tee ${meta.id}.log
    fi

    normalize_dorado_output.sh dorado_out demux ${meta.stage} ${meta.parent} counts.tsv ${task.cpus}
    rm -rf reads dorado_out
    """

    stub:
    """
    mkdir -p demux/classified
    for bc in barcode01 barcode02; do
        printf '@${meta.id}_%s\\nACGTACGTAC\\n+\\nIIIIIIIIII\\n' "\$bc" | gzip > demux/classified/\${bc}.fastq.gz
        printf '${meta.stage}\\t${meta.parent}\\t%s\\t1\\t10\\n' "\$bc" >> counts.tsv
    done
    printf '@${meta.id}_unclassified\\nACGTACGTAC\\n+\\nIIIIIIIIII\\n' | gzip > demux/unclassified.fastq.gz
    printf '${meta.stage}\\t${meta.parent}\\tunclassified\\t1\\t10\\n' >> counts.tsv
    touch ${meta.id}.log
    """
}
