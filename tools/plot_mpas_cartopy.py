#!/usr/bin/env python3
"""Plot MPAS cell diagnostics over East Asia with Cartopy."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cartopy.crs as ccrs
import cartopy.feature as cfeature
import matplotlib.pyplot as plt
import matplotlib.tri as mtri
import netCDF4
import numpy as np

from mpas_io import validate_same_mesh


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "coordinates",
        type=Path,
        help="init/history file containing latCell and lonCell",
    )
    parser.add_argument("diagnostics", type=Path, help="diag file on the same mesh")
    parser.add_argument(
        "--extent",
        nargs=4,
        type=float,
        default=[95, 135, 25, 52],
        metavar=("W", "E", "S", "N"),
    )
    parser.add_argument("--output", type=Path, default=Path("mpas_cartopy.png"))
    return parser.parse_args()


def decode_time(ds: netCDF4.Dataset) -> str:
    return netCDF4.chartostring(ds["xtime"][0]).item().strip()


def main() -> None:
    args = parse_args()
    try:
        with netCDF4.Dataset(args.coordinates) as grid, netCDF4.Dataset(
            args.diagnostics
        ) as ds:
            lineage_available = validate_same_mesh(
                grid, ds, args.coordinates, args.diagnostics
            )
            missing_coordinates = [
                name for name in ("latCell", "lonCell") if name not in grid.variables
            ]
            missing_diagnostics = [
                name
                for name in ("xtime", "t2m", "mslp", "u10", "v10")
                if name not in ds.variables
            ]
            if missing_coordinates:
                raise ValueError(
                    f"{args.coordinates} is missing variables: {', '.join(missing_coordinates)}"
                )
            if missing_diagnostics:
                raise ValueError(
                    f"{args.diagnostics} is missing variables: {', '.join(missing_diagnostics)}"
                )
            lon = (np.degrees(np.asarray(grid["lonCell"][:])) + 180.0) % 360.0 - 180.0
            lat = np.degrees(np.asarray(grid["latCell"][:]))
            t2m = np.asarray(ds["t2m"][0]) - 273.15
            mslp = np.asarray(ds["mslp"][0]) / 100.0
            u10 = np.asarray(ds["u10"][0])
            v10 = np.asarray(ds["v10"][0])
            valid_time = decode_time(ds)
    except (OSError, ValueError) as error:
        raise SystemExit(f"Cannot plot these MPAS files safely: {error}") from error
    if not lineage_available:
        print(
            "WARNING: file_id/parent_id metadata was unavailable; mesh validation used nCells only.",
            file=sys.stderr,
        )

    west, east, south, north = args.extent
    # Include a halo outside the plotted extent so contours reach the frame.
    keep = (
        (lon >= west - 5) & (lon <= east + 5) & (lat >= south - 5) & (lat <= north + 5)
    )
    x, y = lon[keep], lat[keep]
    triangulation = mtri.Triangulation(x, y)
    triangles = triangulation.triangles
    max_span = np.maximum.reduce(
        [
            np.abs(x[triangles[:, 0]] - x[triangles[:, 1]]),
            np.abs(x[triangles[:, 1]] - x[triangles[:, 2]]),
            np.abs(x[triangles[:, 2]] - x[triangles[:, 0]]),
        ]
    )
    triangulation.set_mask(max_span > 6.0)

    projection = ccrs.LambertConformal(central_longitude=115, central_latitude=38)
    data_crs = ccrs.PlateCarree()
    fig, ax = plt.subplots(
        figsize=(11, 8), subplot_kw={"projection": projection}, constrained_layout=True
    )
    ax.set_extent(args.extent, crs=data_crs)
    levels = np.arange(-12, 25, 2)
    filled = ax.tricontourf(
        triangulation,
        t2m[keep],
        levels=levels,
        cmap="coolwarm",
        extend="both",
        transform=data_crs,
    )
    pressure_levels = np.arange(980, 1041, 4)
    contours = ax.tricontour(
        triangulation,
        mslp[keep],
        levels=pressure_levels,
        colors="black",
        linewidths=0.65,
        transform=data_crs,
    )
    ax.clabel(contours, fmt="%d", fontsize=7)

    indices = np.flatnonzero(keep)[:: max(1, int(keep.sum() / 350))]
    wind_vectors = ax.quiver(
        lon[indices],
        lat[indices],
        u10[indices],
        v10[indices],
        transform=data_crs,
        regrid_shape=18,
        color="0.15",
        scale=220,
        width=0.0022,
    )
    ax.quiverkey(
        wind_vectors,
        X=0.80,
        Y=0.04,
        U=10,
        label="10 m s⁻¹",
        labelpos="E",
        coordinates="axes",
        fontproperties={"size": 8},
    )
    ax.add_feature(cfeature.LAND, facecolor="none", edgecolor="none")
    ax.coastlines(resolution="50m", linewidth=0.8)
    ax.add_feature(cfeature.BORDERS.with_scale("50m"), linewidth=0.55)
    gridlines = ax.gridlines(
        draw_labels=True, linewidth=0.35, color="gray", alpha=0.6, linestyle="--"
    )
    gridlines.top_labels = False
    gridlines.right_labels = False
    ax.scatter(
        116.4074,
        39.9042,
        marker="*",
        s=130,
        color="gold",
        edgecolor="black",
        transform=data_crs,
        zorder=5,
    )
    ax.set_title(f"MPAS-A 2-m temperature, MSLP and 10-m wind\nValid {valid_time} UTC")
    fig.colorbar(
        filled,
        ax=ax,
        orientation="horizontal",
        pad=0.06,
        shrink=0.82,
        label="2-m temperature (°C)",
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output, dpi=180)
    print(f"plotted {keep.sum()} cells; wrote {args.output}")


if __name__ == "__main__":
    main()
