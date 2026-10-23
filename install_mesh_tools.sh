#!/usr/bin/env bash
set -euo pipefail

# Install the Python mesh tools used by lesson 10 into Git-ignored directories:
#   local/miniforge3/              conda base (Miniforge, conda-forge only)
#   local/miniforge3/envs/mpas_mesh mpas_tools + jigsaw + METIS + netCDF tools
#   src/MPAS-Limited-Area/         create_region, pinned to a fixed commit
#   src/mpas_jigsaw_tutorial/      NCAR mesh-generation mini-tutorial (mesh_quality.py)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDA_DIR="${CONDA_DIR:-$ROOT_DIR/local/miniforge3}"
ENV_NAME="${ENV_NAME:-mpas_mesh}"
MINIFORGE_URL="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-$(uname -m).sh"
LAM_REPO="https://github.com/MPAS-Dev/MPAS-Limited-Area.git"
# MPAS-Limited-Area v2.2 (2025-04-01). Pin the commit so create_region does not
# change silently on another machine.
LAM_REVISION="${LAM_REVISION:-edc556e174aee626bb8b54ec7f2ca00e05c501a1}"
JIGSAW_TUT_REPO="https://github.com/mgduda/mpas_jigsaw_tutorial.git"
# Repository accompanying the 2026 "Generating meshes for MPAS-Atmosphere" lecture.
JIGSAW_TUT_REVISION="${JIGSAW_TUT_REVISION:-d5cd1c83112f14256883b24fe536dda2352e5005}"
PACKAGES=(python=3.12 "mpas_tools=2.1.0" jigsawpy metis netcdf4 matplotlib-base cartopy nco)

usage() {
  cat <<USAGE
Usage: $0 [--conda-dir DIR] [--env-name NAME] [--lam-revision REF]
Install Miniforge, a conda environment with mpas_tools/jigsaw/METIS,
MPAS-Limited-Area and mpas_jigsaw_tutorial. Existing installs are reused.
USAGE
}
while (($#)); do
  case "$1" in
    --conda-dir) CONDA_DIR="$2"; shift 2 ;;
    --env-name) ENV_NAME="$2"; shift 2 ;;
    --lam-revision) LAM_REVISION="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

mkdir -p "$ROOT_DIR/downloads" "$ROOT_DIR/src" "$(dirname "$CONDA_DIR")"
if [[ ! -x "$CONDA_DIR/bin/conda" ]]; then
  installer="$ROOT_DIR/downloads/Miniforge3-Linux-$(uname -m).sh"
  [[ -s "$installer" ]] || curl -L --fail --retry 3 -o "$installer" "$MINIFORGE_URL"
  bash "$installer" -b -p "$CONDA_DIR"
fi
# conda's activation hooks are not written for `set -u`.
set +u
# shellcheck disable=SC1091
source "$CONDA_DIR/etc/profile.d/conda.sh"
if ! conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  conda create -y -n "$ENV_NAME" -c conda-forge --override-channels "${PACKAGES[@]}"
fi

lam_dir="$ROOT_DIR/src/MPAS-Limited-Area"
if [[ ! -d "$lam_dir/.git" ]]; then
  git clone --quiet "$LAM_REPO" "$lam_dir"
fi
git -C "$lam_dir" checkout --quiet --detach "$LAM_REVISION"
tut_dir="$ROOT_DIR/src/mpas_jigsaw_tutorial"
if [[ ! -d "$tut_dir/.git" ]]; then
  git clone --quiet "$JIGSAW_TUT_REPO" "$tut_dir"
fi
git -C "$tut_dir" checkout --quiet --detach "$JIGSAW_TUT_REVISION"

conda activate "$ENV_NAME"
set -u
python -c 'import mpas_tools, jigsawpy, netCDF4; print("mpas_tools", mpas_tools.__version__)'
for exe in jigsaw MpasMeshConverter.x gpmetis ncdump; do
  printf '%-22s %s\n' "$exe" "$(command -v "$exe")"
done
echo "MPAS-Limited-Area: $(git -C "$lam_dir" rev-parse HEAD)"
echo "mpas_jigsaw_tutorial: $(git -C "$tut_dir" rev-parse HEAD)"
echo "Activate with: source $CONDA_DIR/etc/profile.d/conda.sh && conda activate $ENV_NAME"
