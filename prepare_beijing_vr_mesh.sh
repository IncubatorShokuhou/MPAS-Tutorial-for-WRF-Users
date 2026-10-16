#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_DIR="${CASE_DIR:-$ROOT_DIR/work/beijing_92-25km}"
LATITUDE="${LATITUDE:-39.9042}"
LONGITUDE="${LONGITUDE:-116.4074}"
MESH_URL="https://www2.mmm.ucar.edu/projects/mpas/atmosphere_meshes/x4.163842.tar.gz"
TOOLS_REPO="https://github.com/MPAS-Dev/MPAS-Tools.git"
# MPAS-Tools 2.1.0. Pin the commit so a future tag move or main-branch change
# cannot silently alter grid_rotate on another machine.
TOOLS_REVISION="${MPAS_TOOLS_REVISION:-be1954cf369ae0e3aad06cda7283a15f7cb1325e}"

usage() {
  cat <<EOF
Usage: $0 [--case-dir DIR] [--latitude DEG] [--longitude DEG] [options]
Rotate the official 92-25 km refinement from (0,0) to Beijing by default.

  --mpas-tools-revision REF  pinned MPAS-Tools commit/tag
                             (default: $TOOLS_REVISION; MPAS-Tools 2.1.0)
EOF
}
while (($#)); do
  case "$1" in
    --case-dir) CASE_DIR="$2"; shift 2 ;;
    --latitude) LATITUDE="$2"; shift 2 ;;
    --longitude) LONGITUDE="$2"; shift 2 ;;
    --mpas-tools-revision) TOOLS_REVISION="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

mkdir -p "$ROOT_DIR/downloads" "$ROOT_DIR/src" "$ROOT_DIR/local/bin" "$CASE_DIR"
archive="$ROOT_DIR/downloads/x4.163842.tar.gz"
if ! tar -tzf "$archive" >/dev/null 2>&1; then
  curl -L --fail --retry 3 -C - -o "$archive" "$MESH_URL"
fi
tar -xzf "$archive" -C "$CASE_DIR"

tools_dir="$ROOT_DIR/src/MPAS-Tools"
if [[ ! -d "$tools_dir/.git" ]]; then
  mkdir -p "$tools_dir"
  git -C "$tools_dir" init
  git -C "$tools_dir" remote add origin "$TOOLS_REPO"
fi
if ! git -C "$tools_dir" cat-file -e "$TOOLS_REVISION^{commit}" 2>/dev/null; then
  git -C "$tools_dir" fetch --depth 1 origin "$TOOLS_REVISION"
fi
git -C "$tools_dir" checkout --detach "$TOOLS_REVISION"
resolved_revision="$(git -C "$tools_dir" rev-parse HEAD)"
echo "Using MPAS-Tools revision: $resolved_revision"
export PATH="$ROOT_DIR/local/io-stack/bin:$PATH"
export LD_LIBRARY_PATH="$ROOT_DIR/local/io-stack/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
make -C "$tools_dir/mesh_tools/grid_rotate" -j "$(nproc)"
cp "$tools_dir/mesh_tools/grid_rotate/grid_rotate" "$ROOT_DIR/local/bin/grid_rotate"

cat > "$CASE_DIR/namelist.input" <<EOF
&input
 config_original_latitude_degrees = 0.0
 config_original_longitude_degrees = 0.0
 config_new_latitude_degrees = $LATITUDE
 config_new_longitude_degrees = $LONGITUDE
 config_birdseye_rotation_counter_clockwise_degrees = 0.0
/
EOF

output="$CASE_DIR/beijing.x4.163842.grid.nc"
rm -f "$output"
(cd "$CASE_DIR" && "$ROOT_DIR/local/bin/grid_rotate" x4.163842.grid.nc "$(basename "$output")")

python - "$output" "$LATITUDE" "$LONGITUDE" <<'PY'
import math, sys
import netCDF4
import numpy as np
path, lat0, lon0 = sys.argv[1], math.radians(float(sys.argv[2])), math.radians(float(sys.argv[3]))
with netCDF4.Dataset(path) as ds:
    lat = np.asarray(ds['latCell'][:]); lon = np.asarray(ds['lonCell'][:]); area = np.asarray(ds['areaCell'][:])
dlat = lat-lat0; dlon = (lon-lon0+math.pi)%(2*math.pi)-math.pi
d = 6371*2*np.arcsin(np.sqrt(np.sin(dlat/2)**2+np.cos(lat)*math.cos(lat0)*np.sin(dlon/2)**2))
i = int(np.argmin(d))
# areaCell is area on the unit sphere; multiply sqrt(area) by Earth radius.
print(f"nearest cell={i}, distance={d[i]:.3f} km, area scale={6371*math.sqrt(area[i]):.2f} km")
PY
echo "Rotated mesh: $output"
echo "Graph partitions remain: $CASE_DIR/x4.163842.graph.info.part.*"
