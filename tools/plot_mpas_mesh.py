#!/usr/bin/env python3
"""Plot a global MPAS mesh overview and a true-cell zoom around a target."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
matplotlib.rcParams["font.sans-serif"] = [
    "WenQuanYi Micro Hei",
    "Droid Sans Fallback",
    "Noto Sans CJK SC",
    "DejaVu Sans",
]
matplotlib.rcParams["axes.unicode_minus"] = False

import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
from matplotlib.lines import Line2D
from matplotlib.patches import Patch
import netCDF4
import numpy as np


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mesh", type=Path, help="MPAS grid file")
    parser.add_argument("--output", type=Path, default=Path("mpas_mesh.png"))
    parser.add_argument("--latitude", type=float, default=39.9042)
    parser.add_argument("--longitude", type=float, default=116.4074)
    parser.add_argument(
        "--zoom-extent",
        nargs=4,
        type=float,
        default=[105.0, 128.0, 31.0, 49.0],
        metavar=("W", "E", "S", "N"),
    )
    return parser.parse_args()


def great_circle_km(
    latitude: np.ndarray, longitude: np.ndarray, target_lat: float, target_lon: float
) -> np.ndarray:
    """Return great-circle distances from cell centers to one target."""

    target_latitude = math.radians(target_lat)
    target_longitude = math.radians(target_lon)
    latitude_delta = latitude - target_latitude
    longitude_delta = (longitude - target_longitude + math.pi) % (
        2.0 * math.pi
    ) - math.pi
    haversine = (
        np.sin(latitude_delta / 2.0) ** 2
        + np.cos(latitude)
        * math.cos(target_latitude)
        * np.sin(longitude_delta / 2.0) ** 2
    )
    return 6371.0 * 2.0 * np.arcsin(np.sqrt(haversine))


def require_variables(dataset: netCDF4.Dataset, names: tuple[str, ...]) -> None:
    missing = [name for name in names if name not in dataset.variables]
    if missing:
        raise ValueError(f"mesh is missing variables: {', '.join(missing)}")


def cell_polygon(
    cell_index: int,
    n_edges_on_cell: np.ndarray,
    vertices_on_cell: np.ndarray,
    vertex_id_to_index: dict[int, int],
    vertex_longitude: np.ndarray,
    vertex_latitude: np.ndarray,
) -> np.ndarray:
    """Return one cell boundary as longitude/latitude degrees.

    MPAS NetCDF connectivity stores global vertex IDs.  The model converts
    them to local positions after reading, but a stand-alone file reader must
    invert indexToVertexID before indexing lonVertex and latVertex.
    """

    edge_count = int(n_edges_on_cell[cell_index])
    if edge_count < 3 or edge_count > vertices_on_cell.shape[1]:
        raise ValueError(f"cell {cell_index} has invalid nEdgesOnCell={edge_count}")
    global_ids = vertices_on_cell[cell_index, :edge_count]
    try:
        positions = np.fromiter(
            (vertex_id_to_index[int(global_id)] for global_id in global_ids),
            dtype=int,
            count=edge_count,
        )
    except KeyError as error:
        raise ValueError(
            f"cell {cell_index} references unknown global vertex ID {error.args[0]}"
        ) from error
    return np.column_stack((vertex_longitude[positions], vertex_latitude[positions]))


def main() -> None:
    args = parse_args()
    if not args.mesh.is_file():
        raise SystemExit(f"mesh file does not exist: {args.mesh}")

    required = (
        "indexToCellID",
        "latCell",
        "lonCell",
        "latVertex",
        "lonVertex",
        "indexToVertexID",
        "nEdgesOnCell",
        "verticesOnCell",
    )
    try:
        with netCDF4.Dataset(args.mesh) as dataset:
            require_variables(dataset, required)
            dimension_counts = {
                name: len(dataset.dimensions[name])
                for name in ("nCells", "nEdges", "nVertices")
            }
            cell_ids = np.asarray(dataset["indexToCellID"][:], dtype=int)
            cell_latitude = np.asarray(dataset["latCell"][:], dtype=float)
            cell_longitude = np.asarray(dataset["lonCell"][:], dtype=float)
            vertex_latitude = np.degrees(
                np.asarray(dataset["latVertex"][:], dtype=float)
            )
            vertex_longitude = (
                np.degrees(np.asarray(dataset["lonVertex"][:], dtype=float)) + 180.0
            ) % 360.0 - 180.0
            vertex_ids = np.asarray(dataset["indexToVertexID"][:], dtype=int)
            n_edges_on_cell = np.asarray(dataset["nEdgesOnCell"][:], dtype=int)
            vertices_on_cell = np.asarray(dataset["verticesOnCell"][:], dtype=int)
    except (OSError, ValueError, KeyError) as error:
        raise SystemExit(f"cannot read {args.mesh}: {error}") from error

    distance = great_circle_km(
        cell_latitude,
        cell_longitude,
        args.latitude,
        args.longitude,
    )
    nearest = int(np.argmin(distance))
    cell_longitude_degrees = (np.degrees(cell_longitude) + 180.0) % 360.0 - 180.0
    cell_latitude_degrees = np.degrees(cell_latitude)

    side_counts, side_populations = np.unique(n_edges_on_cell, return_counts=True)
    shape_summary = dict(zip(side_counts.tolist(), side_populations.tolist()))
    vertex_id_to_index = {
        int(global_id): local_index for local_index, global_id in enumerate(vertex_ids)
    }
    if len(vertex_id_to_index) != len(vertex_ids):
        raise SystemExit("indexToVertexID contains duplicate global vertex IDs")
    side_names = {5: "五边形", 6: "六边形"}
    shape_text = " + ".join(
        f"{population:,} 个{side_names.get(sides, f'{sides} 边形')}"
        for sides, population in sorted(shape_summary.items())
    )

    figure = plt.figure(figsize=(14, 7.2))
    grid = figure.add_gridspec(
        1,
        2,
        width_ratios=(1.15, 1.0),
        left=0.05,
        right=0.98,
        bottom=0.10,
        top=0.82,
        wspace=0.16,
    )

    global_axis = figure.add_subplot(grid[0, 0], projection="mollweide")
    global_axis.set_anchor("N")
    wrapped_longitude = (cell_longitude + math.pi) % (2.0 * math.pi) - math.pi
    six_sided = n_edges_on_cell == 6
    global_axis.scatter(
        wrapped_longitude[six_sided],
        cell_latitude[six_sided],
        s=1.3,
        color="#277da1",
        alpha=0.7,
        linewidths=0,
        rasterized=True,
    )
    non_six_sided = ~six_sided
    global_axis.scatter(
        wrapped_longitude[non_six_sided],
        cell_latitude[non_six_sided],
        s=24,
        color="#f8961e",
        edgecolors="black",
        linewidths=0.35,
        label="非六边形网格单元（cell）",
        zorder=3,
    )
    target_longitude_radians = (math.radians(args.longitude) + math.pi) % (
        2.0 * math.pi
    ) - math.pi
    global_axis.scatter(
        [target_longitude_radians],
        [math.radians(args.latitude)],
        marker="*",
        s=130,
        color="#d62828",
        edgecolors="white",
        linewidths=0.7,
        label="北京",
        zorder=4,
    )
    global_axis.grid(color="0.72", linewidth=0.45, alpha=0.7)
    global_axis.set_title(
        "全球网格单元中心（Mollweide 投影）\n"
        f"共 {dimension_counts['nCells']:,} 个网格单元（cell）：{shape_text}"
    )
    global_axis.legend(loc="lower left", fontsize=8)

    zoom_axis = figure.add_subplot(grid[0, 1])
    west, east, south, north = args.zoom_extent
    if not (west < east and south < north):
        raise SystemExit("--zoom-extent must satisfy W < E and S < N")
    margin = 4.0
    selected = np.flatnonzero(
        (cell_longitude_degrees >= west - margin)
        & (cell_longitude_degrees <= east + margin)
        & (cell_latitude_degrees >= south - margin)
        & (cell_latitude_degrees <= north + margin)
    )
    polygons = [
        cell_polygon(
            index,
            n_edges_on_cell,
            vertices_on_cell,
            vertex_id_to_index,
            vertex_longitude,
            vertex_latitude,
        )
        for index in selected
    ]
    zoom_axis.add_collection(
        PolyCollection(
            polygons,
            facecolors="#d9eef5",
            edgecolors="#277da1",
            linewidths=0.65,
            alpha=0.85,
        )
    )
    nearest_polygon = cell_polygon(
        nearest,
        n_edges_on_cell,
        vertices_on_cell,
        vertex_id_to_index,
        vertex_longitude,
        vertex_latitude,
    )
    zoom_axis.add_collection(
        PolyCollection(
            [nearest_polygon],
            facecolors="#f9c74f",
            edgecolors="#9c5700",
            linewidths=1.6,
            alpha=0.9,
            zorder=3,
        )
    )
    visible_centers = (
        (cell_longitude_degrees >= west)
        & (cell_longitude_degrees <= east)
        & (cell_latitude_degrees >= south)
        & (cell_latitude_degrees <= north)
    )
    zoom_axis.scatter(
        cell_longitude_degrees[visible_centers],
        cell_latitude_degrees[visible_centers],
        s=8,
        color="#17455c",
        linewidths=0,
        zorder=4,
    )
    zoom_axis.plot(
        [args.longitude, cell_longitude_degrees[nearest]],
        [args.latitude, cell_latitude_degrees[nearest]],
        color="#d62828",
        linewidth=1.2,
        linestyle="--",
        zorder=5,
    )
    zoom_axis.scatter(
        [cell_longitude_degrees[nearest]],
        [cell_latitude_degrees[nearest]],
        s=45,
        color="#9c5700",
        edgecolors="white",
        linewidths=0.7,
        zorder=6,
    )
    highlighted_vertex = nearest_polygon[0]
    highlighted_edge = nearest_polygon[:2].mean(axis=0)
    zoom_axis.scatter(
        [highlighted_edge[0]],
        [highlighted_edge[1]],
        marker="s",
        s=42,
        color="#111827",
        edgecolors="white",
        linewidths=0.6,
        zorder=7,
    )
    zoom_axis.scatter(
        [highlighted_vertex[0]],
        [highlighted_vertex[1]],
        marker="^",
        s=52,
        color="#7b2cbf",
        edgecolors="white",
        linewidths=0.6,
        zorder=7,
    )
    zoom_axis.scatter(
        [args.longitude],
        [args.latitude],
        marker="*",
        s=180,
        color="#d62828",
        edgecolors="white",
        linewidths=0.8,
        zorder=7,
    )
    zoom_axis.annotate(
        f"北京距最近网格单元中心：{distance[nearest]:.1f} km",
        xy=(cell_longitude_degrees[nearest], cell_latitude_degrees[nearest]),
        xytext=(0.03, 0.04),
        textcoords="axes fraction",
        fontsize=9,
        bbox={"boxstyle": "round,pad=0.3", "facecolor": "white", "alpha": 0.9},
    )
    zoom_axis.set(
        xlim=(west, east),
        ylim=(south, north),
        xlabel="经度（°E）",
        ylabel="纬度（°N）",
        title=(
            "北京附近的真实 Voronoi 网格单元（cell）\n"
            f"整张网格共有 {dimension_counts['nEdges']:,} 条边（edge）、"
            f"{dimension_counts['nVertices']:,} 个顶点（vertex）"
        ),
    )
    zoom_axis.set_aspect(1.0 / math.cos(math.radians((south + north) / 2.0)))
    zoom_axis.grid(color="0.75", linewidth=0.45, alpha=0.7)
    zoom_axis.legend(
        handles=[
            Patch(
                facecolor="#f9c74f",
                edgecolor="#9c5700",
                label="离北京最近的网格单元",
            ),
            Line2D(
                [0],
                [0],
                marker="o",
                color="none",
                markerfacecolor="#9c5700",
                markeredgecolor="white",
                markersize=7,
                label="网格单元中心",
            ),
            Line2D(
                [0],
                [0],
                marker="s",
                color="none",
                markerfacecolor="#111827",
                markeredgecolor="white",
                markersize=7,
                label="一条边（edge）",
            ),
            Line2D(
                [0],
                [0],
                marker="^",
                color="none",
                markerfacecolor="#7b2cbf",
                markeredgecolor="white",
                markersize=8,
                label="一个顶点（vertex）",
            ),
            Line2D(
                [0],
                [0],
                marker="*",
                color="none",
                markerfacecolor="#d62828",
                markeredgecolor="white",
                markersize=12,
                label="北京",
            ),
        ],
        loc="upper right",
        fontsize=8,
    )

    mesh_label = args.mesh.name.removesuffix(".grid.nc")
    figure.suptitle(f"MPAS 网格：{mesh_label}", fontsize=16, y=0.965)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(args.output, dpi=180)
    plt.close(figure)

    print(
        "mesh: "
        f"{dimension_counts['nCells']} cells, "
        f"{dimension_counts['nEdges']} edges, "
        f"{dimension_counts['nVertices']} vertices"
    )
    print(
        "cell shapes: "
        + ", ".join(
            f"{sides} sides={population}"
            for sides, population in sorted(shape_summary.items())
        )
    )
    print(
        f"nearest target cell: index={nearest}, ID={cell_ids[nearest]}, "
        f"center=({cell_longitude_degrees[nearest]:.4f} E, "
        f"{cell_latitude_degrees[nearest]:.4f} N), "
        f"distance={distance[nearest]:.1f} km"
    )
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
