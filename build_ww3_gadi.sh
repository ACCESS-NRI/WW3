#!/bin/bash -l
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build_ww3_gadi.sh [-b build_dir] [-s switch_file] [-j jobs] [-t build_type] [-i]

Build WW3 on Gadi using the CMake build.

Options:
  -b build_dir    Build directory. Default: <repo>/build-gadi
  -s switch_file  WW3 switch file. Default: <repo>/model/bin/switch_ACCESSOM3
  -j jobs         Parallel build jobs. Default: 8
  -t build_type   CMake build type. Default: Release
  -i              Run 'cmake --install' after a successful build
  -h              Show this help

Environment overrides:
  BUILD_DIR
  SWITCH_FILE
  BUILD_JOBS
  CMAKE_BUILD_TYPE
  INSTALL_DIR
  SPACK_NETCDF_BASE
EOF
}

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_dir="${BUILD_DIR:-${repo_dir}/build-gadi}"
switch_file="${SWITCH_FILE:-${repo_dir}/model/bin/switch_ACCESSOM3}"
install_dir="${INSTALL_DIR:-${build_dir}/install}"
jobs="${BUILD_JOBS:-8}"
build_type="${CMAKE_BUILD_TYPE:-Release}"
do_install=0

while getopts ":b:s:j:t:ih" opt; do
  case "${opt}" in
    b) build_dir="${OPTARG}" ;;
    s) switch_file="${OPTARG}" ;;
    j) jobs="${OPTARG}" ;;
    t) build_type="${OPTARG}" ;;
    i) do_install=1 ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "error: option -${OPTARG} requires an argument" >&2
      usage >&2
      exit 1
      ;;
    \?)
      echo "error: invalid option -${OPTARG}" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ ! -f "${switch_file}" ]; then
  echo "error: switch file not found: ${switch_file}" >&2
  exit 1
fi

if ! command -v module >/dev/null 2>&1; then
  echo "error: the 'module' command is not available in this shell" >&2
  exit 1
fi

resolve_spack_netcdf() {
  local base="${SPACK_NETCDF_BASE:-/g/data/vk83/apps/spack/0.22/release/linux-rocky8-x86_64_v4/intel-2021.10.0}"
  local dir
  local c_lib

  shopt -s nullglob
  for dir in "${base}"/netcdf-fortran-*; do
    if [ ! -f "${dir}/lib/libnetcdff.so" ]; then
      continue
    fi

    c_lib="$(ldd "${dir}/lib/libnetcdff.so" | awk '/libnetcdf\.so/{print $3; exit}')"
    if [ -n "${c_lib}" ] && [ -f "${c_lib}" ]; then
      NETCDF_FORTRAN_ROOT="${dir}"
      NETCDF_FORTRAN_LIBRARY="${dir}/lib/libnetcdff.so"
      NETCDF_C_LIBRARY="${c_lib}"
      NETCDF_C_ROOT="$(cd "$(dirname "${c_lib}")/.." && pwd)"
      export NETCDF_FORTRAN_ROOT NETCDF_FORTRAN_LIBRARY NETCDF_C_ROOT NETCDF_C_LIBRARY
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob

  echo "error: could not resolve a working Spack NetCDF C/Fortran pair under ${base}" >&2
  exit 1
}

module purge >/dev/null 2>&1
module load intel-compiler/2021.10.0 openmpi/4.1.7

export CC=mpicc
export FC=mpif90
export CXX=mpicxx

resolve_spack_netcdf

mkdir -p "${build_dir}"

if [ -f "${build_dir}/Makefile" ]; then
  cmake --build "${build_dir}" --target clean
fi

cmake -S "${repo_dir}" -B "${build_dir}" \
  -DCMAKE_BUILD_TYPE="${build_type}" \
  -DCMAKE_INSTALL_PREFIX="${install_dir}" \
  -DSWITCH="${switch_file}" \
  -DNetCDF_C_LIBRARY="${NETCDF_C_LIBRARY}" \
  -DNetCDF_C_INCLUDE_FILE="${NETCDF_C_ROOT}/include/netcdf.h" \
  -DNetCDF_Fortran_LIBRARY="${NETCDF_FORTRAN_LIBRARY}" \
  -DNetCDF_Fortran_INCLUDE_FILE="${NETCDF_FORTRAN_ROOT}/include/netcdf.mod" \
  -DNetCDF_C_CONFIG_EXECUTABLE="${NETCDF_C_ROOT}/bin/nc-config" \
  -DNetCDF_Fortran_CONFIG_EXECUTABLE="${NETCDF_FORTRAN_ROOT}/bin/nf-config" \
  -DWW3_ACCESS3=OFF \
  -DWW3_OPENMP=OFF

targets=(
  ww3_grid
  ww3_strt
  ww3_outf
  ww3_ounf
  ww3_ounp
  ww3_prnc
  ww3_shel
)

cmake --build "${build_dir}" --parallel "${jobs}" --target "${targets[@]}"

if [ "${do_install}" -eq 1 ]; then
  cmake --install "${build_dir}"
fi

echo "Built WW3 targets in ${build_dir}:"
for target in "${targets[@]}"; do
  echo "  ${build_dir}/${target}"
done
