#!/usr/bin/env python3
"""Plot a limited-area MPAS mesh made by create_region.

Left: true cell polygons coloured by bdyMaskCell (0 interior, 1-5 relaxation
zone, 6-7 specified zone). Right (optional): terrain height `ter` from a
regional static.nc cut from the same global mesh.
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
from matplotlib.colors import BoundaryNorm, ListedColormap
from matplotlib.patches import Patch

from mesh_polygons import lon_deg, polygons, read_cells


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("mesh", type=Path, help="regional grid.nc or static.nc")
    p.add_argument("--static", type=Path, help="regional static.nc for the terrain panel")
    p.add_argument("--output", type=Path, default=Path("region_mesh.png"))
    p.add_argument("--latitude", type=float, default=39.9042)
    p.add_argument("--longitude", type=float, default=116.4074)
    a = p.parse_args()

    cells = read_cells(a.mesh)
    mask = cells["mask"]
    if mask is None:
        raise SystemExit(f"{a.mesh} has no bdyMaskCell; is it a regional mesh?")
    index = np.arange(mask.size)
    polys = polygons(cells, index)
    allxy = np.vstack(polys)
    W, E = allxy[:, 0].min() - 2, allxy[:, 0].max() + 2
    S, N = allxy[:, 1].min() - 2, allxy[:, 1].max() + 2

    panels = 2 if a.static else 1
    fig, axes = plt.subplots(1, panels, figsize=(7.2 * panels, 6.4), constrained_layout=True,
                             squeeze=False)
    ax = axes[0, 0]
    zone = np.where(mask == 0, 0, np.where(mask <= 5, 1, 2))
    cmap = ListedColormap(["#d9ecf7", "#f6c76b", "#d6604d"])
    coll = PolyCollection(polys, array=zone, cmap=cmap,
                          norm=BoundaryNorm([-0.5, 0.5, 1.5, 2.5], 3),
                          edgecolors="0.35", linewidths=0.3)
    ax.add_collection(coll)
    ax.plot(a.longitude, a.latitude, "r*", ms=14, mec="k")
    counts = [int((zone == k).sum()) for k in range(3)]
    ax.legend(handles=[
        Patch(color=cmap(0), label=f"内部（bdyMaskCell=0）：{counts[0]}"),
        Patch(color=cmap(1), label=f"松弛区（1–5）：{counts[1]}"),
        Patch(color=cmap(2), label=f"指定区（6–7）：{counts[2]}")], loc="lower left", fontsize=9)
    ax.set_title(f"{a.mesh.name}：{mask.size} 个网格单元")

    if a.static:
        with netCDF4.Dataset(a.static) as ds:
            ter = np.asarray(ds["ter"][:])
            land = np.asarray(ds["landmask"][:]) == 1
        ax2 = axes[0, 1]
        land_cmap = ListedColormap(plt.get_cmap("terrain")(np.linspace(0.25, 1.0, 192)))
        tc = PolyCollection([polys[i] for i in np.where(land)[0]], array=ter[land],
                            cmap=land_cmap, edgecolors="0.4", linewidths=0.2)
        tc.set_clim(0, max(1.0, float(ter.max())))
        ax2.add_collection(tc)
        ax2.add_collection(PolyCollection([polys[i] for i in np.where(~land)[0]],
                                          facecolors="#9ecae1", edgecolors="0.4",
                                          linewidths=0.2))
        ax2.legend(handles=[Patch(color="#9ecae1", label="水体（landmask=0）")],
                   loc="lower left", fontsize=9)
        ax2.plot(a.longitude, a.latitude, "r*", ms=14, mec="k")
        ax2.set_title(f"{a.static.name}：地形高度 ter")
        fig.colorbar(tc, ax=ax2, shrink=0.8, label="ter（m）")

    for axis in axes.ravel():
        axis.set(xlim=(W, E), ylim=(S, N), xlabel="经度（°E）", ylabel="纬度（°N）")
        axis.set_aspect(1.0 / math.cos(math.radians(0.5 * (S + N))))
        axis.grid(alpha=0.25)
    fig.savefig(a.output, dpi=150)
    print(f"cells: {mask.size}; interior={counts[0]}, relaxation={counts[1]}, specified={counts[2]}")
    print(f"wrote {a.output}")


if __name__ == "__main__":
    main()
