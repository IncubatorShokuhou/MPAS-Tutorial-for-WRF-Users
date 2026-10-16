#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_DIR="${CASE_DIR:-$ROOT_DIR/work/beijing_240km_2026101500}"
GFS_ROOT="${GFS_ROOT:-/eds/shared/energy/gfs}"
DATE="${DATE:-20261015}"
CYCLE="${CYCLE:-00}"
FORECAST_HOURS="${FORECAST_HOURS:-24}"
INTERVAL_HOURS="${INTERVAL_HOURS:-3}"
MESH_URL="https://www2.mmm.ucar.edu/projects/mpas/atmosphere_meshes/x1.10242.tar.gz"
STATIC_URL="https://www2.mmm.ucar.edu/projects/mpas/atmosphere_meshes/x1.10242_static.tar.gz"

usage() {
  cat <<EOF
Usage: $0 [options]
  --case-dir DIR       case directory (default: work/beijing_240km_2026101500)
  --gfs-root DIR       GFS archive root (default: /eds/shared/energy/gfs)
  --date YYYYMMDD      initialization date (default: 20261015)
  --cycle HH           UTC cycle (default: 00)
  --forecast-hours N   forecast length (default: 24)
  --interval-hours N   GFS interval (default: 3)
EOF
}

while (($#)); do
  case "$1" in
    --case-dir) CASE_DIR="$2"; shift 2 ;;
    --gfs-root) GFS_ROOT="$2"; shift 2 ;;
    --date) DATE="$2"; shift 2 ;;
    --cycle) CYCLE="$2"; shift 2 ;;
    --forecast-hours) FORECAST_HOURS="$2"; shift 2 ;;
    --interval-hours) INTERVAL_HOURS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for path in \
  "$ROOT_DIR/local/wps-4.6.0/bin/ungrib.exe" \
  "$ROOT_DIR/src/WPS-4.6.0/link_grib.csh" \
  "$ROOT_DIR/src/WPS-4.6.0/ungrib/Variable_Tables/Vtable.GFS"; do
  [[ -e "$path" ]] || { echo "Missing $path; run ./install_wps.sh first" >&2; exit 1; }
done

GFS_DIR="$GFS_ROOT/gfs.$DATE/$CYCLE/atmos"
[[ -d "$GFS_DIR" ]] || { echo "Missing GFS cycle: $GFS_DIR" >&2; exit 1; }
mkdir -p "$CASE_DIR" "$ROOT_DIR/downloads"

for archive in x1.10242.tar.gz x1.10242_static.tar.gz; do
  url="$MESH_URL"; [[ "$archive" == *_static* ]] && url="$STATIC_URL"
  [[ -s "$ROOT_DIR/downloads/$archive" ]] || curl -L --fail --retry 3 -o "$ROOT_DIR/downloads/$archive" "$url"
  tar -xzf "$ROOT_DIR/downloads/$archive" -C "$CASE_DIR"
done

ln -sfn "$ROOT_DIR/local/wps-4.6.0/bin/ungrib.exe" "$CASE_DIR/ungrib.exe"
ln -sfn "$ROOT_DIR/src/WPS-4.6.0/ungrib/Variable_Tables/Vtable.GFS" "$CASE_DIR/Vtable"

files=()
for ((hour=0; hour<=FORECAST_HOURS; hour+=INTERVAL_HOURS)); do
  printf -v lead '%03d' "$hour"
  file="$GFS_DIR/gfs.t${CYCLE}z.pgrb2.0p25.f${lead}"
  [[ -s "$file" && "$file" != *.tmp ]] || { echo "Missing/incomplete GFS file: $file" >&2; exit 1; }
  files+=("$file")
done

rm -f "$CASE_DIR"/GRIBFILE.???
(cd "$CASE_DIR" && "$ROOT_DIR/src/WPS-4.6.0/link_grib.csh" "${files[@]}")

start="${DATE:0:4}-${DATE:4:2}-${DATE:6:2}_${CYCLE}:00:00"
start_epoch="$(date -u -d "${DATE:0:4}-${DATE:4:2}-${DATE:6:2} ${CYCLE}:00:00" +%s)"
end="$(date -u -d "@$((start_epoch + FORECAST_HOURS * 3600))" +%Y-%m-%d_%H:%M:%S)"
cat > "$CASE_DIR/namelist.wps" <<EOF
&share
 start_date = '$start'
 end_date = '$end'
 interval_seconds = $((INTERVAL_HOURS * 3600))
/
&ungrib
 out_format = 'WPS'
 prefix = 'FILE'
/
EOF

cat > "$CASE_DIR/case.env" <<EOF
export MPAS_TUTORIAL_ROOT='$ROOT_DIR'
export CASE_DIR='$CASE_DIR'
export START_TIME='$start'
export STOP_TIME='$end'
export FORECAST_HOURS='$FORECAST_HOURS'
export WPS_GEOG='/eds/shared/dm/WPS_GEOG'
EOF

echo "Prepared $CASE_DIR"
echo "Next: cd '$CASE_DIR' && ./ungrib.exe"
