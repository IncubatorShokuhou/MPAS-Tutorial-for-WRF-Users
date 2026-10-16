#!/usr/bin/env python3
"""Plot MPAS cell-area scale over a longitude/latitude window."""

from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import netCDF4
import numpy as np


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mesh", type=Path)
    parser.add_argument("--extent", nargs=4, type=float, default=[70, 145, 15, 60], metavar=("W", "E", "S", "N"))
    parser.add_argument("--output", type=Path, default=Path("beijing_mesh_resolution.png"))
    args = parser.parse_args()
    with netCDF4.Dataset(args.mesh) as ds:
        lon = np.degrees(np.asarray(ds["lonCell"][:]))
        lat = np.degrees(np.asarray(ds["latCell"][:]))
        scale = 6371.0 * np.sqrt(np.asarray(ds["areaCell"][:]))
    lon = (lon + 180.0) % 360.0 - 180.0
    west, east, south, north = args.extent
    selected = (lon >= west) & (lon <= east) & (lat >= south) & (lat <= north)
    fig, ax = plt.subplots(figsize=(10, 7), constrained_layout=True)
    points = ax.scatter(lon[selected], lat[selected], c=scale[selected], s=2, cmap="viridis", vmin=20, vmax=95)
    ax.scatter([116.4074], [39.9042], marker="*", s=130, color="red", edgecolor="black", label="Beijing")
    ax.set(xlim=(west, east), ylim=(south, north), xlabel="Longitude (°E)", ylabel="Latitude (°N)")
    ax.set_title("MPAS 92–25 km variable-resolution mesh (cell-area scale)")
    ax.grid(alpha=0.2)
    ax.legend()
    fig.colorbar(points, ax=ax, label="6371 × sqrt(areaCell) (km)")
    fig.savefig(args.output, dpi=180)
    print(f"selected {selected.sum()} of {len(lat)} cells; wrote {args.output}")


if __name__ == "__main__":
    main()
