#!/bin/bash -l
#PBS -P tm70
#PBS -N ww3_era5_asm
#PBS -q normal
#PBS -l walltime=12:00:00
#PBS -l ncpus=1
#PBS -l mem=8GB
#PBS -l jobfs=2GB
#PBS -l storage=gdata/tm70+scratch/tm70
#PBS -l wd

set -euo pipefail

WW3_DIR="/g/data/tm70/ek4684/WW3"
CHUNK_MONTHS="${CHUNK_MONTHS:-12}"
WORK_DIR="${WORK_DIR:-/scratch/tm70/${USER}/ww3-era5-wind-${CHUNK_MONTHS}m}"
LOG_DIR="${LOG_DIR:-${WW3_DIR}/logs/era5_wind_batches}"

mkdir -p "${LOG_DIR}"
exec > "${LOG_DIR}/assemble_${CHUNK_MONTHS}m.log" 2>&1

echo "Chunk months=${CHUNK_MONTHS}"
echo "Work directory=${WORK_DIR}"

cd "${WW3_DIR}"
./assemble_era5_wind_chunks.sh -m "${CHUNK_MONTHS}" -w "${WORK_DIR}"
