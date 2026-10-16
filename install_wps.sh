#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WPS_VERSION=4.6.0
ZLIB_VERSION=1.3.1
LIBPNG_VERSION=1.6.44
JASPER_VERSION=1.900.29
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)
DOWNLOAD_DIR="$SCRIPT_DIR/downloads"
BUILD_DIR="$SCRIPT_DIR/build"
PREFIX="$SCRIPT_DIR/local/wps-$WPS_VERSION"
GRIB2_PREFIX="$SCRIPT_DIR/local/grib2"
WPS_SOURCE="$SCRIPT_DIR/src/WPS-$WPS_VERSION"
MPI_PREFIX="$SCRIPT_DIR/local/io-stack"
NETCDF_PREFIX="$SCRIPT_DIR/local/io-stack"
WRF_DIR=
CC_CMD=gcc
CXX_CMD=g++
FC_CMD=gfortran
INTERACTIVE=auto
FULL_WPS=false

usage() {
    cat <<'EOF'
Usage: ./install_wps.sh [options]

With no arguments in a terminal, prompts are shown; Enter accepts project-local
defaults. In scripts/CI, defaults are accepted without prompting.

  --prefix DIR          WPS installation prefix
  --grib2-prefix DIR    common zlib/libpng/JasPer installation prefix
  --wps-source DIR      WPS source directory
  --mpi-prefix DIR      project-built OpenMPI prefix
  --netcdf-prefix DIR   project-built netCDF prefix (added to CMake search path)
  --wrf-dir DIR         compiled/installed WRF directory (implies --full-wps)
  --full-wps            build geogrid/metgrid too; requires --wrf-dir
  --download-dir DIR    source archive cache
  --build-dir DIR       out-of-source build directory
  --cc PATH             GCC executable or command name
  --cxx PATH            G++ executable or command name
  --fc PATH              GFortran executable or command name
  -j, --jobs N          parallel jobs (default: all detected logical CPUs)
  -y, --non-interactive accept defaults without prompting
  -h, --help            show this help

The default builds only ungrib.exe for converting GFS GRIB2 into WPS
intermediate files consumed by MPAS init_atmosphere.
EOF
}

had_args=$#
while (($#)); do
    case "$1" in
        --prefix) PREFIX=$2; shift 2 ;;
        --grib2-prefix) GRIB2_PREFIX=$2; shift 2 ;;
        --wps-source) WPS_SOURCE=$2; shift 2 ;;
        --mpi-prefix) MPI_PREFIX=$2; shift 2 ;;
        --netcdf-prefix) NETCDF_PREFIX=$2; shift 2 ;;
        --wrf-dir) WRF_DIR=$2; FULL_WPS=true; shift 2 ;;
        --full-wps) FULL_WPS=true; shift ;;
        --download-dir) DOWNLOAD_DIR=$2; shift 2 ;;
        --build-dir) BUILD_DIR=$2; shift 2 ;;
        --cc) CC_CMD=$2; shift 2 ;;
        --cxx) CXX_CMD=$2; shift 2 ;;
        --fc) FC_CMD=$2; shift 2 ;;
        -j|--jobs) JOBS=$2; shift 2 ;;
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
    CC_CMD=$(prompt "GCC command/path" "$CC_CMD")
    CXX_CMD=$(prompt "G++ command/path" "$CXX_CMD")
    FC_CMD=$(prompt "GFortran command/path" "$FC_CMD")
    MPI_PREFIX=$(prompt "Project OpenMPI prefix" "$MPI_PREFIX")
    NETCDF_PREFIX=$(prompt "Project netCDF prefix" "$NETCDF_PREFIX")
    GRIB2_PREFIX=$(prompt "GRIB2 libraries prefix" "$GRIB2_PREFIX")
    WPS_SOURCE=$(prompt "WPS source directory" "$WPS_SOURCE")
    PREFIX=$(prompt "WPS install prefix" "$PREFIX")
    DOWNLOAD_DIR=$(prompt "Download cache" "$DOWNLOAD_DIR")
    BUILD_DIR=$(prompt "Build directory" "$BUILD_DIR")
    JOBS=$(prompt "Parallel jobs" "$JOBS")
fi

resolve_command() {
    command -v "$1" 2>/dev/null || { echo "Required command not found: $1" >&2; exit 1; }
}

CC=$(resolve_command "$CC_CMD")
CXX=$(resolve_command "$CXX_CMD")
FC=$(resolve_command "$FC_CMD")
for tool in autoreconf cmake curl git make python3 tar; do resolve_command "$tool" >/dev/null; done
case "$JOBS" in ''|*[!0-9]*) echo "--jobs must be a positive integer" >&2; exit 2 ;; esac
((JOBS > 0)) || { echo "--jobs must be greater than zero" >&2; exit 2; }
[[ $FULL_WPS == false || -n $WRF_DIR ]] || {
    echo "--full-wps requires --wrf-dir; MPAS needs only the default ungrib build." >&2
    exit 2
}

mkdir -p "$DOWNLOAD_DIR" "$BUILD_DIR" "$GRIB2_PREFIX" "$PREFIX" "$(dirname "$WPS_SOURCE")"

download() {
    local url=$1 output=$2
    if [[ ! -f $output ]]; then
        echo "Downloading $url"
        curl -fL --retry 3 --retry-delay 2 -o "$output.part" "$url"
        mv "$output.part" "$output"
    fi
}

cmake_install() {
    local source=$1 build=$2
    shift 2
    cmake -S "$source" -B "$build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$GRIB2_PREFIX" \
        -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
        -DBUILD_SHARED_LIBS=OFF "$@"
    cmake --build "$build" --parallel "$JOBS"
    cmake --install "$build"
}

zlib_tar="$DOWNLOAD_DIR/zlib-$ZLIB_VERSION.tar.gz"
download "https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION/zlib-$ZLIB_VERSION.tar.gz" "$zlib_tar"
if [[ ! -f $GRIB2_PREFIX/include/zlib.h ]]; then
    zlib_src="$BUILD_DIR/zlib-$ZLIB_VERSION"
    [[ -d $zlib_src ]] || tar -xzf "$zlib_tar" -C "$BUILD_DIR"
    cmake_install "$zlib_src" "$BUILD_DIR/zlib-$ZLIB_VERSION-cmake" -DZLIB_BUILD_EXAMPLES=OFF
fi

png_tar="$DOWNLOAD_DIR/libpng-$LIBPNG_VERSION.tar.gz"
download "https://github.com/pnggroup/libpng/archive/refs/tags/v$LIBPNG_VERSION.tar.gz" "$png_tar"
if [[ ! -f $GRIB2_PREFIX/include/png.h ]]; then
    png_src="$BUILD_DIR/libpng-$LIBPNG_VERSION"
    [[ -d $png_src ]] || tar -xzf "$png_tar" -C "$BUILD_DIR"
    cmake_install "$png_src" "$BUILD_DIR/libpng-$LIBPNG_VERSION-cmake" \
        -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF \
        -DZLIB_ROOT="$GRIB2_PREFIX"
fi

jasper_tar="$DOWNLOAD_DIR/jasper-$JASPER_VERSION.tar.gz"
download "https://github.com/mdadams/jasper/archive/refs/tags/version-$JASPER_VERSION.tar.gz" "$jasper_tar"
if [[ ! -f $GRIB2_PREFIX/include/jasper/jasper.h ]]; then
    jasper_src="$BUILD_DIR/jasper-version-$JASPER_VERSION"
    [[ -d $jasper_src ]] || tar -xzf "$jasper_tar" -C "$BUILD_DIR"
    # JasPer 1.900.29's no-libjpeg stub missed const qualifiers present in
    # its own public header; GCC 11 correctly rejects the conflicting types.
    sed -i 's/char \*optstr/const char *optstr/g' \
        "$jasper_src/src/libjasper/jpg/jpg_dummy.c"
    (
        cd "$jasper_src"
        autoreconf -fi
        CPPFLAGS="-I$GRIB2_PREFIX/include" LDFLAGS="-L$GRIB2_PREFIX/lib" \
            ./configure --prefix="$GRIB2_PREFIX" --disable-shared \
            --enable-static --disable-opengl --disable-libjpeg
        make -j"$JOBS"
        make install
    )
fi

if [[ ! -d $WPS_SOURCE/.git ]]; then
    git clone --branch "v$WPS_VERSION" --depth 1 https://github.com/wrf-model/WPS.git "$WPS_SOURCE"
fi
actual_tag=$(git -C "$WPS_SOURCE" describe --tags --exact-match 2>/dev/null || true)
[[ $actual_tag == "v$WPS_VERSION" ]] || {
    echo "$WPS_SOURCE exists but is not WPS v$WPS_VERSION (found: ${actual_tag:-untagged})." >&2
    exit 1
}

# WPS's generated GNU toolchain refers to gcc/g++/gfortran by name. Put the
# requested compiler directories first while retaining the project MPI stack.
export PATH="$(dirname "$CC"):$(dirname "$CXX"):$(dirname "$FC"):$MPI_PREFIX/bin:$PATH"
export CMAKE_PREFIX_PATH="$GRIB2_PREFIX${NETCDF_PREFIX:+:$NETCDF_PREFIX}${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export JASPERINC="$GRIB2_PREFIX/include"
export JASPERLIB="$GRIB2_PREFIX/lib"
export LD_LIBRARY_PATH="$GRIB2_PREFIX/lib${NETCDF_PREFIX:+:$NETCDF_PREFIX/lib}${MPI_PREFIX:+:$MPI_PREFIX/lib}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

wps_build="$BUILD_DIR/wps-$WPS_VERSION-cmake"
use_wrf=OFF
cmake_extra=()
if [[ $FULL_WPS == true ]]; then
    use_wrf=ON
    cmake_extra+=("-DWRF_ROOT=$WRF_DIR" "-DWRF_DIR=$WRF_DIR")
fi

mkdir -p "$wps_build"
"$WPS_SOURCE/arch/configure_reader.py" \
    -c "$WPS_SOURCE/arch/configure.defaults" \
    -t "$WPS_SOURCE/cmake/template/arch_config.cmake" \
    -o "$wps_build/wps_config.cmake" -x -p gfortran
cmake -S "$WPS_SOURCE" -B "$wps_build" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_TOOLCHAIN_FILE="$wps_build/wps_config.cmake" \
    -DUSE_WRF="$use_wrf" -DUSE_MPI=OFF -DUSE_OPENMP=OFF \
    -DBUILD_EXTERNALS=OFF \
    -DZLIB_ROOT="$GRIB2_PREFIX" -DPNG_ROOT="$GRIB2_PREFIX" \
    -DJasper_ROOT="$GRIB2_PREFIX" \
    "${cmake_extra[@]}"
# WPS 4.6.0 shares a Fortran module directory between ungrib and g2print;
# parallel target builds race while replacing the same .mod files.
mkdir -p "$PREFIX/modules/ungrib"
cmake --build "$wps_build" --target clean
cmake --build "$wps_build" --parallel 1
cmake --install "$wps_build"

[[ -x $PREFIX/bin/ungrib.exe || -x $PREFIX/bin/ungrib ]] || {
    echo "WPS build completed without an installed ungrib executable." >&2
    exit 1
}

echo "WPS installation complete: $PREFIX"
echo "Load this installation with:"
echo "  export PATH=\"$PREFIX/bin:\$PATH\""
