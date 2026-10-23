#!/usr/bin/env bash
set -euo pipefail

# Cut a Beijing-centred limited-area mesh out of a global MPAS grid.nc or
# static.nc file with MPAS-Limited-Area's create_region, then partition it
# with gpmetis. Run ./install_mesh_tools.sh first.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${SOURCE:-$ROOT_DIR/work/beijing_240km_2026101500/x1.10242.grid.nc}"
CASE_DIR="${CASE_DIR:-$ROOT_DIR/work/beijing_region_240km}"
NAME="${NAME:-beijing_circle}"
LATITUDE="${LATITUDE:-39.9042}"
LONGITUDE="${LONGITUDE:-116.4074}"
RADIUS_KM="${RADIUS_KM:-2000}"
NTASKS="${NTASKS:-4 8}"
CONDA_DIR="${CONDA_DIR:-$ROOT_DIR/local/miniforge3}"
ENV_NAME="${ENV_NAME:-mpas_mesh}"
LAM_DIR="${LAM_DIR:-$ROOT_DIR/src/MPAS-Limited-Area}"

usage() {
  cat <<USAGE
Usage: $0 [--source FILE] [--case-dir DIR] [--name NAME] [--radius-km KM]
          [--latitude DEG] [--longitude DEG] [--ntasks "N1 N2 ..."]
Write a circle .pts file, run create_region on a global grid.nc/static.nc,
and partition the regional graph.info for each MPI task count.

Defaults: source=$SOURCE
          radius=${RADIUS_KM} km around (${LATITUDE}, ${LONGITUDE}), ntasks="$NTASKS"
USAGE
}
while (($#)); do
  case "$1" in
    --source) SOURCE="$2"; shift 2 ;;
    --case-dir) CASE_DIR="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --radius-km) RADIUS_KM="$2"; shift 2 ;;
    --latitude) LATITUDE="$2"; shift 2 ;;
    --longitude) LONGITUDE="$2"; shift 2 ;;
    --ntasks) NTASKS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -s "$SOURCE" ]] || { echo "Missing source mesh: $SOURCE" >&2; exit 1; }
[[ -x "$LAM_DIR/create_region" ]] || { echo "Missing $LAM_DIR; run ./install_mesh_tools.sh" >&2; exit 1; }
SOURCE="$(cd "$(dirname "$SOURCE")" && pwd)/$(basename "$SOURCE")"
set +u
# shellcheck disable=SC1091
source "$CONDA_DIR/etc/profile.d/conda.sh"
conda activate "$ENV_NAME"
set -u

mkdir -p "$CASE_DIR"
cd "$CASE_DIR"
radius_m="$(python -c "print(float('$RADIUS_KM') * 1000.0)")"
cat > "$NAME.pts" <<PTS
Name: $NAME
Type: circle
Point: $LATITUDE, $LONGITUDE
radius: $radius_m
PTS

# create_region names its output after the pts Name and the source type:
# NAME.grid.nc from *.grid.nc, NAME.static.nc from *.static.nc.
python "$LAM_DIR/create_region" "$NAME.pts" "$SOURCE"

case "$(basename "$SOURCE")" in
  *static*) region_file="$NAME.static.nc" ;;
  *grid*) region_file="$NAME.grid.nc" ;;
  *init*) region_file="$NAME.init.nc" ;;
  *) region_file="$NAME.region.nc" ;;
esac
[[ -s "$region_file" ]] || { echo "create_region did not write $region_file" >&2; exit 1; }
python - "$region_file" "$LATITUDE" "$LONGITUDE" <<'PY'
import math
import sys

import netCDF4
import numpy as np

path, lat0, lon0 = sys.argv[1], math.radians(float(sys.argv[2])), math.radians(float(sys.argv[3]))
with netCDF4.Dataset(path) as ds:
    lat = np.asarray(ds["latCell"][:])
    lon = np.asarray(ds["lonCell"][:])
    mask = np.asarray(ds["bdyMaskCell"][:])
dlat = lat - lat0
dlon = (lon - lon0 + math.pi) % (2.0 * math.pi) - math.pi
dist = 6371.229 * 2.0 * np.arcsin(np.sqrt(np.sin(dlat / 2) ** 2
                                          + np.cos(lat) * math.cos(lat0) * np.sin(dlon / 2) ** 2))
print(f"{path}: nCells={lat.size}, farthest cell center={dist.max():.0f} km")
# 0 = interior, 1-5 = relaxation zone, 6-7 = specified zone (MPAS-A nRelaxZone=5, nSpecZone=2)
for k in np.unique(mask):
    sel = mask == k
    print(f"  bdyMaskCell={k}: {sel.sum():4d} cells, {dist[sel].min():5.0f}-{dist[sel].max():5.0f} km from center")
PY

for n in $NTASKS; do
  gpmetis -minconn -contig -niter=200 "$NAME.graph.info" "$n" | grep -E 'Edgecut|Partitioning'
done
echo "Regional mesh: $CASE_DIR/$region_file"
