#!/bin/bash -l
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUN_DIR="${SCRIPT_DIR}/run"

U_ROOT="/g/data/rt52/era5/single-levels/reanalysis/u10n"
V_ROOT="/g/data/rt52/era5/single-levels/reanalysis/v10n"
NCKS_EXE="/apps/nco/5.0.5/bin/ncks"

START_YEAR=1979
END_YEAR=2025
CHUNK_MONTHS=3
MPI_NP="${PBS_NCPUS:-1}"

CHUNK_INDEX=""
WORK_DIR="/scratch/tm70/${USER}/ww3-era5-wind-chunks"
WW3_PRNC_EXE=""

usage() {
  cat <<'EOF'
Usage: ./prepare_era5_wind_chunk.sh -i chunk_index [-m chunk_months] [-n mpi_ranks] [-w workdir] [-x /path/to/ww3_prnc]

Processes one ERA5 chunk into a WW3 wind chunk.
`chunk_months` must divide 12, so useful values are 1, 2, 3, 4, 6, or 12.
Chunk 1 carries the WW3 file header. Later chunks are headerless and are
meant to be concatenated in order.
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

resolve_prnc_exe() {
  if [ -n "${WW3_PRNC_EXE}" ] && [ -x "${WW3_PRNC_EXE}" ]; then
    return 0
  fi

  for candidate in \
    "${SCRIPT_DIR}/build-gadi/ww3_prnc" \
    "${SCRIPT_DIR}/build-gadi-test3/ww3_prnc" \
    "${SCRIPT_DIR}/build/ww3_prnc"
  do
    if [ -x "${candidate}" ]; then
      WW3_PRNC_EXE="${candidate}"
      return 0
    fi
  done

  echo "ww3_prnc executable not found. Use -x /path/to/ww3_prnc." >&2
  exit 1
}

run_prnc() {
  local workdir="$1"
  if [ "${MPI_NP}" -gt 1 ]; then
    (
      cd "${workdir}"
      mpirun -x LD_LIBRARY_PATH -np "${MPI_NP}" "${WW3_PRNC_EXE}" > ww3_prnc.log 2>&1
    )
  else
    (
      cd "${workdir}"
      "${WW3_PRNC_EXE}" > ww3_prnc.log 2>&1
    )
  fi
}

while getopts ":hi:m:n:w:x:" opt; do
  case "${opt}" in
    h)
      usage
      exit 0
      ;;
    i)
      CHUNK_INDEX="${OPTARG}"
      ;;
    m)
      CHUNK_MONTHS="${OPTARG}"
      ;;
    n)
      MPI_NP="${OPTARG}"
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

if ! [[ "${CHUNK_INDEX}" =~ ^[0-9]+$ ]]; then
  echo "Chunk index must be a positive integer." >&2
  exit 2
fi

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

TOTAL_CHUNKS=$((((END_YEAR - START_YEAR + 1) * 12) / CHUNK_MONTHS))

if [ "${CHUNK_INDEX}" -lt 1 ] || [ "${CHUNK_INDEX}" -gt "${TOTAL_CHUNKS}" ]; then
  echo "Chunk index must be between 1 and ${TOTAL_CHUNKS}." >&2
  exit 2
fi

if [ ! -f "${RUN_DIR}/mod_def.ww3" ]; then
  echo "mod_def.ww3 not found in ${RUN_DIR}" >&2
  exit 1
fi

if [ ! -x "${NCKS_EXE}" ]; then
  echo "Required tool not found: ${NCKS_EXE}" >&2
  exit 1
fi

resolve_prnc_exe
mkdir -p "${WORK_DIR}"

offset=$(((CHUNK_INDEX - 1) * CHUNK_MONTHS))
year=$((START_YEAR + offset / 12))
start_month=$((offset % 12 + 1))
end_month=$((start_month + CHUNK_MONTHS - 1))

chunk_id=$(printf '%04d_%04d%02d_%04d%02d' "${CHUNK_INDEX}" "${year}" "${start_month}" "${year}" "${end_month}")
chunk_dir="${WORK_DIR}/${chunk_id}"
chunk_out="${chunk_dir}/wind.ww3"
chunk_out_tmp="${chunk_out}.part"
chunk_done="${chunk_dir}/chunk.done"

if [ -f "${chunk_done}" ] && [ -f "${chunk_out}" ]; then
  log "Chunk ${chunk_id} already complete, skipping"
  exit 0
fi

mkdir -p "${chunk_dir}"
log "Processing chunk ${chunk_id}"
log "Using ww3_prnc executable ${WW3_PRNC_EXE}"
log "Using ${MPI_NP} MPI rank(s)"

month_index=0
for month in $(seq "${start_month}" "${end_month}"); do
  month_tag=$(printf '%04d%02d' "${year}" "${month}")
  month_dir="${chunk_dir}/${month_tag}"
  month_done="${month_dir}/month.done"
  month_chunk="${month_dir}/wind.ww3"
  month_nc="${month_dir}/wind.nc"
  month_log="${month_dir}/ww3_prnc.log"
  header_flag="F"

  if [ "${CHUNK_INDEX}" -eq 1 ] && [ "${month_index}" -eq 0 ]; then
    header_flag="T"
  fi

  if [ -f "${month_done}" ] && [ -f "${month_chunk}" ]; then
    log "Month ${month_tag} already complete, skipping"
    month_index=$((month_index + 1))
    continue
  fi

  shopt -s nullglob
  u_matches=("${U_ROOT}/${year}/u10n_era5_oper_sfc_${month_tag}"*.nc)
  v_matches=("${V_ROOT}/${year}/v10n_era5_oper_sfc_${month_tag}"*.nc)
  shopt -u nullglob

  if [ "${#u_matches[@]}" -ne 1 ] || [ "${#v_matches[@]}" -ne 1 ]; then
    echo "Expected exactly one ERA5 u10n and v10n file for ${month_tag}." >&2
    exit 1
  fi

  u_file="${u_matches[0]}"
  v_file="${v_matches[0]}"

  mkdir -p "${month_dir}"
  rm -f "${month_done}" "${month_nc}" "${month_chunk}" "${month_log}"
  cp "${u_file}" "${month_nc}"
  "${NCKS_EXE}" -A -v v10n "${v_file}" "${month_nc}"
  ln -sf "${RUN_DIR}/mod_def.ww3" "${month_dir}/mod_def.ww3"

  cat > "${month_dir}/ww3_prnc.inp" <<EOF
$ -------------------------------------------------------------------- $
$ Temporary ww3_prnc input generated by prepare_era5_wind_chunk.sh     $
$ -------------------------------------------------------------------- $
  'WND' 'LL' T ${header_flag}
 longitude latitude
  u10n v10n
  'wind.nc'
$ -------------------------------------------------------------------- $
$ End of input file                                                    $
$ -------------------------------------------------------------------- $
EOF

  run_prnc "${month_dir}"

  rm -f "${month_nc}"
  touch "${month_done}"
  month_index=$((month_index + 1))
  log "Month ${month_tag} finished"
done

rm -f "${chunk_out_tmp}"
month_index=0
for month in $(seq "${start_month}" "${end_month}"); do
  month_tag=$(printf '%04d%02d' "${year}" "${month}")
  month_chunk="${chunk_dir}/${month_tag}/wind.ww3"

  if [ ! -f "${month_chunk}" ]; then
    echo "Missing monthly WW3 chunk: ${month_chunk}" >&2
    exit 1
  fi

  if [ "${month_index}" -eq 0 ]; then
    cp "${month_chunk}" "${chunk_out_tmp}"
  else
    cat "${month_chunk}" >> "${chunk_out_tmp}"
  fi
  month_index=$((month_index + 1))
done

mv "${chunk_out_tmp}" "${chunk_out}"
touch "${chunk_done}"

for month in $(seq "${start_month}" "${end_month}"); do
  month_tag=$(printf '%04d%02d' "${year}" "${month}")
  rm -rf "${chunk_dir:?}/${month_tag}"
done

log "Chunk ${chunk_id} complete"
