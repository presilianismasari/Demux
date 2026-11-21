/*
 * Render the Quarto demux statistics report -> report/demux.html
 */
process DEMUX_REPORT {
    label 'report'

    publishDir "${params.outdir}/report", mode: params.publish_dir_mode

    input:
    path(qmd)
    path(stage_counts, stageAs: 'stage_counts.tsv')
    path(sample_stats, stageAs: 'sample_stats.tsv')
    path(sample_meta, stageAs: 'samples_metadata.tsv')

    output:
    path 'demux.html', emit: html

    script:
    """
    export HOME=\$PWD XDG_CACHE_HOME=\$PWD/.cache XDG_DATA_HOME=\$PWD/.local/share

    printf 'key\\tvalue\\n' > run_info.tsv
    printf 'run_name\\t%s\\n'   "${workflow.runName}"             >> run_info.tsv
    printf 'pipeline\\t%s\\n'   "${workflow.manifest.name} ${workflow.manifest.version}" >> run_info.tsv
    printf 'nextflow\\t%s\\n'   "${nextflow.version}"             >> run_info.tsv
    printf 'input\\t%s\\n'      "${params.input}"                 >> run_info.tsv
    printf 'metadata\\t%s\\n'   "${params.metadata}"              >> run_info.tsv
    printf 'date\\t%s\\n'       "${new Date().format('yyyy-MM-dd HH:mm')}" >> run_info.tsv

    cp -L ${qmd} demux.qmd
    quarto render demux.qmd --output demux.html
    """

    stub:
    """
    touch demux.html
    """
}
