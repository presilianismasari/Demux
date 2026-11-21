/*
 * STAGE 6: NanoPlot QC per sample -> NanoPlot/<customer>/<sample>/
 */
process NANOPLOT {
    tag "${meta.customer}/${meta.sample}"
    label 'nanoplot'

    publishDir "${params.outdir}/NanoPlot/${meta.customer}", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${meta.sample}"), emit: results

    script:
    def args = params.nanoplot_args ?: ''
    """
    NanoPlot \\
        --fastq ${reads} \\
        --outdir ${meta.sample} \\
        --threads ${task.cpus} \\
        ${args}
    """

    stub:
    """
    mkdir -p ${meta.sample}
    touch ${meta.sample}/NanoPlot-report.html
    """
}
