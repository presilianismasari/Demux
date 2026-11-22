/*
 * Helper functions: barcode name normalisation and sample sheet parsing.
 */

// "barcode1", "barcode01", "barcode01-rcREV" -> "barcode01"; anything else is returned unchanged
def normBarcode(String name) {
    def m = (name =~ /(?i)barcode0*(\d+)/)
    return m.find() ? String.format('barcode%02d', m.group(1) as int) : name
}

// dorado outputs <barcode>.fastq.gz (single Path or list of Paths) -> [[barcode, file], ...]
def perBarcode(files) {
    return [files].flatten().collect { f -> [normBarcode(f.name.replaceFirst(/\.fastq(\.gz)?$/, '')), f] }
}

def simplify(String h) {
    return h.toLowerCase().replaceAll(/[^a-z0-9]/, '')
}

def clean(String s) {
    return s.trim().replaceAll(/[^A-Za-z0-9._-]+/, '_')
}

def barcode(String value, String col, int lineNo) {
    if (!(value =~ /(?i)barcode\d+/)) {
        throw new IllegalArgumentException("Metadata line ${lineNo}: '${value}' in ${col} is not a barcodeNN value")
    }
    return normBarcode(value.trim())
}

def dupes(List rows, Closure key) {
    return rows.groupBy(key).findAll { k, v -> v.size() > 1 }.keySet()
}

/*
 * Parse the tab-separated sample sheet. Header names are matched case/punctuation-insensitively:
 *   customer   : Nama Customer | Customer | Cust name
 *   sample     : Sample
 *   fwd_front  : Forward-front   (e.g. barcode01-rcREV; the leading barcodeNN is used)
 *   fwd_rear   : Forward-rear
 *   rev_front  : Reverse-front   (e.g. barcode01-rcFWD)
 *   rev_rear   : Reverse-rear
 * Returns a list of maps with sanitised customer/sample names and normalised barcodes.
 */
def parseMetadata(metadata) {
    def aliases = [
        customer : ['namacustomer', 'customer', 'customername', 'custname', 'cust'],
        sample   : ['sample', 'sampleid', 'samplename'],
        fwd_front: ['forwardfront'],
        fwd_rear : ['forwardrear'],
        rev_front: ['reversefront'],
        rev_rear : ['reverserear'],
    ]
    def lines = metadata.readLines()
        .collect { it.replace('\r', '').replace('\uFEFF', '') }
        .findAll { it.trim() && !it.trim().startsWith('#') }
    if (lines.size() < 2) {
        throw new IllegalArgumentException("Metadata ${metadata} needs a header and at least one sample")
    }

    def header = lines[0].split('\t', -1).collect { it.trim() }
    def idx = [:]
    aliases.each { key, names ->
        def i = header.findIndexOf { h -> simplify(h) in names }
        if (i < 0) {
            throw new IllegalArgumentException("Metadata is missing a '${key}' column (accepted: ${names.join(', ')}). Header: ${header}")
        }
        idx[key] = i
    }

    def rows = []
    lines.drop(1).eachWithIndex { line, n ->
        def lineNo = n + 2
        def cells = line.split('\t', -1).collect { it.trim() }
        if (cells.size() < header.size()) {
            throw new IllegalArgumentException("Metadata line ${lineNo}: expected ${header.size()} tab-separated columns, found ${cells.size()}")
        }
        def row = [
            customer : clean(cells[idx.customer]),
            sample   : clean(cells[idx.sample]),
            fwd_front: barcode(cells[idx.fwd_front], 'Forward-front', lineNo),
            fwd_rear : barcode(cells[idx.fwd_rear],  'Forward-rear',  lineNo),
            rev_front: barcode(cells[idx.rev_front], 'Reverse-front', lineNo),
            rev_rear : barcode(cells[idx.rev_rear],  'Reverse-rear',  lineNo),
        ]
        if (!row.customer || !row.sample) {
            throw new IllegalArgumentException("Metadata line ${lineNo}: customer and sample must not be empty")
        }
        rows << row
    }

    def dupSamples = dupes(rows) { r -> "${r.customer}/${r.sample}" }
    if (dupSamples) {
        throw new IllegalArgumentException("Duplicate customer/sample in metadata: ${dupSamples}")
    }
    def dupFwd = dupes(rows) { r -> "${r.fwd_front}|${r.fwd_rear}" }
    if (dupFwd) {
        throw new IllegalArgumentException("Forward barcode combination used by more than one sample: ${dupFwd}")
    }
    def dupRev = dupes(rows) { r -> "${r.rev_front}|${r.rev_rear}" }
    if (dupRev) {
        throw new IllegalArgumentException("Reverse barcode combination used by more than one sample: ${dupRev}")
    }
    return rows
}
