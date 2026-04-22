#!/bin/bash -l
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

START_YEAR=1979
END_YEAR=2025
CHUNK_MONTHS=12
MPI_NP="${PBS_NCPUS:-1}"
TIME_BUDGET_HOURS=42
START_CHUNK=1
END_CHUNK=""
WORK_DIR="/scratch/tm70/${USER}/ww3-era5-wind-batches"
WW3_PRNC_EXE=""

usage() {
  cat <<'EOF'
Usage: ./prepare_era5_wind_batch.sh [-m chunk_months] [-n mpi_ranks] [-t budget_hours] [-s start_chunk] [-e end_chunk] [-w workdir] [-x /path/to/ww3_prnc]

Processes a range of ERA5 chunks in sequence until the time budget is exhausted.
Each chunk is delegated to prepare_era5_wind_chunk.sh and is safe to resume.

Examples:
  ./prepare_era5_wind_batch.sh -m 12 -n 8 -t 42
  ./prepare_era5_wind_batch.sh -m 6 -n 8 -t 42 -s 1 -e 20
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

chunk_id_from_index() {
  local idx="$1"
  local offset year start_month end_month
  offset=$(((idx - 1) * CHUNK_MONTHS))
  year=$((START_YEAR + offset / 12))
  start_month=$((offset % 12 + 1))
  end_month=$((start_month + CHUNK_MONTHS - 1))
  printf '%04d_%04d%02d_%04d%02d' "${idx}" "${year}" "${start_month}" "${year}" "${end_month}"
}

chunk_is_complete() {
  local idx="$1"
  local chunk_id chunk_dir
  chunk_id=$(chunk_id_from_index "${idx}")
  chunk_dir="${WORK_DIR}/${chunk_id}"
  [ -f "${chunk_dir}/chunk.done" ] && [ -f "${chunk_dir}/wind.ww3" ]
}

while getopts ":hm:n:t:s:e:w:x:" opt; do
  case "${opt}" in
    h)
      usage
      exit 0
      ;;
    m)
      CHUNK_MONTHS="${OPTARG}"
      ;;
    n)
      MPI_NP="${OPTARG}"
      ;;
    t)
      TIME_BUDGET_HOURS="${OPTARG}"
      ;;
    s)
      START_CHUNK="${OPTARG}"
      ;;
    e)
      END_CHUNK="${OPTARG}"
      ;;
    w)
      WORK_DIR="${OPTARG}"
      ;;
    x)
      WW3_PRNC_EXE="${OPTARG}"
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

if ! [[ "${MPI_NP}" =~ ^[0-9]+$ ]] || [ "${MPI_NP}" -lt 1 ]; then
  echo "MPI ranks must be a positive integer." >&2
  exit 2
fi

if ! [[ "${TIME_BUDGET_HOURS}" =~ ^[0-9]+$ ]] || [ "${TIME_BUDGET_HOURS}" -lt 1 ]; then
  echo "Time budget hours must be a positive integer." >&2
  exit 2
fi

if ! [[ "${START_CHUNK}" =~ ^[0-9]+$ ]] || [ "${START_CHUNK}" -lt 1 ]; then
  echo "Start chunk must be a positive integer." >&2
  exit 2
fi

TOTAL_CHUNKS=$((((END_YEAR - START_YEAR + 1) * 12) / CHUNK_MONTHS))

if [ -z "${END_CHUNK}" ]; then
  END_CHUNK="${TOTAL_CHUNKS}"
fi

if ! [[ "${END_CHUNK}" =~ ^[0-9]+$ ]] || [ "${END_CHUNK}" -lt 1 ]; then
  echo "End chunk must be a positive integer." >&2
  exit 2
fi

if [ "${START_CHUNK}" -gt "${END_CHUNK}" ]; then
  echo "Start chunk must not be greater than end chunk." >&2
  exit 2
fi

if [ "${END_CHUNK}" -gt "${TOTAL_CHUNKS}" ]; then
  echo "End chunk must be between 1 and ${TOTAL_CHUNKS}." >&2
  exit 2
fi

SECONDS_BUDGET=$((TIME_BUDGET_HOURS * 3600))
JOB_START_TS=$(date +%s)
PROCESSED=0

log "Chunk months=${CHUNK_MONTHS}; total chunks=${TOTAL_CHUNKS}"
log "Chunk range=${START_CHUNK}-${END_CHUNK}; MPI ranks=${MPI_NP}; time budget=${TIME_BUDGET_HOURS} hour(s)"
log "Work directory=${WORK_DIR}"

for idx in $(seq "${START_CHUNK}" "${END_CHUNK}"); do
  if chunk_is_complete "${idx}"; then
    log "Chunk $(chunk_id_from_index "${idx}") already complete, skipping"
    continue
  fi

  NOW_TS=$(date +%s)
  ELAPSED=$((NOW_TS - JOB_START_TS))
  REMAINING=$((SECONDS_BUDGET - ELAPSED))
  if [ "${REMAINING}" -le 0 ]; then
    log "Time budget exhausted before chunk index ${idx}, stopping"
    break
  fi

  log "Starting chunk $(chunk_id_from_index "${idx}") with about $((REMAINING / 3600)) hour(s) remaining in budget"
  "${SCRIPT_DIR}/prepare_era5_wind_chunk.sh" \
    -i "${idx}" \
    -m "${CHUNK_MONTHS}" \
    -n "${MPI_NP}" \
    -w "${WORK_DIR}" \
    -x "${WW3_PRNC_EXE}"
  PROCESSED=$((PROCESSED + 1))
done

NEXT_INCOMPLETE=""
for idx in $(seq 1 "${TOTAL_CHUNKS}"); do
  if ! chunk_is_complete "${idx}"; then
    NEXT_INCOMPLETE="${idx}"
    break
  fi
done

log "Processed ${PROCESSED} new chunk(s) in this submission"
if [ -n "${NEXT_INCOMPLETE}" ]; then
  log "Next incomplete chunk index is ${NEXT_INCOMPLETE}"
else
  log "All ${TOTAL_CHUNKS} chunks are complete"
fi
