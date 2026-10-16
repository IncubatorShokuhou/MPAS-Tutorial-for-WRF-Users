#!/usr/bin/env python3
"""Extract and plot a nearest-cell Beijing time series from MPAS diagnostics."""

from __future__ import annotations

import argparse
import csv
import math
import sys
from datetime import datetime, timedelta
from pathlib import Path

import matplotlib.pyplot as plt
import netCDF4
import numpy as np

from mpas_io import validate_same_mesh

TIME_FORMAT = "%Y-%m-%d_%H:%M:%S"
PRECIPITATION_COMPONENTS = ("rainc", "rainnc")


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case_dir", type=Path)
    parser.add_argument(
        "--grid-file",
        type=Path,
        help="coordinate/init file; relative paths are resolved inside CASE_DIR",
    )
    parser.add_argument("--diagnostics-glob", default="diag.*.nc")
    parser.add_argument("--expected-interval-hours", type=float, default=3.0)
    parser.add_argument("--latitude", type=float, default=39.9042)
    parser.add_argument("--longitude", type=float, default=116.4074)
    parser.add_argument("--output-prefix", default="beijing_nearest_cell")
    return parser.parse_args()


def great_circle_km(
    lat: np.ndarray, lon: np.ndarray, lat0: float, lon0: float
) -> np.ndarray:
    dlat = lat - math.radians(lat0)
    dlon = (lon - math.radians(lon0) + math.pi) % (2.0 * math.pi) - math.pi
    a = (
        np.sin(dlat / 2.0) ** 2
        + np.cos(lat) * math.cos(math.radians(lat0)) * np.sin(dlon / 2.0) ** 2
    )
    return 6371.0 * 2.0 * np.arcsin(np.sqrt(a))


def read_text_variable(
    dataset: netCDF4.Dataset, name: str, index: int | None = None
) -> str:
    if name not in dataset.variables:
        raise ValueError(f"missing required variable {name}")
    decoded = np.asarray(netCDF4.chartostring(dataset.variables[name][:]))
    if index is not None and decoded.ndim:
        decoded = decoded[index]
    if decoded.size != 1:
        raise ValueError(f"{name} contains {decoded.size} strings; expected one")
    return str(decoded.item()).strip()


def parse_time(value: str, source: Path) -> datetime:
    try:
        return datetime.strptime(value, TIME_FORMAT)
    except ValueError as error:
        raise ValueError(f"invalid MPAS time {value!r} in {source}") from error


def validate_time_continuity(
    valid_time: datetime,
    previous_time: datetime | None,
    initial_time: datetime,
    expected_interval: timedelta,
    source: Path,
) -> None:
    if previous_time is None:
        if valid_time != initial_time:
            raise ValueError(
                f"first diagnostics time is {valid_time.strftime(TIME_FORMAT)}, not "
                f"initialization time {initial_time.strftime(TIME_FORMAT)}; the series is incomplete"
            )
    elif valid_time - previous_time != expected_interval:
        raise ValueError(
            f"time discontinuity at {source}: expected "
            f"{(previous_time + expected_interval).strftime(TIME_FORMAT)}, "
            f"got {valid_time.strftime(TIME_FORMAT)}"
        )


def find_grid_file(case_dir: Path, requested: Path | None) -> Path:
    if requested is not None:
        candidate = requested if requested.is_absolute() else case_dir / requested
        if not candidate.is_file():
            raise SystemExit(f"Grid/coordinate file does not exist: {candidate}")
        return candidate

    candidates = sorted(case_dir.glob("*.init.nc"))
    if not candidates:
        raise SystemExit(
            f"No *.init.nc coordinate file found in {case_dir}; run init_atmosphere "
            "or pass --grid-file PATH"
        )
    if len(candidates) > 1:
        names = ", ".join(path.name for path in candidates)
        raise SystemExit(
            f"Multiple init files found ({names}); select one with --grid-file"
        )
    return candidates[0]


def require_variables(
    dataset: netCDF4.Dataset, names: tuple[str, ...], source: Path
) -> None:
    missing = [name for name in names if name not in dataset.variables]
    if missing:
        raise ValueError(f"{source} is missing variables: {', '.join(missing)}")


def precipitation_components(
    dataset: netCDF4.Dataset, cell_index: int
) -> tuple[dict[str, float], set[str]]:
    """Return bucket-corrected cumulative rain and components without counters."""

    totals: dict[str, float] = {}
    missing_counters: set[str] = set()
    for name in PRECIPITATION_COMPONENTS:
        raw = float(dataset.variables[name][0, cell_index])
        counter_name = f"i_{name}"
        if counter_name in dataset.variables:
            attribute_name = f"config_bucket_{name}"
            if attribute_name not in dataset.ncattrs():
                raise ValueError(
                    f"{counter_name} is present but global attribute {attribute_name} is missing"
                )
            bucket = float(dataset.getncattr(attribute_name))
            if bucket <= 0.0:
                raise ValueError(f"{attribute_name} must be positive, got {bucket}")
            counter = int(dataset.variables[counter_name][0, cell_index])
            if counter < 0:
                raise ValueError(f"{counter_name} must be non-negative, got {counter}")
            totals[name] = raw + bucket * counter
        else:
            totals[name] = raw
            missing_counters.add(name)
    return totals, missing_counters


def precipitation_increment(
    current: dict[str, float], previous: dict[str, float], source: Path
) -> float:
    increments: list[float] = []
    for name in PRECIPITATION_COMPONENTS:
        difference = current[name] - previous[name]
        if difference < 0.0:
            raise ValueError(
                f"{name} decreased by {-difference:.6g} mm at {source}; this can mean "
                "a precipitation-bucket rollover, a restart, or out-of-order input. "
                f"Include i_{name} in diagnostics or analyze continuous output."
            )
        increments.append(difference)
    return sum(increments)


def main() -> None:
    args = arguments()
    if not args.case_dir.is_dir():
        raise SystemExit(f"Case directory does not exist: {args.case_dir}")
    if args.expected_interval_hours <= 0.0:
        raise SystemExit("--expected-interval-hours must be greater than zero")

    grid_file = find_grid_file(args.case_dir, args.grid_file)
    diag_files = sorted(args.case_dir.glob(args.diagnostics_glob))
    if not diag_files:
        raise SystemExit(
            f"No diagnostics match {args.diagnostics_glob!r} in {args.case_dir}; "
            "finish the MPAS forecast first"
        )

    try:
        with netCDF4.Dataset(grid_file) as grid:
            require_variables(grid, ("latCell", "lonCell", "indexToCellID"), grid_file)
            lat = np.asarray(grid.variables["latCell"][:])
            lon = np.asarray(grid.variables["lonCell"][:])
            cell_ids = np.asarray(grid.variables["indexToCellID"][:])
            grid_initial_time = read_text_variable(grid, "initial_time")
    except (OSError, ValueError) as error:
        raise SystemExit(f"Cannot read coordinate file: {error}") from error

    distance = great_circle_km(lat, lon, args.latitude, args.longitude)
    index = int(np.argmin(distance))
    expected_interval = timedelta(hours=args.expected_interval_hours)
    expected_initial = parse_time(grid_initial_time, grid_file)

    rows: list[dict[str, float | int | str | None]] = []
    previous_precipitation: dict[str, float] | None = None
    previous_time: datetime | None = None
    components_without_counters: set[str] = set()
    lineage_unavailable = False

    for filename in diag_files:
        try:
            with netCDF4.Dataset(grid_file) as grid, netCDF4.Dataset(
                filename
            ) as dataset:
                lineage_unavailable |= not validate_same_mesh(
                    grid, dataset, grid_file, filename
                )
                require_variables(
                    dataset,
                    (
                        "xtime",
                        "initial_time",
                        "rainc",
                        "rainnc",
                        "u10",
                        "v10",
                        "t2m",
                        "mslp",
                    ),
                    filename,
                )
                if "Time" not in dataset.dimensions:
                    raise ValueError(f"{filename} has no Time dimension")
                if len(dataset.dimensions["Time"]) != 1:
                    raise ValueError(
                        f"{filename} contains {len(dataset.dimensions['Time'])} records; "
                        "this script expects one record per diagnostics file"
                    )
                valid_time_text = read_text_variable(dataset, "xtime", 0)
                valid_time = parse_time(valid_time_text, filename)
                initial_time_text = read_text_variable(dataset, "initial_time")
                if parse_time(initial_time_text, filename) != expected_initial:
                    raise ValueError(
                        f"initial_time changed from {grid_initial_time} to {initial_time_text} "
                        f"in {filename}; do not join separate cold starts"
                    )
                validate_time_continuity(
                    valid_time,
                    previous_time,
                    expected_initial,
                    expected_interval,
                    filename,
                )

                current_precipitation, missing = precipitation_components(
                    dataset, index
                )
                components_without_counters.update(missing)
                increment = None
                if previous_precipitation is not None:
                    increment = precipitation_increment(
                        current_precipitation, previous_precipitation, filename
                    )
                previous_precipitation = current_precipitation
                previous_time = valid_time

                u10 = float(dataset.variables["u10"][0, index])
                v10 = float(dataset.variables["v10"][0, index])
                rows.append(
                    {
                        "time_utc": valid_time_text,
                        "cell_index_zero_based": index,
                        "cell_id_one_based": int(cell_ids[index]),
                        "cell_latitude_deg": math.degrees(float(lat[index])),
                        "cell_longitude_deg": math.degrees(float(lon[index])),
                        "distance_to_beijing_km": float(distance[index]),
                        "t2m_c": float(dataset.variables["t2m"][0, index]) - 273.15,
                        "u10_m_s": u10,
                        "v10_m_s": v10,
                        "wind10_m_s": math.hypot(u10, v10),
                        "precip_accum_mm": sum(current_precipitation.values()),
                        "precip_since_previous_output_mm": increment,
                        "mslp_hpa": float(dataset.variables["mslp"][0, index]) / 100.0,
                    }
                )
        except (OSError, ValueError, IndexError) as error:
            raise SystemExit(f"Cannot safely analyze {filename}: {error}") from error

    if lineage_unavailable:
        print(
            "WARNING: file_id/parent_id metadata was unavailable; mesh validation used nCells only.",
            file=sys.stderr,
        )
    if components_without_counters:
        names = ", ".join(f"i_{name}" for name in sorted(components_without_counters))
        print(
            f"WARNING: diagnostics omit {names}; any detected bucket rollover will stop the analysis.",
            file=sys.stderr,
        )

    csv_path = args.case_dir / f"{args.output_prefix}.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    times = [str(row["time_utc"])[5:16].replace("_", " ") for row in rows]
    increments = [
        (
            np.nan
            if row["precip_since_previous_output_mm"] is None
            else row["precip_since_previous_output_mm"]
        )
        for row in rows
    ]
    fig, axes = plt.subplots(
        3, 1, figsize=(10, 9), sharex=True, constrained_layout=True
    )
    axes[0].plot(times, [row["t2m_c"] for row in rows], marker="o")
    axes[0].set_ylabel("2-m temperature (°C)")
    axes[1].plot(
        times, [row["wind10_m_s"] for row in rows], marker="o", color="tab:green"
    )
    axes[1].set_ylabel("10-m wind (m s⁻¹)")
    axes[2].bar(times, increments, color="tab:blue")
    axes[2].set_ylabel("Precipitation since previous output (mm)")
    axes[2].tick_params(axis="x", rotation=35)
    fig.suptitle(
        f"Nearest MPAS cell to Beijing: {rows[0]['cell_latitude_deg']:.2f}°N, "
        f"{rows[0]['cell_longitude_deg']:.2f}°E ({rows[0]['distance_to_beijing_km']:.1f} km away)"
    )
    png_path = args.case_dir / f"{args.output_prefix}.png"
    fig.savefig(png_path, dpi=160)
    print(
        f"cell index={index}, cell ID={cell_ids[index]}, distance={distance[index]:.1f} km"
    )
    print(f"wrote {csv_path}")
    print(f"wrote {png_path}")


if __name__ == "__main__":
    main()
