#!/usr/bin/env python3
"""Compare a limited-area MPAS diag file with the global run on the same cells.

The regional mesh from create_region renumbers indexToCellID, so cells are
matched by their Cartesian centre (xCell/yCell/zCell) instead of by ID.
"""
import argparse

import netCDF4
import numpy as np


def centres(path):
    with netCDF4.Dataset(path) as ds:
        xyz = np.stack([ds["xCell"][:], ds["yCell"][:], ds["zCell"][:]], axis=1)
        bdy = ds["bdyMaskCell"][:] if "bdyMaskCell" in ds.variables else None
    return xyz / np.linalg.norm(xyz, axis=1, keepdims=True), bdy


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("region_mesh", help="regional grid.nc or static.nc (has bdyMaskCell)")
    p.add_argument("global_mesh", help="global grid.nc the region was cut from")
    p.add_argument("region_diag", help="regional diag.*.nc")
    p.add_argument("global_diag", help="global diag.*.nc at the same time")
    p.add_argument("--fields", default="t2m,mslp")
    p.add_argument("--latitude", type=float, default=39.9042)
    p.add_argument("--longitude", type=float, default=116.4074)
    args = p.parse_args()

    rxyz, bdy = centres(args.region_mesh)
    gxyz, _ = centres(args.global_mesh)
    if bdy is None:
        p.error(f"{args.region_mesh} has no bdyMaskCell")
    match = np.array([np.argmax(gxyz @ c) for c in rxyz])
    offset = np.max(np.linalg.norm(gxyz[match] - rxyz, axis=1)) * 6371.229
    print(f"matched {len(match)} cells, max centre offset {offset:.3f} km")
    lat, lon = np.radians(args.latitude), np.radians(args.longitude)
    target = np.array([np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat)])
    near = int(np.argmax(rxyz @ target))
    with netCDF4.Dataset(args.region_diag) as r, netCDF4.Dataset(args.global_diag) as g:
        for name in args.fields.split(","):
            rv = np.asarray(r[name][0, :], dtype=float)
            gv = np.asarray(g[name][0, :], dtype=float)[match]
            if name == "mslp":
                rv, gv, unit = rv / 100.0, gv / 100.0, "hPa"
            else:
                unit = getattr(r[name], "units", "")
            diff = np.abs(rv - gv)
            print(f"{name} [{unit}]: NaN {int(np.isnan(rv).sum())}, "
                  f"nearest cell region {rv[near]:.2f} global {gv[near]:.2f}; "
                  f"|region-global| interior mean {diff[bdy == 0].mean():.2f} "
                  f"max {diff[bdy == 0].max():.2f}, specified zone mean "
                  f"{diff[bdy >= 6].mean():.2f}")


if __name__ == "__main__":
    main()
