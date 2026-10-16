#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_DIR="${CASE_DIR:-$ROOT_DIR/work/beijing_240km_2026101500}"
GFS_ROOT="${GFS_ROOT:-/eds/shared/energy/gfs}"
WPS_GEOG="${WPS_GEOG:-/eds/shared/dm/WPS_GEOG}"
DATE="${DATE:-20261015}"
CYCLE="${CYCLE:-00}"
FORECAST_HOURS="${FORECAST_HOURS:-24}"
INTERVAL_HOURS="${INTERVAL_HOURS:-3}"
MESH_ONLY=false
MESH_URL="https://www2.mmm.ucar.edu/projects/mpas/atmosphere_meshes/x1.10242.tar.gz"
STATIC_URL="https://www2.mmm.ucar.edu/projects/mpas/atmosphere_meshes/x1.10242_static.tar.gz"

usage() {
  cat <<EOF
Usage: $0 [options]
  --case-dir DIR       case directory (default: work/beijing_240km_2026101500)
  --gfs-root DIR       GFS archive root (default: /eds/shared/energy/gfs)
  --wps-geog DIR       WPS geography root (default: /eds/shared/dm/WPS_GEOG)
  --date YYYYMMDD      initialization date (default: 20261015)
  --cycle HH           UTC cycle (default: 00)
  --forecast-hours N   forecast length (default: 24)
  --interval-hours N   GFS interval (default: 3)
  --mesh-only          download/extract the mesh and static file, then stop
EOF
}

while (($#)); do
  case "$1" in
    --case-dir) CASE_DIR="$2"; shift 2 ;;
    --gfs-root) GFS_ROOT="$2"; shift 2 ;;
    --wps-geog) WPS_GEOG="$2"; shift 2 ;;
    --date) DATE="$2"; shift 2 ;;
    --cycle) CYCLE="$2"; shift 2 ;;
    --forecast-hours) FORECAST_HOURS="$2"; shift 2 ;;
    --interval-hours) INTERVAL_HOURS="$2"; shift 2 ;;
    --mesh-only) MESH_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $MESH_ONLY == false ]]; then
  [[ "$DATE" =~ ^[0-9]{8}$ ]] || { echo "--date must use YYYYMMDD" >&2; exit 2; }
  [[ "$CYCLE" =~ ^[0-9]{2}$ ]] || { echo "--cycle must use two digits (HH)" >&2; exit 2; }
  case "$FORECAST_HOURS" in ''|*[!0-9]*) echo "--forecast-hours must be a positive integer" >&2; exit 2 ;; esac
  case "$INTERVAL_HOURS" in ''|*[!0-9]*) echo "--interval-hours must be a positive integer" >&2; exit 2 ;; esac
  FORECAST_HOURS=$((10#$FORECAST_HOURS))
  INTERVAL_HOURS=$((10#$INTERVAL_HOURS))
  cycle_number=$((10#$CYCLE))
  ((cycle_number <= 23)) || { echo "--cycle must be between 00 and 23" >&2; exit 2; }
  ((FORECAST_HOURS > 0)) || { echo "--forecast-hours must be greater than zero" >&2; exit 2; }
  ((INTERVAL_HOURS > 0)) || { echo "--interval-hours must be greater than zero" >&2; exit 2; }
  date -u -d "${DATE:0:4}-${DATE:4:2}-${DATE:6:2} ${CYCLE}:00:00" +%s >/dev/null 2>&1 || {
    echo "Invalid initialization date/cycle: $DATE $CYCLE" >&2
    exit 2
  }
  if ! CSH_BIN="$(command -v "${CSH:-csh}" 2>/dev/null)"; then
    echo "Required command not found: csh (set CSH=/path/to/csh to override)" >&2
    exit 1
  fi
fi

mkdir -p "$CASE_DIR" "$ROOT_DIR/downloads"
for archive in x1.10242.tar.gz x1.10242_static.tar.gz; do
  url="$MESH_URL"; [[ "$archive" == *_static* ]] && url="$STATIC_URL"
  [[ -s "$ROOT_DIR/downloads/$archive" ]] || curl -L --fail --retry 3 -o "$ROOT_DIR/downloads/$archive" "$url"
  tar -xzf "$ROOT_DIR/downloads/$archive" -C "$CASE_DIR"
done

if [[ $MESH_ONLY == true ]]; then
  echo "Prepared mesh files in $CASE_DIR"
  exit 0
fi

for path in \
  "$ROOT_DIR/local/wps-4.6.0/bin/ungrib.exe" \
  "$ROOT_DIR/src/WPS-4.6.0/link_grib.csh" \
  "$ROOT_DIR/src/WPS-4.6.0/ungrib/Variable_Tables/Vtable.GFS"; do
  [[ -e "$path" ]] || { echo "Missing $path; run ./install_wps.sh first" >&2; exit 1; }
done

GFS_DIR="$GFS_ROOT/gfs.$DATE/$CYCLE/atmos"
[[ -d "$GFS_DIR" ]] || { echo "Missing GFS cycle: $GFS_DIR" >&2; exit 1; }

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
(cd "$CASE_DIR" && "$CSH_BIN" "$ROOT_DIR/src/WPS-4.6.0/link_grib.csh" "${files[@]}")

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

{
  printf 'export MPAS_TUTORIAL_ROOT=%q\n' "$ROOT_DIR"
  printf 'export CASE_DIR=%q\n' "$CASE_DIR"
  printf 'export DATE=%q\n' "$DATE"
  printf 'export CYCLE=%q\n' "$CYCLE"
  printf 'export START_TIME=%q\n' "$start"
  printf 'export STOP_TIME=%q\n' "$end"
  printf 'export FORECAST_HOURS=%q\n' "$FORECAST_HOURS"
  printf 'export INTERVAL_HOURS=%q\n' "$INTERVAL_HOURS"
  printf 'export WPS_GEOG=%q\n' "$WPS_GEOG"
} > "$CASE_DIR/case.env"

echo "Prepared $CASE_DIR"
echo "Next: cd '$CASE_DIR' && ./ungrib.exe"
