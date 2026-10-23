#!/usr/bin/env bash
set -euo pipefail

# Limited-area MPAS-A run on a create_region mesh (lesson 9):
#   init : config_init_case=7 + config_blend_bdy_terrain=true -> NAME.init.nc
#   lbc  : config_init_case=9 -> lbc.*.nc every config_fg_interval
#   run  : config_apply_lbcs=true, lbc_in every 3 h
# Reuses FILE:* and the namelists of the 240 km global case (lessons 4-6) and
# the regional static.nc cut by make_beijing_region.sh, so WPS_GEOG is not read.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_CASE="${SOURCE_CASE:-$ROOT_DIR/work/beijing_240km_2026101500}"
REGION_DIR="${REGION_DIR:-$ROOT_DIR/work/beijing_region_240km}"
NAME="${NAME:-beijing_circle}"
RUN_DIR="${RUN_DIR:-$ROOT_DIR/work/beijing_region_240km_run}"
NTASKS="${NTASKS:-4}"
START_TIME="${START_TIME:-2026-10-15_00:00:00}"
STOP_TIME="${STOP_TIME:-2026-10-16_00:00:00}"
RUN_DURATION="${RUN_DURATION:-1_00:00:00}"
FG_INTERVAL="${FG_INTERVAL:-10800}"
STAGE="${1:-all}"

usage() {
  cat <<USAGE
Usage: $0 [init|lbc|run|all]
Environment: SOURCE_CASE REGION_DIR NAME RUN_DIR NTASKS START_TIME STOP_TIME
             RUN_DURATION FG_INTERVAL (seconds; must match the FILE:* spacing)
USAGE
}
case "$STAGE" in init|lbc|run|all) ;; -h|--help) usage; exit 0 ;; *) usage >&2; exit 2 ;; esac
die() { echo "$*" >&2; exit 1; }

[[ -f "$ROOT_DIR/local/io-stack/env.sh" ]] && source "$ROOT_DIR/local/io-stack/env.sh"
MPIEXEC="$ROOT_DIR/local/io-stack/bin/mpiexec"
INIT_EXE="$ROOT_DIR/local/mpas-8.4.2/bin/mpas_init_atmosphere"
ATM_EXE="$ROOT_DIR/local/mpas-8.4.2/bin/mpas_atmosphere"
ATM_SHARE="$ROOT_DIR/local/mpas-8.4.2/share/MPAS/core_atmosphere"
[[ -x "$MPIEXEC" && -x "$INIT_EXE" && -x "$ATM_EXE" ]] || die "Run ./install_mpas.sh first"
for f in "$REGION_DIR/$NAME.static.nc" "$REGION_DIR/$NAME.graph.info.part.$NTASKS" \
         "$SOURCE_CASE/namelist.init_atmosphere" "$SOURCE_CASE/namelist.atmosphere"; do
  [[ -s "$f" ]] || die "Missing $f"
done

mkdir -p "$RUN_DIR"
cd "$RUN_DIR"
ln -sfn "$INIT_EXE" init_atmosphere_model
ln -sfn "$ATM_EXE" atmosphere_model
for file in "$ATM_SHARE"/*; do
  case "$(basename "$file")" in namelist.atmosphere|streams.atmosphere|stream_list.*) continue ;; esac
  ln -sfn "$file" .
done
ln -sfn "$REGION_DIR/$NAME.static.nc" .
ln -sfn "$REGION_DIR/$NAME.graph.info.part.$NTASKS" .
for f in "$SOURCE_CASE"/FILE:*; do ln -sfn "$f" .; done

check_log() {
  local log="$1"
  grep -q 'Critical error messages = *0' "$log" || { tail -n 20 "$log"; die "critical errors in $log"; }
  grep -E 'Error messages|Critical error messages' "$log"
}

init_streams() {   # $1 = input file, $2 = output file
  cat > streams.init_atmosphere <<XML
<streams>
<immutable_stream name="input" type="input" filename_template="$1" input_interval="initial_only" />
<immutable_stream name="output" type="output" filename_template="$2"
                  packages="initial_conds" output_interval="initial_only" />
<immutable_stream name="surface" type="output" filename_template="$NAME.sfc_update.nc"
                  filename_interval="none" packages="sfc_update" output_interval="86400" />
<immutable_stream name="lbc" type="output" filename_template="lbc.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  filename_interval="output_interval" packages="lbcs"
                  output_interval="$((FG_INTERVAL / 3600)):00:00" />
</streams>
XML
}

run_init_case() {  # $1 = case number, $2 = stop time, $3 = log copy name
  sed -e "s/config_init_case = .*/config_init_case = $1/" \
      -e "s/config_start_time = .*/config_start_time = '$START_TIME'/" \
      -e "s/config_stop_time = .*/config_stop_time = '$2'/" \
      -e "s/config_fg_interval = .*/config_fg_interval = $FG_INTERVAL/" \
      -e "s/config_blend_bdy_terrain = .*/config_blend_bdy_terrain = true/" \
      -e "s/config_block_decomp_file_prefix = .*/config_block_decomp_file_prefix = '$NAME.graph.info.part.'/" \
      "$SOURCE_CASE/namelist.init_atmosphere" > namelist.init_atmosphere
  rm -f log.init_atmosphere.*
  "$MPIEXEC" --mca btl '^openib' -n "$NTASKS" ./init_atmosphere_model
  cp log.init_atmosphere.0000.out "$3"
  check_log "$3"
}

if [[ "$STAGE" == init || "$STAGE" == all ]]; then
  init_streams "$NAME.static.nc" "$NAME.init.nc"
  run_init_case 7 "$START_TIME" log.init_case7.out
  ls -lh "$NAME.init.nc"
fi
if [[ "$STAGE" == lbc || "$STAGE" == all ]]; then
  init_streams "$NAME.init.nc" "$NAME.init_lbc_unused.nc"
  run_init_case 9 "$STOP_TIME" log.init_case9.out
  ls lbc.*.nc
fi
if [[ "$STAGE" == run || "$STAGE" == all ]]; then
  sed -e "s/config_start_time = .*/config_start_time = '$START_TIME'/" \
      -e "s/config_run_duration = .*/config_run_duration = '$RUN_DURATION'/" \
      -e "s/config_apply_lbcs = .*/config_apply_lbcs = true/" \
      -e "s/config_block_decomp_file_prefix = .*/config_block_decomp_file_prefix = '$NAME.graph.info.part.'/" \
      "$SOURCE_CASE/namelist.atmosphere" > namelist.atmosphere
  sed -e "s/x1\.10242\.init\.nc/$NAME.init.nc/" \
      -e "s/x1\.10242\.sfc_update\.nc/$NAME.sfc_update.nc/" \
      -e "/name=\"lbc_in\"/,/\/>/ s/input_interval=\"[^\"]*\"/input_interval=\"$((FG_INTERVAL / 3600)):00:00\"/" \
      "$SOURCE_CASE/streams.atmosphere" > streams.atmosphere
  # stream_list.* files list the fields each output stream writes.
  for f in "$SOURCE_CASE"/stream_list.atmosphere.*; do rm -f "$(basename "$f")"; cp "$f" .; done
  rm -f log.atmosphere.*
  "$MPIEXEC" --mca btl '^openib' -n "$NTASKS" ./atmosphere_model
  cp log.atmosphere.0000.out log.forecast.out
  check_log log.forecast.out
  ls diag.*.nc history.*.nc
fi
