#!/usr/bin/env python3
"""Build a global variable-resolution MPAS-A mesh refined around one point.

Steps:
  1. sample a cell-width function h(r) (km) on a regular lon/lat grid;
  2. mpas_tools.mesh.creation.build_spherical_mesh -> JIGSAW -> base_mesh.nc;
  3. rewrite the mesh in MPAS-Atmosphere conventions as NAME.grid.nc:
     unit sphere (sphere_radius = 1), meshDensity = (h_min / h)^4 and
     nominalMinDc = h_min / R, as in the official MPAS-A meshes;
  4. keep the METIS graph written by MpasMeshConverter.x as NAME.graph.info.

h(r) is the piecewise-linear profile used in the NCAR "Generating meshes for
MPAS-Atmosphere" mini-tutorial: fine inside fine_radius, linear transition over
transition_km, coarse outside.
"""

from __future__ import annotations

import argparse
import math
import os
import shutil
import time
from pathlib import Path

import netCDF4
import numpy as np

EARTH_RADIUS_M = 6371229.0  # MPAS-Atmosphere's Earth radius
LENGTH_VARS = ("xCell", "yCell", "zCell", "xEdge", "yEdge", "zEdge",
               "xVertex", "yVertex", "zVertex", "dcEdge", "dvEdge")
AREA_VARS = ("areaCell", "areaTriangle", "kiteAreasOnVertex")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--latitude", type=float, default=39.9042)
    p.add_argument("--longitude", type=float, default=116.4074)
    p.add_argument("--fine-km", type=float, default=60.0)
    p.add_argument("--coarse-km", type=float, default=240.0)
    p.add_argument("--fine-radius-km", type=float, default=1500.0,
                   help="radius of the uniform fine region")
    p.add_argument("--transition-km", type=float, default=6000.0,
                   help="width of the linear fine-to-coarse transition")
    p.add_argument("--step-deg", type=float, default=0.5,
                   help="spacing of the lon/lat grid that samples cellWidth")
    p.add_argument("--name", default="beijing_vr_240-60km")
    p.add_argument("--out-dir", type=Path, default=Path("work/beijing_vr_240-60km"))
    return p.parse_args()


def great_circle_km(lat, lon, lat0, lon0):
    lat, lon = np.radians(lat), np.radians(lon)
    lat0, lon0 = math.radians(lat0), math.radians(lon0)
    dlat = lat - lat0
    dlon = (lon - lon0 + math.pi) % (2.0 * math.pi) - math.pi
    hav = np.sin(dlat / 2) ** 2 + np.cos(lat) * math.cos(lat0) * np.sin(dlon / 2) ** 2
    return EARTH_RADIUS_M / 1000.0 * 2.0 * np.arcsin(np.sqrt(np.clip(hav, 0.0, 1.0)))


def cell_width_km(r, a):
    t0, t1 = a.fine_radius_km, a.fine_radius_km + a.transition_km
    frac = np.clip((r - t0) / (t1 - t0), 0.0, 1.0)
    return a.fine_km + frac * (a.coarse_km - a.fine_km)


def to_mpas_atmosphere(base: Path, out: Path, a) -> None:
    """Copy base_mesh.nc to a unit-sphere MPAS-A grid file."""
    with netCDF4.Dataset(base) as src, netCDF4.Dataset(out, "w", format="NETCDF3_64BIT_OFFSET") as dst:
        radius = float(src.getncattr("sphere_radius"))
        for name, dim in src.dimensions.items():
            dst.createDimension(name, None if dim.isunlimited() else len(dim))
        for name, var in src.variables.items():
            new = dst.createVariable(name, var.datatype, var.dimensions)
            new.setncatts({k: var.getncattr(k) for k in var.ncattrs()})
            data = var[:]
            if name in LENGTH_VARS:
                data = data / radius
            elif name in AREA_VARS:
                data = data / radius**2
            new[:] = data
        attrs = {k: src.getncattr(k) for k in src.ncattrs()}
        attrs["sphere_radius"] = 1.0
        dst.setncatts(attrs)

        lat = np.degrees(src["latCell"][:])
        lon = np.degrees(src["lonCell"][:])
        h = cell_width_km(great_circle_km(lat, lon, a.latitude, a.longitude), a)
        density = (a.fine_km / h) ** 4
        if "meshDensity" not in dst.variables:
            dst.createVariable("meshDensity", "f8", ("nCells",))
        dst["meshDensity"][:] = density
        dst["meshDensity"].long_name = "density function used to generate the mesh, (h_min/h)^4"
        if "nominalMinDc" not in dst.variables:
            dst.createVariable("nominalMinDc", "f8", ())
        dst["nominalMinDc"].assignValue(a.fine_km * 1000.0 / EARTH_RADIUS_M)
        dst["nominalMinDc"].long_name = "nominal minimum dcEdge where meshDensity == 1 (unit sphere)"
    print(f"base_mesh.nc sphere_radius = {radius:.1f} m -> {out.name} sphere_radius = 1.0")


def summarize(path: Path, a) -> None:
    with netCDF4.Dataset(path) as ds:
        n_cells = len(ds.dimensions["nCells"])
        n_edges = len(ds.dimensions["nEdges"])
        n_vertices = len(ds.dimensions["nVertices"])
        sides = np.asarray(ds["nEdgesOnCell"][:])
        dc = np.asarray(ds["dcEdge"][:]) * EARTH_RADIUS_M / 1000.0
        lat = np.degrees(np.asarray(ds["latCell"][:]))
        lon = np.degrees(np.asarray(ds["lonCell"][:]))
        area = np.asarray(ds["areaCell"][:])
    shapes = ", ".join(f"{s} sides={c}" for s, c in zip(*np.unique(sides, return_counts=True)))
    r = great_circle_km(lat, lon, a.latitude, a.longitude)
    i = int(np.argmin(r))
    print(f"mesh: {n_cells} cells, {n_edges} edges, {n_vertices} vertices")
    print(f"cell shapes: {shapes}")
    print(f"dcEdge range: {dc.min():.1f} - {dc.max():.1f} km")
    print(f"nearest cell to target: index={i}, distance={r[i]:.1f} km, "
          f"area scale={EARTH_RADIUS_M / 1000.0 * math.sqrt(area[i]):.1f} km")


def main() -> None:
    a = parse_args()
    from mpas_tools.mesh.creation.build_mesh import build_spherical_mesh

    out_dir = a.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    slope = (a.coarse_km - a.fine_km) / a.transition_km
    print(f"target: ({a.latitude}, {a.longitude}), {a.fine_km:g} km within "
          f"{a.fine_radius_km:g} km, {a.coarse_km:g} km beyond "
          f"{a.fine_radius_km + a.transition_km:g} km, transition slope {slope:.3f}")

    lat = np.arange(-90.0, 90.0 + 0.5 * a.step_deg, a.step_deg)
    lon = np.arange(-180.0, 180.0 + 0.5 * a.step_deg, a.step_deg)
    lon2, lat2 = np.meshgrid(lon, lat)
    width = cell_width_km(great_circle_km(lat2, lon2, a.latitude, a.longitude), a)

    cwd = os.getcwd()
    os.chdir(out_dir)
    try:
        start = time.perf_counter()
        build_spherical_mesh(width, lon, lat, earth_radius=EARTH_RADIUS_M,
                             out_filename="base_mesh.nc", plot_cellWidth=False)
        print(f"build_spherical_mesh: {time.perf_counter() - start:.1f} s")
        grid = Path(f"{a.name}.grid.nc")
        to_mpas_atmosphere(Path("base_mesh.nc"), grid, a)
        if Path("graph.info").exists():
            shutil.move("graph.info", f"{a.name}.graph.info")
        summarize(grid, a)
        print(f"wrote {out_dir / grid}")
        print(f"wrote {out_dir / (a.name + '.graph.info')}")
    finally:
        os.chdir(cwd)


if __name__ == "__main__":
    main()
