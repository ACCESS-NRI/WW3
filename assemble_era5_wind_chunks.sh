#!/bin/bash -l
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUN_DIR="${SCRIPT_DIR}/run"

START_YEAR=1979
END_YEAR=2025
CHUNK_MONTHS=3

WORK_DIR="/scratch/tm70/${USER}/ww3-era5-wind-chunks"
OUT_WW3="${RUN_DIR}/wind.ww3"

usage() {
  cat <<'EOF'
Usage: ./assemble_era5_wind_chunks.sh [-m chunk_months] [-w workdir]

Concatenates completed WW3 wind chunks into run/wind.ww3.
The first chunk must include the WW3 header; later chunks must be headerless.
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

while getopts ":hm:w:" opt; do
  case "${opt}" in
    h)
      usage
      exit 0
      ;;
    m)
      CHUNK_MONTHS="${OPTARG}"
      ;;
    w)
      WORK_DIR="${OPTARG}"
      ;;
    :)
      echo "Missing argument for -${OPTARG}" >&2
      usage >&2
      exit 2
      ;;
    \?)
      echo "Unknown option: -${OPTARG}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "${CHUNK_MONTHS}" =~ ^[0-9]+$ ]] || [ "${CHUNK_MONTHS}" -lt 1 ]; then
  echo "Chunk months must be a positive integer." >&2
  exit 2
fi

if [ $((12 % CHUNK_MONTHS)) -ne 0 ]; then
  echo "Chunk months must divide 12." >&2
  exit 2
fi

TOTAL_CHUNKS=$((((END_YEAR - START_YEAR + 1) * 12) / CHUNK_MONTHS))

tmp_out="${OUT_WW3}.part"
rm -f "${tmp_out}"

for idx in $(seq 1 "${TOTAL_CHUNKS}"); do
  offset=$(((idx - 1) * CHUNK_MONTHS))
  year=$((START_YEAR + offset / 12))
  start_month=$((offset % 12 + 1))
  end_month=$((start_month + CHUNK_MONTHS - 1))
  chunk_id=$(printf '%04d_%04d%02d_%04d%02d' "${idx}" "${year}" "${start_month}" "${year}" "${end_month}")
  chunk_file="${WORK_DIR}/${chunk_id}/wind.ww3"

  if [ ! -f "${chunk_file}" ]; then
    echo "Missing chunk file: ${chunk_file}" >&2
    exit 1
  fi

  if [ "${idx}" -eq 1 ]; then
    cp "${chunk_file}" "${tmp_out}"
  else
    cat "${chunk_file}" >> "${tmp_out}"
  fi

  log "Appended chunk ${chunk_id}"
done

mv "${tmp_out}" "${OUT_WW3}"
log "Built ${OUT_WW3}"
