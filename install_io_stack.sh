#!/usr/bin/env bash
set -euo pipefail

# Build the complete MPAS I/O stack without using a system MPI.
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OPENMPI_VERSION=4.1.8
ZLIB_VERSION=1.3.1
HDF5_VERSION=1.14.6
NETCDF_C_VERSION=4.9.3
NETCDF_FORTRAN_VERSION=4.6.2
PNETCDF_VERSION=1.15.0
PIO_VERSION=2.6.6

PREFIX="$ROOT_DIR/local/io-stack"
DOWNLOAD_DIR="$ROOT_DIR/downloads"
BUILD_DIR="$ROOT_DIR/build/io-stack"
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)
CC_CMD=gcc
CXX_CMD=g++
FC_CMD=gfortran
INTERACTIVE=auto
RUN_TESTS=false
DRY_RUN=false

usage() {
    cat <<'EOF'
Usage: ./install_io_stack.sh [options]

Builds OpenMPI, zlib, parallel HDF5, netCDF-C, netCDF-Fortran,
Parallel-NetCDF, and ParallelIO (PIO) from source.

  --prefix DIR           common install prefix (default: ./local/io-stack)
  --download-dir DIR     archive cache (default: ./downloads)
  --build-dir DIR        source/build workspace (default: ./build/io-stack)
  --cc PATH              GCC command or path (default: gcc)
  --cxx PATH             G++ command or path (default: g++)
  --fc PATH              GFortran command or path (default: gfortran)
  -j, --jobs N           parallel jobs (default: all detected logical CPUs)
  --run-tests            run library test targets (can take a long time)
  --dry-run              print configuration and exit without downloading/building
  -y, --non-interactive  do not prompt; accept defaults/arguments
  -h, --help             show this help
EOF
}

had_args=$#
while (($#)); do
    case "$1" in
        --prefix) PREFIX=$2; shift 2 ;;
        --download-dir) DOWNLOAD_DIR=$2; shift 2 ;;
        --build-dir) BUILD_DIR=$2; shift 2 ;;
        --cc) CC_CMD=$2; shift 2 ;;
        --cxx) CXX_CMD=$2; shift 2 ;;
        --fc) FC_CMD=$2; shift 2 ;;
        -j|--jobs) JOBS=$2; shift 2 ;;
        --run-tests) RUN_TESTS=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -y|--non-interactive) INTERACTIVE=false; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ $INTERACTIVE == auto ]]; then
    if ((had_args == 0)) && [[ -t 0 ]]; then INTERACTIVE=true; else INTERACTIVE=false; fi
fi

prompt() {
    local label=$1 current=$2 answer
    read -r -p "$label [$current]: " answer
    printf '%s' "${answer:-$current}"
}

if [[ $INTERACTIVE == true ]]; then
    PREFIX=$(prompt "Install prefix" "$PREFIX")
    DOWNLOAD_DIR=$(prompt "Download cache" "$DOWNLOAD_DIR")
    BUILD_DIR=$(prompt "Build directory" "$BUILD_DIR")
    CC_CMD=$(prompt "GCC command/path" "$CC_CMD")
    CXX_CMD=$(prompt "G++ command/path" "$CXX_CMD")
    FC_CMD=$(prompt "GFortran command/path" "$FC_CMD")
    JOBS=$(prompt "Parallel jobs" "$JOBS")
fi

resolve_command() {
    command -v "$1" 2>/dev/null || { echo "Required command not found: $1" >&2; exit 1; }
}

CC=$(resolve_command "$CC_CMD")
CXX=$(resolve_command "$CXX_CMD")
FC=$(resolve_command "$FC_CMD")
case "$JOBS" in ''|*[!0-9]*) echo "--jobs must be a positive integer" >&2; exit 2 ;; esac
((JOBS > 0)) || { echo "--jobs must be greater than zero" >&2; exit 2; }

cat <<EOF
MPAS I/O stack configuration
  prefix:    $PREFIX
  downloads: $DOWNLOAD_DIR
  builds:    $BUILD_DIR
  compilers: $CC, $CXX, $FC
  jobs:      $JOBS
EOF
[[ $DRY_RUN == false ]] || exit 0

for tool in curl tar cmake make; do resolve_command "$tool" >/dev/null; done
mkdir -p "$PREFIX" "$DOWNLOAD_DIR" "$BUILD_DIR"

download() {
    local url=$1 archive=$2
    if [[ ! -s $archive ]]; then
        echo "Downloading $url"
        curl -fL --retry 3 --retry-delay 2 -o "$archive.part" "$url"
        mv "$archive.part" "$archive"
    fi
}

extract() {
    local archive=$1 source_dir=$2
    if [[ ! -d $source_dir ]]; then
        mkdir -p "$source_dir"
        tar -xf "$archive" -C "$source_dir" --strip-components=1
    fi
}

cmake_build() {
    local source_dir=$1 build_dir=$2 stamp=$3
    shift 3
    [[ -e $stamp ]] && { echo "Already installed: $stamp"; return; }
    cmake -S "$source_dir" -B "$build_dir" "$@"
    cmake --build "$build_dir" --parallel "$JOBS"
    if [[ $RUN_TESTS == true ]]; then ctest --test-dir "$build_dir" --parallel "$JOBS" --output-on-failure; fi
    cmake --install "$build_dir"
}

# OpenMPI must precede every parallel I/O library. OpenMPI upstream uses Autotools.
mpi_archive="$DOWNLOAD_DIR/openmpi-$OPENMPI_VERSION.tar.gz"
mpi_source="$BUILD_DIR/src/openmpi-$OPENMPI_VERSION"
download "https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-$OPENMPI_VERSION.tar.gz" "$mpi_archive"
extract "$mpi_archive" "$mpi_source"
if [[ ! -x $PREFIX/bin/mpifort ]]; then
    mkdir -p "$BUILD_DIR/openmpi"
    (
        cd "$BUILD_DIR/openmpi"
        "$mpi_source/configure" --prefix="$PREFIX" CC="$CC" CXX="$CXX" FC="$FC" \
            --enable-mpi-fortran --disable-mpi-java
        make -j"$JOBS"
        [[ $RUN_TESTS == false ]] || make -j"$JOBS" check
        make install
    )
fi

export PATH="$PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CMAKE_PREFIX_PATH="$PREFIX${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
MPICC="$PREFIX/bin/mpicc"
MPICXX="$PREFIX/bin/mpicxx"
MPIFC="$PREFIX/bin/mpifort"
[[ $(command -v mpifort) == "$MPIFC" ]] || { echo "A non-project MPI was selected" >&2; exit 1; }

zlib_archive="$DOWNLOAD_DIR/zlib-$ZLIB_VERSION.tar.gz"
zlib_source="$BUILD_DIR/src/zlib-$ZLIB_VERSION"
download "https://zlib.net/fossils/zlib-$ZLIB_VERSION.tar.gz" "$zlib_archive"
extract "$zlib_archive" "$zlib_source"
cmake_build "$zlib_source" "$BUILD_DIR/zlib" "$PREFIX/lib/libz.a" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER="$CC" -DZLIB_BUILD_EXAMPLES=OFF

hdf5_archive="$DOWNLOAD_DIR/hdf5-$HDF5_VERSION.tar.gz"
hdf5_extract="$BUILD_DIR/src/hdf5-$HDF5_VERSION"
download "https://github.com/HDFGroup/hdf5/releases/download/hdf5_$HDF5_VERSION/hdf5-$HDF5_VERSION.tar.gz" "$hdf5_archive"
extract "$hdf5_archive" "$hdf5_extract"
# HDF Group release archives use ./hdf5-VERSION/ as their top-level path.
hdf5_source="$hdf5_extract/hdf5-$HDF5_VERSION"
cmake_build "$hdf5_source" "$BUILD_DIR/hdf5" "$PREFIX/bin/h5pfc" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER="$MPICC" -DCMAKE_CXX_COMPILER="$MPICXX" \
    -DCMAKE_Fortran_COMPILER="$MPIFC" -DBUILD_SHARED_LIBS=ON \
    -DHDF5_ENABLE_PARALLEL=ON -DHDF5_BUILD_FORTRAN=ON \
    -DHDF5_BUILD_CPP_LIB=OFF -DHDF5_BUILD_EXAMPLES=OFF

pnetcdf_archive="$DOWNLOAD_DIR/pnetcdf-$PNETCDF_VERSION.tar.gz"
pnetcdf_source="$BUILD_DIR/src/pnetcdf-$PNETCDF_VERSION"
download "https://parallel-netcdf.github.io/Release/pnetcdf-$PNETCDF_VERSION.tar.gz" "$pnetcdf_archive"
extract "$pnetcdf_archive" "$pnetcdf_source"
if [[ ! -x $PREFIX/bin/pnetcdf-config ]]; then
    mkdir -p "$BUILD_DIR/pnetcdf"
    (
        cd "$BUILD_DIR/pnetcdf"
        "$pnetcdf_source/configure" --prefix="$PREFIX" CC="$MPICC" CXX="$MPICXX" \
            FC="$MPIFC" F77="$MPIFC" --enable-shared --enable-fortran
        make -j"$JOBS"
        [[ $RUN_TESTS == false ]] || make -j"$JOBS" check
        make install
    )
fi

netcdf_c_archive="$DOWNLOAD_DIR/netcdf-c-$NETCDF_C_VERSION.tar.gz"
netcdf_c_source="$BUILD_DIR/src/netcdf-c-$NETCDF_C_VERSION"
download "https://github.com/Unidata/netcdf-c/archive/refs/tags/v$NETCDF_C_VERSION.tar.gz" "$netcdf_c_archive"
extract "$netcdf_c_archive" "$netcdf_c_source"
cmake_build "$netcdf_c_source" "$BUILD_DIR/netcdf-c" "$PREFIX/bin/nc-config" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER="$MPICC" -DBUILD_SHARED_LIBS=ON \
    -DNETCDF_ENABLE_NETCDF_4=ON -DNETCDF_ENABLE_HDF5=ON \
    -DNETCDF_ENABLE_PARALLEL4=ON -DNETCDF_ENABLE_PNETCDF=ON \
    -DNETCDF_ENABLE_DAP=OFF -DNETCDF_BUILD_UTILITIES=ON

netcdf_f_archive="$DOWNLOAD_DIR/netcdf-fortran-$NETCDF_FORTRAN_VERSION.tar.gz"
netcdf_f_source="$BUILD_DIR/src/netcdf-fortran-$NETCDF_FORTRAN_VERSION"
download "https://github.com/Unidata/netcdf-fortran/archive/refs/tags/v$NETCDF_FORTRAN_VERSION.tar.gz" "$netcdf_f_archive"
extract "$netcdf_f_archive" "$netcdf_f_source"
cmake_build "$netcdf_f_source" "$BUILD_DIR/netcdf-fortran" "$PREFIX/bin/nf-config" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER="$MPICC" -DCMAKE_Fortran_COMPILER="$MPIFC" \
    -DBUILD_SHARED_LIBS=ON

pio_archive="$DOWNLOAD_DIR/pio-$PIO_VERSION.tar.gz"
pio_source="$BUILD_DIR/src/pio-$PIO_VERSION"
download "https://github.com/NCAR/ParallelIO/archive/refs/tags/pio${PIO_VERSION//./_}.tar.gz" "$pio_archive"
extract "$pio_archive" "$pio_source"
cmake_build "$pio_source" "$BUILD_DIR/pio" "$PREFIX/lib/libpiof.a" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER="$MPICC" -DCMAKE_CXX_COMPILER="$MPICXX" \
    -DCMAKE_Fortran_COMPILER="$MPIFC" -DPIO_ENABLE_FORTRAN=ON \
    -DPIO_ENABLE_TIMING=OFF -DPIO_BUILD_EXAMPLES=OFF \
    -DNetCDF_C_PATH="$PREFIX" -DNetCDF_Fortran_PATH="$PREFIX" -DPnetCDF_PATH="$PREFIX"

cat <<EOF

I/O stack installation complete: $PREFIX
Use it with:
  export PATH="$PREFIX/bin:\$PATH"
  export LD_LIBRARY_PATH="$PREFIX/lib:\${LD_LIBRARY_PATH:-}"
  export CMAKE_PREFIX_PATH="$PREFIX:\${CMAKE_PREFIX_PATH:-}"
  export NETCDF="$PREFIX"
  export PNETCDF="$PREFIX"
EOF
