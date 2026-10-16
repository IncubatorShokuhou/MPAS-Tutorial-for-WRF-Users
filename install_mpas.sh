#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MPAS_VERSION=8.4.2
IO_PREFIX="$ROOT_DIR/local/io-stack"
MPAS_SOURCE="$ROOT_DIR/MPAS-Model"
MPAS_PREFIX="$ROOT_DIR/local/mpas-$MPAS_VERSION"
DOWNLOAD_DIR="$ROOT_DIR/downloads"
BUILD_DIR="$ROOT_DIR/build"
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)
CC_CMD=gcc; CXX_CMD=g++; FC_CMD=gfortran
INTERACTIVE=auto; RUN_TESTS=false; INSTALL_WPS=false

usage() {
    cat <<'EOF'
Usage: ./install_mpas.sh [options]

Build the complete MPI/HDF5/netCDF/PnetCDF/PIO stack, then MPAS-A with PIO.
With no arguments in a terminal, prompts are shown; Enter accepts local defaults.

  --io-prefix DIR       common dependency-stack prefix
  --mpas-source DIR     MPAS source checkout
  --mpas-prefix DIR     MPAS installation prefix
  --download-dir DIR    source archive cache
  --build-dir DIR       build workspace
  --cc/--cxx/--fc PATH  GNU compiler commands or absolute paths
  -j, --jobs N          parallel jobs (default: all logical CPUs)
  --run-tests           run dependency test suites
  --with-wps            also build WPS ungrib and its GRIB2 libraries
  -y, --non-interactive accept defaults without prompting
  -h, --help            show this help

Individual installers: install_io_stack.sh and install_wps.sh
EOF
}

had_args=$#
while (($#)); do
    case "$1" in
        --io-prefix) IO_PREFIX=$2; shift 2 ;;
        --mpas-source) MPAS_SOURCE=$2; shift 2 ;;
        --mpas-prefix) MPAS_PREFIX=$2; shift 2 ;;
        --download-dir) DOWNLOAD_DIR=$2; shift 2 ;;
        --build-dir) BUILD_DIR=$2; shift 2 ;;
        --cc) CC_CMD=$2; shift 2 ;;
        --cxx) CXX_CMD=$2; shift 2 ;;
        --fc) FC_CMD=$2; shift 2 ;;
        -j|--jobs) JOBS=$2; shift 2 ;;
        --run-tests) RUN_TESTS=true; shift ;;
        --with-wps) INSTALL_WPS=true; shift ;;
        -y|--non-interactive) INTERACTIVE=false; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done
if [[ $INTERACTIVE == auto ]]; then
    if ((had_args == 0)) && [[ -t 0 ]]; then INTERACTIVE=true; else INTERACTIVE=false; fi
fi
prompt() { local label=$1 current=$2 answer; read -r -p "$label [$current]: " answer; printf '%s' "${answer:-$current}"; }
if [[ $INTERACTIVE == true ]]; then
    CC_CMD=$(prompt "GCC command/path" "$CC_CMD")
    CXX_CMD=$(prompt "G++ command/path" "$CXX_CMD")
    FC_CMD=$(prompt "GFortran command/path" "$FC_CMD")
    IO_PREFIX=$(prompt "I/O stack prefix" "$IO_PREFIX")
    MPAS_SOURCE=$(prompt "MPAS source directory" "$MPAS_SOURCE")
    MPAS_PREFIX=$(prompt "MPAS install prefix" "$MPAS_PREFIX")
    DOWNLOAD_DIR=$(prompt "Download cache" "$DOWNLOAD_DIR")
    BUILD_DIR=$(prompt "Build directory" "$BUILD_DIR")
    JOBS=$(prompt "Parallel jobs" "$JOBS")
fi
case "$JOBS" in ''|*[!0-9]*) echo "--jobs must be a positive integer" >&2; exit 2 ;; esac
((JOBS > 0)) || { echo "--jobs must be greater than zero" >&2; exit 2; }
for tool in cmake git; do command -v "$tool" >/dev/null || { echo "Required tool not found: $tool" >&2; exit 1; }; done

io_args=(-y --prefix "$IO_PREFIX" --download-dir "$DOWNLOAD_DIR" --build-dir "$BUILD_DIR/io-stack"
         --cc "$CC_CMD" --cxx "$CXX_CMD" --fc "$FC_CMD" --jobs "$JOBS")
[[ $RUN_TESTS == false ]] || io_args+=(--run-tests)
"$ROOT_DIR/install_io_stack.sh" "${io_args[@]}"

export PATH="$IO_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$IO_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CMAKE_PREFIX_PATH="$IO_PREFIX${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export NETCDF="$IO_PREFIX" PNETCDF="$IO_PREFIX" PIO="$IO_PREFIX"
[[ $(command -v mpifort) == "$IO_PREFIX/bin/mpifort" ]] || {
    echo "Refusing to build with a non-project MPI: $(command -v mpifort)" >&2; exit 1;
}

if [[ ! -d $MPAS_SOURCE/.git ]]; then
    git clone --branch "v$MPAS_VERSION" --depth 1 https://github.com/MPAS-Dev/MPAS-Model.git "$MPAS_SOURCE"
fi
actual_tag=$(git -C "$MPAS_SOURCE" describe --tags --exact-match 2>/dev/null || true)
[[ $actual_tag == "v$MPAS_VERSION" ]] || {
    echo "$MPAS_SOURCE is not MPAS v$MPAS_VERSION (found: ${actual_tag:-untagged})." >&2; exit 1;
}

mpas_build="$BUILD_DIR/mpas-$MPAS_VERSION-cmake-pio"
if [[ -x $MPAS_PREFIX/bin/mpas_atmosphere && -x $MPAS_PREFIX/bin/mpas_init_atmosphere ]]; then
    echo "MPAS v$MPAS_VERSION is already installed at $MPAS_PREFIX"
else
    cmake -S "$MPAS_SOURCE" -B "$mpas_build" \
            -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$MPAS_PREFIX" \
            -DCMAKE_C_COMPILER="$IO_PREFIX/bin/mpicc" \
            -DCMAKE_Fortran_COMPILER="$IO_PREFIX/bin/mpifort" \
            -DCMAKE_PREFIX_PATH="$IO_PREFIX" -DPnetCDF_ROOT="$IO_PREFIX" \
            -DPIO_ROOT="$IO_PREFIX" -DNetCDF_ROOT="$IO_PREFIX" \
            -DMPAS_CORES="atmosphere;init_atmosphere" \
            -DMPAS_USE_PIO=ON -DMPAS_OPENMP=OFF
    cmake --build "$mpas_build" --parallel "$JOBS"
    cmake --install "$mpas_build"
fi
test -x "$MPAS_PREFIX/bin/mpas_atmosphere"
test -x "$MPAS_PREFIX/bin/mpas_init_atmosphere"
"$IO_PREFIX/bin/mpirun" -n 2 "$IO_PREFIX/bin/ompi_info" --version >/dev/null

if [[ $INSTALL_WPS == true ]]; then
    "$ROOT_DIR/install_wps.sh" -y --jobs "$JOBS" \
        --mpi-prefix "$IO_PREFIX" --netcdf-prefix "$IO_PREFIX" \
        --download-dir "$DOWNLOAD_DIR" --build-dir "$BUILD_DIR/wps"
fi

cat <<EOF

Installation complete.
I/O stack:    $IO_PREFIX
MPAS source:  $MPAS_SOURCE
MPAS install: $MPAS_PREFIX

Environment:
  export PATH="$IO_PREFIX/bin:$MPAS_PREFIX/bin:\$PATH"
  export LD_LIBRARY_PATH="$IO_PREFIX/lib:\${LD_LIBRARY_PATH:-}"
EOF
