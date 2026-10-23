#!/usr/bin/env python3
"""Plot the cell spacing of a global variable-resolution MPAS mesh.

Left: every cell centre on a global map, coloured by 6371 km * sqrt(areaCell).
Right: true Voronoi polygons near the target, same colour scale.
Also prints neighbour-to-neighbour size ratios, a quick check that the cell
size changes smoothly.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
matplotlib.rcParams["font.sans-serif"] = [
    "WenQuanYi Micro Hei", "Droid Sans Fallback", "Noto Sans CJK SC", "DejaVu Sans"]
matplotlib.rcParams["axes.unicode_minus"] = False

import matplotlib.pyplot as plt
import netCDF4
import numpy as np
from matplotlib.collections import PolyCollection

from mesh_polygons import great_circle_km, lon_deg, polygons, read_cells


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("mesh", type=Path)
    p.add_argument("--output", type=Path, default=Path("custom_mesh_spacing.png"))
    p.add_argument("--latitude", type=float, default=39.9042)
    p.add_argument("--longitude", type=float, default=116.4074)
    p.add_argument("--zoom-extent", nargs=4, type=float, default=[75.0, 160.0, 5.0, 70.0],
                   metavar=("W", "E", "S", "N"))
    a = p.parse_args()

    cells = read_cells(a.mesh)
    scale = cells["scale"]
    with netCDF4.Dataset(a.mesh) as ds:
        coe = np.asarray(ds["cellsOnEdge"][:]) - 1
    s1, s2 = scale[coe[:, 0]], scale[coe[:, 1]]
    ratio = np.maximum(s1, s2) / np.minimum(s1, s2)
    with netCDF4.Dataset(a.mesh) as ds:
        coc = np.asarray(ds["cellsOnCell"][:]) - 1
    n_edges = cells["n_edges"]
    valid = np.arange(coc.shape[1])[None, :] < n_edges[:, None]
    neighbour_mean = np.where(valid, scale[np.clip(coc, 0, None)], 0.0).sum(1) / n_edges
    rel = scale / neighbour_mean
    print("size relative to neighbours by side count: " + ", ".join(
        f"{k} sides x{rel[n_edges == k].mean():.3f}" for k in np.unique(n_edges)))
    dist = great_circle_km(cells["lat"], cells["lon"], a.latitude, a.longitude)
    i0 = int(np.argmin(dist))
    print(f"cells: {scale.size}, area scale {scale.min():.1f}-{scale.max():.1f} km")
    print(f"neighbour size ratio: median {np.median(ratio):.3f}, "
          f"99th percentile {np.percentile(ratio, 99):.3f}, max {ratio.max():.3f}")
    print(f"nearest cell to target: index={i0}, distance={dist[i0]:.1f} km, "
          f"area scale={scale[i0]:.1f} km")
    for r in (500, 1500, 3000, 5000, 7500):
        ring = np.abs(dist - r) < 150
        print(f"  ~{r:>4d} km from target: mean area scale {scale[ring].mean():.1f} km")

    vmin, vmax = math.floor(scale.min() / 10) * 10, math.ceil(scale.max() / 10) * 10
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(15, 6.2), constrained_layout=True,
                                   gridspec_kw={"width_ratios": [1.45, 1]})
    every = np.arange(scale.size)
    pts = PolyCollection(polygons(cells, every, center_on_180=True), array=scale,
                         cmap="viridis_r", edgecolors="face", linewidths=0.2)
    pts.set_clim(vmin, vmax)
    ax1.add_collection(pts)
    ax1.plot(a.longitude, a.latitude, "r*", ms=12, mec="k")
    ax1.set(xlim=(-180, 180), ylim=(-90, 90), xlabel="经度（°E）", ylabel="纬度（°N）")
    ax1.set_title(f"全球 {scale.size} 个网格单元（颜色＝面积尺度）")
    ax1.grid(alpha=0.25)

    W, E, S, N = a.zoom_extent
    clon = lon_deg(cells["lon"])
    clat = np.degrees(cells["lat"])
    sel = np.where((clon >= W - 3) & (clon <= E + 3) & (clat >= S - 3) & (clat <= N + 3))[0]
    coll = PolyCollection(polygons(cells, sel), array=scale[sel], cmap="viridis_r",
                          edgecolors="0.25", linewidths=0.25)
    coll.set_clim(vmin, vmax)
    ax2.add_collection(coll)
    ax2.plot(a.longitude, a.latitude, "r*", ms=14, mec="k", label="北京")
    ax2.set(xlim=(W, E), ylim=(S, N), xlabel="经度（°E）", ylabel="纬度（°N）")
    ax2.set_aspect(1.0 / math.cos(math.radians(0.5 * (S + N))))
    ax2.set_title("北京附近的真实 Voronoi 网格单元")
    ax2.legend(loc="lower right")
    fig.colorbar(pts, ax=[ax1, ax2], shrink=0.85, label="6371 km × sqrt(areaCell)（km）")
    fig.suptitle(f"自制变分辨率网格：{a.mesh.name}")
    fig.savefig(a.output, dpi=150)
    print(f"wrote {a.output}")


if __name__ == "__main__":
    main()
