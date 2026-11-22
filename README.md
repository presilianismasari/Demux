# Demux

Nextflow pipeline for custom dorado demultiplexing of PacBio 16S barcoded primers sequenced on ONT.
Design notes and diagram: [Custom Demux Pipeline for PacBio16S.md](<Custom Demux Pipeline for PacBio16S.md>).

## Stages

| Stage | Process | Input | dorado config (`assets/dorado/`) |
|---|---|---|---|
| 1 | `FWD_DEMUX` | all input fastq(.gz) | `PacBio_16S_forward.toml`, `barcodes_forward.fasta` |
| 2 | `RC_REV_DEMUX` | each stage 1 barcode | `PacBio_16S_rc-reverse.toml`, `barcodes_rc-reverse.fasta` |
| 3 | `REV_DEMUX` | stage 1 unclassified | `PacBio_16S_reverse.toml`, `barcodes_reverse.fasta` |
| 4 | `RC_FWD_DEMUX` | each stage 3 barcode | `PacBio_16S_rc-forward.toml`, `barcodes_rc-forward.fasta` |
| 5 | `COLLECT_SAMPLE` | metadata lookup of stage 2 + 4 output | |
| 6 | `NANOPLOT` | one fastq.gz per sample | |
| | `DEMUX_REPORT` | counts of every stage and sample | |

dorado nests its output as `<experiment|no_sample>/<run_id>/fastq_pass/barcodeNN/`. Each stage flattens this
into `barcodeNN.fastq.gz` (same-named folders from several run ids are merged), so no path is hardcoded.

## Usage

Before running the pipeline, create and activate the Conda environment from [`demuxPBOR.yml`](<demuxPBOR.yml>):

```bash
conda env create -f demuxPBOR.yml
conda activate demuxPBOR
```

Activation of this environment is required before running Nextflow; running it outside `demuxPBOR` may not provide all required tools.

```bash
chmod +x bin/*.sh   # once; Nextflow needs bin/ scripts to be executable

# --input: fastq/fastq.gz glob or a directory (searched recursively)
nextflow run main.nf \
  --input 'fastq_pass/*.fastq.gz' \
  --metadata metadata.tsv \
  --outdir results
```

Tools are not containerised: `dorado` is run from `params.dorado_bin_dir` (prepended to `PATH`), and
`NanoPlot` / `quarto` (with R, tidyverse and knitr) from the conda envs `params.nanoplot_env` /
`params.quarto_env` (env paths). Override any of them on the command line, e.g.
`--dorado_bin_dir /path/to/dorado/bin --quarto_env /path/to/env`. `conda` must be on `PATH`.
Useful options: `--save_intermediate` (publish every stage's flattened output), `--dorado_args '...'`, `-resume`.

### Metadata

Tab-separated, one row per sample. `Nama Customer` is also accepted as `Customer` / `Cust name`.
Barcode columns use the folder names of your manual run; only the `barcodeNN` part is used.

```
Nama Customer	Sample	Forward-front	Forward-rear	Reverse-front	Reverse-rear
Cust_01	A-1	barcode01-rcREV	barcode01	barcode01-rcFWD	barcode01
Cust_01	A-2	barcode01-rcREV	barcode02	barcode02-rcFWD	barcode01
```

- Forward reads: `RC_REV_DEMUX/<Forward-front>/<Forward-rear>`
- Reverse reads: `RC_FWD_DEMUX/<Reverse-front>/<Reverse-rear>`

Duplicate customer/sample names or barcode combinations stop the pipeline. Samples with no reads only produce a warning.

## Output

```
results/
  demux/<customer>/<sample>/<sample>.fastq.gz   forward + reverse reads concatenated
  NanoPlot/<customer>/<sample>/                 NanoPlot results
  report/demux.html                             demux statistics
  logs/<process>/*.log                          dorado logs
  pipeline_info/                                Nextflow timeline, report and trace
```

Reverse-strand reads are concatenated as they are (not reverse-complemented).

## Tests

```bash
nf-test test    # dorado, NanoPlot and quarto are stubbed; checks channel wiring and metadata validation
```

CI (`.github/workflows/ci.yml`) runs `shellcheck`, `nextflow lint` and `nf-test`.