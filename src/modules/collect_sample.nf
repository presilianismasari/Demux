/*
 * STAGE 5: concatenate the forward-orientation and reverse-orientation reads of one sample
 * into <sample>.fastq.gz (concatenated gzip members are valid gzip).
 */
process COLLECT_SAMPLE {
    tag "${meta.customer}/${meta.sample}"

    publishDir "${params.outdir}/demux/${meta.customer}/${meta.sample}", mode: params.publish_dir_mode, pattern: '*.fastq.gz'

    input:
    tuple val(meta), path(fwd, stageAs: 'fwd/*'), path(rev, stageAs: 'rev/*')

    output:
    tuple val(meta), path("${meta.sample}.fastq.gz"), emit: reads
    path "${meta.sample}.stats.tsv"                 , emit: stats

    script:
    """
    shopt -s nullglob
    fwd_files=(fwd/*)
    rev_files=(rev/*)

    cat "\${fwd_files[@]}" "\${rev_files[@]}" > ${meta.sample}.fastq.gz
    gzip -t ${meta.sample}.fastq.gz

    read -r fwd_reads fwd_bases < <(count_fastq.sh "\${fwd_files[@]}")
    read -r rev_reads rev_bases < <(count_fastq.sh "\${rev_files[@]}")

    printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \\
        "${meta.customer}" "${meta.sample}" \\
        "\$fwd_reads" "\$fwd_bases" "\$rev_reads" "\$rev_bases" \\
        "\$((fwd_reads + rev_reads))" "\$((fwd_bases + rev_bases))" \\
        > ${meta.sample}.stats.tsv
    """

    stub:
    """
    shopt -s nullglob
    cat fwd/* rev/* > ${meta.sample}.fastq.gz
    printf '${meta.customer}\\t${meta.sample}\\t1\\t10\\t1\\t10\\t2\\t20\\n' > ${meta.sample}.stats.tsv
    """
}
