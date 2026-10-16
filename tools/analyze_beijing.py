#!/usr/bin/env python3
"""Extract and plot a nearest-cell Beijing time series from MPAS diagnostics."""

from __future__ import annotations

import argparse
import csv
import glob
import math
from pathlib import Path

import matplotlib.pyplot as plt
import netCDF4
import numpy as np


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case_dir", type=Path)
    parser.add_argument("--latitude", type=float, default=39.9042)
    parser.add_argument("--longitude", type=float, default=116.4074)
    parser.add_argument("--output-prefix", default="beijing_nearest_cell")
    return parser.parse_args()


def great_circle_km(lat: np.ndarray, lon: np.ndarray, lat0: float, lon0: float) -> np.ndarray:
    dlat = lat - math.radians(lat0)
    dlon = (lon - math.radians(lon0) + math.pi) % (2.0 * math.pi) - math.pi
    a = np.sin(dlat / 2.0) ** 2 + np.cos(lat) * math.cos(math.radians(lat0)) * np.sin(dlon / 2.0) ** 2
    return 6371.0 * 2.0 * np.arcsin(np.sqrt(a))


def read_time(dataset: netCDF4.Dataset) -> str:
    chars = dataset.variables["xtime"][0]
    if chars.dtype.kind == "S":
        return netCDF4.chartostring(chars).item().strip()
    return "".join(str(x) for x in chars).strip()


def main() -> None:
    args = arguments()
    init_file = args.case_dir / "x1.10242.init.nc"
    diag_files = sorted(glob.glob(str(args.case_dir / "diag.*.nc")))
    if not init_file.is_file() or not diag_files:
        raise SystemExit("Missing init.nc or diag files; finish lessons 4 and 5 first")

    with netCDF4.Dataset(init_file) as ds:
        lat = np.asarray(ds.variables["latCell"][:])
        lon = np.asarray(ds.variables["lonCell"][:])
        cell_ids = np.asarray(ds.variables["indexToCellID"][:])
    distance = great_circle_km(lat, lon, args.latitude, args.longitude)
    index = int(np.argmin(distance))

    rows: list[dict[str, float | int | str]] = []
    previous_accum = None
    for filename in diag_files:
        with netCDF4.Dataset(filename) as ds:
            rainc = float(ds.variables["rainc"][0, index])
            rainnc = float(ds.variables["rainnc"][0, index])
            accum = rainc + rainnc
            if abs(accum) < 1.0e-9:
                accum = 0.0
            increment = 0.0 if previous_accum is None else max(0.0, accum - previous_accum)
            previous_accum = accum
            u10 = float(ds.variables["u10"][0, index])
            v10 = float(ds.variables["v10"][0, index])
            rows.append(
                {
                    "time_utc": read_time(ds),
                    "cell_index_zero_based": index,
                    "cell_id_one_based": int(cell_ids[index]),
                    "cell_latitude_deg": math.degrees(float(lat[index])),
                    "cell_longitude_deg": math.degrees(float(lon[index])),
                    "distance_to_beijing_km": float(distance[index]),
                    "t2m_c": float(ds.variables["t2m"][0, index]) - 273.15,
                    "u10_m_s": u10,
                    "v10_m_s": v10,
                    "wind10_m_s": math.hypot(u10, v10),
                    "precip_accum_mm": accum,
                    "precip_since_previous_output_mm": increment,
                    "mslp_hpa": float(ds.variables["mslp"][0, index]) / 100.0,
                }
            )

    csv_path = args.case_dir / f"{args.output_prefix}.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    times = [row["time_utc"][5:16].replace("_", " ") for row in rows]
    fig, axes = plt.subplots(3, 1, figsize=(10, 9), sharex=True, constrained_layout=True)
    axes[0].plot(times, [row["t2m_c"] for row in rows], marker="o")
    axes[0].set_ylabel("2-m temperature (°C)")
    axes[1].plot(times, [row["wind10_m_s"] for row in rows], marker="o", color="tab:green")
    axes[1].set_ylabel("10-m wind (m s⁻¹)")
    axes[2].bar(times, [row["precip_since_previous_output_mm"] for row in rows], color="tab:blue")
    axes[2].set_ylabel("3-h precipitation (mm)")
    axes[2].tick_params(axis="x", rotation=35)
    fig.suptitle(
        f"Nearest MPAS cell to Beijing: {rows[0]['cell_latitude_deg']:.2f}°N, "
        f"{rows[0]['cell_longitude_deg']:.2f}°E ({rows[0]['distance_to_beijing_km']:.1f} km away)"
    )
    png_path = args.case_dir / f"{args.output_prefix}.png"
    fig.savefig(png_path, dpi=160)
    print(f"cell index={index}, cell ID={cell_ids[index]}, distance={distance[index]:.1f} km")
    print(f"wrote {csv_path}")
    print(f"wrote {png_path}")


if __name__ == "__main__":
    main()
