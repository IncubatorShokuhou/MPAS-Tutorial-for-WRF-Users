#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_DIR="${CASE_DIR:-$ROOT_DIR/work/beijing_92-25km}"
GEOG_DIR="${GEOG_DIR:-/eds/shared/dm/WPS_GEOG}"
INIT_EXE="$ROOT_DIR/local/mpas-8.4.2/bin/mpas_init_atmosphere"
INIT_SHARE="$ROOT_DIR/local/mpas-8.4.2/share/MPAS/core_init_atmosphere"
MPIEXEC="$ROOT_DIR/local/io-stack/bin/mpiexec"

[[ -x "$INIT_EXE" ]] || { echo "Run ./install_mpas.sh first" >&2; exit 1; }
[[ -f "$CASE_DIR/beijing.x4.163842.grid.nc" ]] || { echo "Run ./prepare_beijing_vr_mesh.sh first" >&2; exit 1; }
[[ -r "$GEOG_DIR/topo_gmted2010_30s/index" ]] || {
  echo "Cannot read $GEOG_DIR/topo_gmted2010_30s/index; request WPS_GEOG ACL/group access" >&2
  exit 1
}

ln -sfn "$INIT_EXE" "$CASE_DIR/init_atmosphere_model"
cat > "$CASE_DIR/namelist.init_atmosphere" <<EOF
&nhyd_model
 config_init_case = 7
 config_start_time = '2026-10-15_00:00:00'
 config_stop_time = '2026-10-15_00:00:00'
/
&dimensions
 config_nvertlevels = 1
 config_nsoillevels = 1
 config_nfglevels = 1
 config_nfgsoillevels = 1
 config_gocartlevels = 1
/
&data_sources
 config_geog_data_path = '$GEOG_DIR/'
 config_landuse_data = 'MODIFIED_IGBP_MODIS_NOAH'
 config_soilcat_data = 'STATSGO'
 config_topo_data = 'GMTED2010'
 config_vegfrac_data = 'MODIS'
 config_albedo_data = 'MODIS'
 config_maxsnowalbedo_data = 'MODIS'
 config_supersample_factor = 1
 config_lu_supersample_factor = 1
 config_30s_supersample_factor = 1
/
&preproc_stages
 config_static_interp = true
 config_native_gwd_static = true
 config_native_gwd_gsl_static = false
 config_vertical_grid = false
 config_met_interp = false
 config_input_sst = false
 config_frac_seaice = false
/
&io
 config_pio_num_iotasks = 0
 config_pio_stride = 1
/
&decomposition
 config_block_decomp_file_prefix = 'x4.163842.graph.info.part.'
/
EOF

sed -e 's/x1\.40962\.grid\.nc/beijing.x4.163842.grid.nc/' \
    -e 's/x1\.40962\.init\.nc/beijing.x4.163842.static.nc/' \
    "$INIT_SHARE/streams.init_atmosphere" > "$CASE_DIR/streams.init_atmosphere"

cd "$CASE_DIR"
rm -f beijing.x4.163842.static.nc
"$MPIEXEC" --mca btl '^openib' -n 1 ./init_atmosphere_model
[[ -s beijing.x4.163842.static.nc ]] || { echo "Static interpolation failed" >&2; exit 1; }
echo "Created $CASE_DIR/beijing.x4.163842.static.nc"
