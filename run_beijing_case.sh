#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_DIR="${CASE_DIR:-$ROOT_DIR/work/beijing_240km_2026101500}"
NTASKS="${NTASKS:-16}"

usage() {
  cat <<EOF
Usage: $0 [init|forecast|all]

The case directory defaults to work/beijing_240km_2026101500. Override it with
CASE_DIR=/path/to/case. Time, input interval, and geography settings are read
from CASE_DIR/case.env when that file exists.
EOF
}

if (($# > 1)); then
  usage >&2
  exit 2
fi
case "${1:-all}" in
  -h|--help) usage; exit 0 ;;
  init|forecast|all) STAGE="${1:-all}" ;;
  *) usage >&2; exit 2 ;;
esac

# Keep the documented tutorial case runnable even before case.env exists, but
# let prepare_beijing_case.sh's metadata drive every prepared case.
selected_case_dir="$CASE_DIR"
if [[ -f "$CASE_DIR/case.env" ]]; then
  # shellcheck disable=SC1090
  source "$CASE_DIR/case.env"
  CASE_DIR="$selected_case_dir"
else
  echo "WARNING: $CASE_DIR/case.env is missing; using the tutorial baseline times." >&2
fi
START_TIME="${START_TIME:-2026-10-15_00:00:00}"
FORECAST_HOURS="${FORECAST_HOURS:-24}"
INTERVAL_HOURS="${INTERVAL_HOURS:-3}"
WPS_GEOG="${WPS_GEOG:-/eds/shared/dm/WPS_GEOG}"

die() { echo "ERROR: $*" >&2; exit 1; }

case "$FORECAST_HOURS" in ''|*[!0-9]*) die "FORECAST_HOURS must be a positive integer" ;; esac
case "$INTERVAL_HOURS" in ''|*[!0-9]*) die "INTERVAL_HOURS must be a positive integer" ;; esac
FORECAST_HOURS=$((10#$FORECAST_HOURS))
INTERVAL_HOURS=$((10#$INTERVAL_HOURS))
((FORECAST_HOURS > 0)) || die "FORECAST_HOURS must be greater than zero"
((INTERVAL_HOURS > 0)) || die "INTERVAL_HOURS must be greater than zero"
[[ "$START_TIME" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] ||
  die "Invalid START_TIME in case.env: $START_TIME"
start_epoch="$(date -u -d "${START_TIME/_/ }" +%s)" || die "Invalid START_TIME: $START_TIME"
if [[ -n ${STOP_TIME:-} ]]; then
  [[ "$STOP_TIME" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] ||
    die "Invalid STOP_TIME in case.env: $STOP_TIME"
  stop_epoch="$(date -u -d "${STOP_TIME/_/ }" +%s)" || die "Invalid STOP_TIME: $STOP_TIME"
else
  stop_epoch=$((start_epoch + FORECAST_HOURS * 3600))
  STOP_TIME="$(date -u -d "@$stop_epoch" +%Y-%m-%d_%H:%M:%S)"
fi
duration_seconds=$((stop_epoch - start_epoch))
((duration_seconds > 0)) || die "STOP_TIME must be later than START_TIME"
((duration_seconds == FORECAST_HOURS * 3600)) ||
  die "case.env is inconsistent: START_TIME/STOP_TIME span ${duration_seconds}s, but FORECAST_HOURS=$FORECAST_HOURS"
duration_days=$((duration_seconds / 86400))
duration_remainder=$((duration_seconds % 86400))
printf -v RUN_DURATION '%d_%02d:%02d:%02d' \
  "$duration_days" "$((duration_remainder / 3600))" \
  "$(((duration_remainder % 3600) / 60))" "$((duration_remainder % 60))"
FG_INTERVAL_SECONDS=$((INTERVAL_HOURS * 3600))
echo "Case timing: $START_TIME -> $STOP_TIME (run duration $RUN_DURATION; input every ${INTERVAL_HOURS}h)"

[[ -f "$ROOT_DIR/local/io-stack/env.sh" ]] && source "$ROOT_DIR/local/io-stack/env.sh"
MPIEXEC="$ROOT_DIR/local/io-stack/bin/mpiexec"
INIT_EXE="$ROOT_DIR/local/mpas-8.4.2/bin/mpas_init_atmosphere"
ATM_EXE="$ROOT_DIR/local/mpas-8.4.2/bin/mpas_atmosphere"
INIT_SHARE="$ROOT_DIR/local/mpas-8.4.2/share/MPAS/core_init_atmosphere"
ATM_SHARE="$ROOT_DIR/local/mpas-8.4.2/share/MPAS/core_atmosphere"

[[ -d "$CASE_DIR" ]] || die "Run ./prepare_beijing_case.sh first"
[[ -x "$MPIEXEC" && -x "$INIT_EXE" && -x "$ATM_EXE" ]] || die "Run ./install_mpas.sh first"
[[ -f "$CASE_DIR/x1.10242.graph.info.part.$NTASKS" ]] || die "No mesh partition for NTASKS=$NTASKS"
if [[ "$STAGE" == init || "$STAGE" == all ]]; then
  [[ -s "$CASE_DIR/FILE:${START_TIME:0:13}" ]] ||
    die "Missing FILE:${START_TIME:0:13}; run ungrib.exe in $CASE_DIR first"
  [[ "$WPS_GEOG" != *"'"* ]] || die "WPS_GEOG may not contain a single quote"
fi

prepare_common() {
  ln -sfn "$INIT_EXE" "$CASE_DIR/init_atmosphere_model"
  ln -sfn "$ATM_EXE" "$CASE_DIR/atmosphere_model"
  for file in "$ATM_SHARE"/*; do
    name="$(basename "$file")"
    case "$name" in namelist.atmosphere|streams.atmosphere) continue ;; esac
    ln -sfn "$file" "$CASE_DIR/$name"
  done
}

write_init_config() {
  cat > "$CASE_DIR/namelist.init_atmosphere" <<EOF
&nhyd_model
 config_init_case = 7
 config_start_time = '$START_TIME'
 config_stop_time = '$START_TIME'
 config_theta_adv_order = 3
 config_coef_3rd_order = 0.25
 config_interface_projection = 'linear_interpolation'
/
&dimensions
 config_nvertlevels = 55
 config_nsoillevels = 4
 config_nfglevels = 38
 config_nfgsoillevels = 4
 config_gocartlevels = 30
/
&data_sources
 config_geog_data_path = '$WPS_GEOG/'
 config_met_prefix = 'FILE'
 config_sfc_prefix = 'FILE'
 config_fg_interval = $FG_INTERVAL_SECONDS
 config_use_spechumd = false
/
&vertical_grid
 config_ztop = 30000.0
 config_hybrid_coordinate = true
 config_hybrid_top_z = 30000.0
 config_nsmterrain = 1
 config_smooth_surfaces = true
 config_dzmin = 0.3
 config_nsm = 30
 config_tc_vertical_grid = true
 config_blend_bdy_terrain = false
/
&interpolation_control
 config_extrap_airtemp = 'lapse-rate'
/
&preproc_stages
 config_static_interp = false
 config_native_gwd_static = false
 config_native_gwd_gsl_static = false
 config_vertical_grid = true
 config_met_interp = true
 config_input_sst = false
 config_frac_seaice = true
/
&io
 config_pio_num_iotasks = 0
 config_pio_stride = 1
/
&decomposition
 config_block_decomp_file_prefix = 'x1.10242.graph.info.part.'
/
EOF
  sed -e 's/x1\.40962\.grid\.nc/x1.10242.static.nc/' \
      -e 's/x1\.40962\.init\.nc/x1.10242.init.nc/' \
      -e 's/x1\.40962\.sfc_update\.nc/x1.10242.sfc_update.nc/' \
      "$INIT_SHARE/streams.init_atmosphere" > "$CASE_DIR/streams.init_atmosphere"
}

write_forecast_config() {
  cp "$ATM_SHARE/namelist.atmosphere" "$CASE_DIR/namelist.atmosphere"
  sed -i \
    -e "s/config_dt = .*/config_dt = 1200.0/" \
    -e "s/config_start_time = .*/config_start_time = '$START_TIME'/" \
    -e "s/config_stop_time = .*/config_stop_time = 'none'/" \
    -e "s/config_run_duration = .*/config_run_duration = '$RUN_DURATION'/" \
    -e "s/config_block_decomp_file_prefix = .*/config_block_decomp_file_prefix = 'x1.10242.graph.info.part.'/" \
    "$CASE_DIR/namelist.atmosphere"
  sed -e 's/x1\.40962\.init\.nc/x1.10242.init.nc/' \
      -e 's/x1\.40962\.sfc_update\.nc/x1.10242.sfc_update.nc/' \
      "$ATM_SHARE/streams.atmosphere" > "$CASE_DIR/streams.atmosphere"
}

prepare_common
cd "$CASE_DIR"
if [[ "$STAGE" == init || "$STAGE" == all ]]; then
  write_init_config
  "$MPIEXEC" --mca btl '^openib' -n "$NTASKS" ./init_atmosphere_model
  [[ -s x1.10242.init.nc ]] || die "Initialization did not create x1.10242.init.nc"
fi
if [[ "$STAGE" == forecast || "$STAGE" == all ]]; then
  [[ -s x1.10242.init.nc ]] || die "Run $0 init first"
  write_forecast_config
  "$MPIEXEC" --mca btl '^openib' -n "$NTASKS" ./atmosphere_model
fi
