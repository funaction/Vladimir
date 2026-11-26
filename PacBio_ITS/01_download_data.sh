#!/usr/bin/env bash
## Download PacBio HiFi reads of the selected FunAqua samples from ENA
## The reads on ENA are demultiplexed (one FASTQ.GZ file per sample) and still contain the primers
## Files are saved as data/<RunID>/<RunID>__<SampleID>.fastq.gz

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/00_config.sh"

## Create the sample list, unless it already exists
## The list in the repository fixes the set of samples used in the example
if [[ ! -s "$SAMPLES" ]]; then
  echo "Querying ENA for the samples of project ${ENA_PROJECT}"

  FIELDS="run_accession,library_name,read_count,fastq_ftp,fastq_md5"
  URL="https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${ENA_PROJECT}&result=read_run&fields=${FIELDS}&format=tsv&limit=0"
  TMP="$(mktemp)"
  curl -sSf "$URL" -o "$TMP"

  ## Keep samples of the selected runs with at least MIN_READS reads,
  ## and the MAX_SAMPLES samples with the most reads per run
  {
    echo -e "run\tlibrary_name\trun_accession\tread_count\tfastq_ftp\tfastq_md5"
    for RUN in $RUNS; do
      awk -F'\t' -v run="$RUN" -v minr="$MIN_READS" '
        NR > 1 && index($2, run "__") == 1 && $3 >= minr {
          print run "\t" $2 "\t" $1 "\t" $3 "\t" $4 "\t" $5 }' "$TMP" \
      | sort -t$'\t' -k4,4nr -k2,2 \
      | head -n "$MAX_SAMPLES"
    done
  } > "$SAMPLES"
  rm "$TMP"
fi

echo "Number of samples per run:"
awk -F'\t' 'NR > 1 { n[$1]++ } END { for (r in n) print "  " r ": " n[r] }' "$SAMPLES"

## Download and check MD5 sums
awk -F'\t' 'NR > 1 { print $1 "\t" $2 "\t" $5 "\t" $6 }' "$SAMPLES" \
| while IFS=$'\t' read -r RUN LIB FTP MD5; do
    mkdir -p "${DATA_DIR}/${RUN}"
    FILE="${DATA_DIR}/${RUN}/${LIB}.fastq.gz"
    if [[ -s "$FILE" ]] && echo "${MD5}  ${FILE}" | md5sum -c --status; then
      continue
    fi
    echo "Downloading ${LIB}"
    curl -sSf --retry 5 --retry-delay 10 -o "$FILE" "https://${FTP}"
    echo "${MD5}  ${FILE}" | md5sum -c --quiet
  done

echo "Done. Files are in ${DATA_DIR}"
