#!/bin/bash -l
#PBS -P tm70
#PBS -N ww3_era5_batch
#PBS -q normal
#PBS -l walltime=48:00:00
#PBS -l ncpus=8
#PBS -l mem=32GB
#PBS -l jobfs=5GB
#PBS -l storage=gdata/tm70+gdata/rt52+scratch/tm70+gdata/vk83
#PBS -l wd

set -euo pipefail

module purge
module load intel-compiler/2021.10.0
module load openmpi/4.1.7

WW3_DIR="/g/data/tm70/ek4684/WW3"
CHUNK_MONTHS="${CHUNK_MONTHS:-12}"
MPI_NP="${MPI_NP:-${PBS_NCPUS:-8}}"
TIME_BUDGET_HOURS="${TIME_BUDGET_HOURS:-42}"
START_CHUNK="${START_CHUNK:-1}"
END_CHUNK="${END_CHUNK:-}"
WORK_DIR="${WORK_DIR:-/scratch/tm70/${USER}/ww3-era5-wind-${CHUNK_MONTHS}m}"
WW3_PRNC_EXE="${WW3_PRNC_EXE:-${WW3_DIR}/build-gadi-test3/ww3_prnc}"
LOG_DIR="${LOG_DIR:-${WW3_DIR}/logs/era5_wind_batches}"

resolve_spack_netcdf_runtime() {
  local base="${SPACK_NETCDF_BASE:-/g/data/vk83/apps/spack/0.22/release/linux-rocky8-x86_64_v4/intel-2021.10.0}"
  local dir
  local c_lib
  local c_lib_dir

  shopt -s nullglob
  for dir in "${base}"/netcdf-fortran-*; do
    if [ ! -f "${dir}/lib/libnetcdff.so" ]; then
      continue
    fi

    c_lib="$(ldd "${dir}/lib/libnetcdff.so" | awk '/libnetcdf\.so/{print $3; exit}')"
    if [ -n "${c_lib}" ] && [ -f "${c_lib}" ]; then
      c_lib_dir="$(dirname "${c_lib}")"
      export LD_LIBRARY_PATH="${dir}/lib:${c_lib_dir}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob

  echo "Failed to resolve NetCDF runtime libraries under ${base}" >&2
  exit 1
}

resolve_spack_netcdf_runtime

mkdir -p "${LOG_DIR}"
job_log="${LOG_DIR}/batch_${PBS_JOBID:-manual}_${CHUNK_MONTHS}m.log"
exec > "${job_log}" 2>&1

echo "PBS_JOBID=${PBS_JOBID:-unset}"
echo "Chunk months=${CHUNK_MONTHS}"
echo "MPI ranks=${MPI_NP}"
echo "Time budget hours=${TIME_BUDGET_HOURS}"
echo "Chunk range=${START_CHUNK}-${END_CHUNK:-auto}"
echo "Work directory=${WORK_DIR}"
echo "ww3_prnc executable=${WW3_PRNC_EXE}"
echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-unset}"
echo "Log file=${job_log}"

cd "${WW3_DIR}"

cmd=(
  ./prepare_era5_wind_batch.sh
  -m "${CHUNK_MONTHS}"
  -n "${MPI_NP}"
  -t "${TIME_BUDGET_HOURS}"
  -s "${START_CHUNK}"
  -w "${WORK_DIR}"
  -x "${WW3_PRNC_EXE}"
)

if [ -n "${END_CHUNK}" ]; then
  cmd+=(-e "${END_CHUNK}")
fi

"${cmd[@]}"
