#!/usr/bin/env nextflow

/*
 * Custom demultiplexing of PacBio 16S barcoded primers sequenced on ONT (dorado).
 *
 *   STAGE 1  FWD_DEMUX      front barcode of the forward primer      (forward reads)
 *   STAGE 2  RC_REV_DEMUX   rear barcode = RC of reverse primer      (per STAGE 1 barcode)
 *   STAGE 3  REV_DEMUX      front barcode of the reverse primer      (STAGE 1 unclassified)
 *   STAGE 4  RC_FWD_DEMUX   rear barcode = RC of forward primer      (per STAGE 3 barcode)
 *   STAGE 5  COLLECT_SAMPLE merge forward + reverse reads per sample (metadata driven)
 *   STAGE 6  NANOPLOT       QC per sample
 *            DEMUX_REPORT   demux statistics (Quarto -> demux.html)
 */

nextflow.enable.dsl = 2

include { DORADO_DEMUX as FWD_DEMUX    } from './src/modules/dorado_demux'
include { DORADO_DEMUX as RC_REV_DEMUX } from './src/modules/dorado_demux'
include { DORADO_DEMUX as REV_DEMUX    } from './src/modules/dorado_demux'
include { DORADO_DEMUX as RC_FWD_DEMUX } from './src/modules/dorado_demux'
include { COLLECT_SAMPLE               } from './src/modules/collect_sample'
include { NANOPLOT                     } from './src/modules/nanoplot'
include { DEMUX_REPORT                 } from './src/modules/demux_report'
include { parseMetadata; perBarcode    } from './src/functions'

def dorado(String name) {
    return file("${projectDir}/assets/dorado/${name}", checkIfExists: true)
}

workflow {
    main:
    if (!params.input)    { error "Missing --input (fastq/fastq.gz glob or directory)" }
    if (!params.metadata) { error "Missing --metadata (tab-separated sample sheet)" }

    log.info """
    ===== PacBio16S custom demux =====
    input    : ${params.input}
    metadata : ${params.metadata}
    outdir   : ${params.outdir}
    ==================================
    """.stripIndent()

    def samples = parseMetadata(file(params.metadata, checkIfExists: true))
    log.info "Metadata: ${samples.size()} samples, ${samples*.customer.unique().size()} customers"

    def inputPattern = (!params.input.contains('*') && file(params.input).isDirectory())
        ? "${params.input}/**/*.{fastq,fastq.gz}"
        : params.input

    ch_reads = Channel.fromPath(inputPattern, checkIfExists: true)
        .toList()
        .map { files -> [[id: 'FWD_DEMUX', stage: 'FWD_DEMUX', parent: 'all'], files] }

    // STAGE 1: forward primer, front barcode
    FWD_DEMUX(
        ch_reads,
        dorado('PacBio_16S_forward.toml'),
        dorado('barcodes_forward.fasta'),
        'PacBio_16S_forward'
    )

    // STAGE 2: RC of reverse primer (rear barcode) on every STAGE 1 barcode
    RC_REV_DEMUX(
        FWD_DEMUX.out.classified
            .flatMap { meta, files -> perBarcode(files) }
            .map { bc, f -> [[id: "RC_REV_DEMUX_${bc}", stage: 'RC_REV_DEMUX', parent: bc], f] },
        dorado('PacBio_16S_rc-reverse.toml'),
        dorado('barcodes_rc-reverse.fasta'),
        'PacBio_16S_rc-reverse'
    )

    // STAGE 3: reverse primer, front barcode, on reads left unclassified by STAGE 1
    REV_DEMUX(
        FWD_DEMUX.out.unclassified
            .map { meta, f -> [[id: 'REV_DEMUX', stage: 'REV_DEMUX', parent: 'unclassified'], f] },
        dorado('PacBio_16S_reverse.toml'),
        dorado('barcodes_reverse.fasta'),
        'PacBio_16S_reverse'
    )

    // STAGE 4: RC of forward primer (rear barcode) on every STAGE 3 barcode
    RC_FWD_DEMUX(
        REV_DEMUX.out.classified
            .flatMap { meta, files -> perBarcode(files) }
            .map { bc, f -> [[id: "RC_FWD_DEMUX_${bc}", stage: 'RC_FWD_DEMUX', parent: bc], f] },
        dorado('PacBio_16S_rc-forward.toml'),
        dorado('barcodes_rc-forward.fasta'),
        'PacBio_16S_rc-forward'
    )

    // STAGE 5: look up each sample's forward and reverse barcode combination
    ch_fwd_map = RC_REV_DEMUX.out.classified
        .flatMap { meta, files -> perBarcode(files).collect { bc, f -> ["${meta.parent}|${bc}".toString(), f] } }
        .toList()
        .map { pairs -> pairs.collectEntries { [(it[0]): it[1]] } }

    ch_rev_map = RC_FWD_DEMUX.out.classified
        .flatMap { meta, files -> perBarcode(files).collect { bc, f -> ["${meta.parent}|${bc}".toString(), f] } }
        .toList()
        .map { pairs -> pairs.collectEntries { [(it[0]): it[1]] } }

    ch_matched = Channel.fromList(samples)
        .combine(ch_fwd_map)
        .combine(ch_rev_map)
        .map { row, fwd_map, rev_map ->
            [row, fwd_map["${row.fwd_front}|${row.fwd_rear}".toString()], rev_map["${row.rev_front}|${row.rev_rear}".toString()]]
        }

    ch_matched.subscribe { row, fwd, rev ->
        if (fwd == null && rev == null) {
            log.warn "No reads for ${row.customer}/${row.sample} (forward ${row.fwd_front}/${row.fwd_rear}, reverse ${row.rev_front}/${row.rev_rear})"
        }
        else if (fwd == null || rev == null) {
            log.warn "${row.customer}/${row.sample}: only ${fwd == null ? 'reverse' : 'forward'} reads found"
        }
    }

    COLLECT_SAMPLE(
        ch_matched
            .filter { row, fwd, rev -> fwd != null || rev != null }
            .map { row, fwd, rev -> [row, fwd != null ? fwd : [], rev != null ? rev : []] }
    )

    // STAGE 6: QC
    NANOPLOT(COLLECT_SAMPLE.out.reads)

    // Report
    ch_stage_counts = Channel.empty()
        .mix(FWD_DEMUX.out.counts, RC_REV_DEMUX.out.counts, REV_DEMUX.out.counts, RC_FWD_DEMUX.out.counts)
        .collectFile(name: 'stage_counts.tsv', seed: 'stage\tparent\tbarcode\treads\tbases\n', sort: 'deep')

    ch_sample_stats = COLLECT_SAMPLE.out.stats
        .collectFile(
            name: 'sample_stats.tsv',
            seed: 'customer\tsample\tfwd_reads\tfwd_bases\trev_reads\trev_bases\ttotal_reads\ttotal_bases\n',
            sort: 'deep'
        )

    ch_sample_meta = Channel.fromList(samples)
        .map { r -> [r.customer, r.sample, r.fwd_front, r.fwd_rear, r.rev_front, r.rev_rear].join('\t') }
        .collectFile(
            name: 'samples_metadata.tsv',
            seed: 'customer\tsample\tfwd_front\tfwd_rear\trev_front\trev_rear',
            newLine: true,
            sort: 'deep'
        )

    DEMUX_REPORT(
        file("${projectDir}/assets/report/demux_report.qmd", checkIfExists: true),
        ch_stage_counts,
        ch_sample_stats,
        ch_sample_meta
    )

    onComplete:
    log.info(workflow.success
        ? "Done. Results in: ${params.outdir}"
        : "Pipeline failed: ${workflow.errorMessage ?: 'see .nextflow.log'}")
}
