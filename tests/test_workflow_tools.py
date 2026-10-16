#!/usr/bin/env python3
"""Lightweight regression tests for tutorial workflow scripts."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

import netCDF4

ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault("MPLBACKEND", "Agg")
sys.path.insert(0, str(ROOT / "tools"))

from analyze_beijing import (  # noqa: E402
    precipitation_components,
    precipitation_increment,
    validate_time_continuity,
)
from mpas_io import validate_same_mesh  # noqa: E402


def make_netcdf(
    path: Path,
    cells: int,
    *,
    file_id: str | None = None,
    parent_id: str | None = None,
) -> None:
    with netCDF4.Dataset(path, "w") as dataset:
        dataset.createDimension("nCells", cells)
        if file_id is not None:
            dataset.file_id = file_id
        if parent_id is not None:
            dataset.parent_id = parent_id


class MeshValidationTests(unittest.TestCase):
    def test_coordinate_file_is_diagnostic_ancestor(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            coordinate_path = Path(directory) / "init.nc"
            diagnostic_path = Path(directory) / "diag.nc"
            make_netcdf(coordinate_path, 4, file_id="init-id", parent_id="grid-id\n")
            make_netcdf(
                diagnostic_path, 4, file_id="diag-id", parent_id="init-id\ngrid-id\n"
            )
            with netCDF4.Dataset(coordinate_path) as coordinates, netCDF4.Dataset(
                diagnostic_path
            ) as diagnostics:
                self.assertTrue(
                    validate_same_mesh(
                        coordinates, diagnostics, coordinate_path, diagnostic_path
                    )
                )

    def test_sibling_outputs_share_nearest_parent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            history_path = Path(directory) / "history.nc"
            diagnostic_path = Path(directory) / "diag.nc"
            make_netcdf(
                history_path, 4, file_id="history-id", parent_id="init-id\ngrid-id\n"
            )
            make_netcdf(
                diagnostic_path, 4, file_id="diag-id", parent_id="init-id\ngrid-id\n"
            )
            with netCDF4.Dataset(history_path) as history, netCDF4.Dataset(
                diagnostic_path
            ) as diagnostics:
                self.assertTrue(
                    validate_same_mesh(
                        history, diagnostics, history_path, diagnostic_path
                    )
                )

    def test_unrelated_lineages_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            coordinate_path = Path(directory) / "init.nc"
            diagnostic_path = Path(directory) / "diag.nc"
            make_netcdf(coordinate_path, 4, file_id="init-a", parent_id="grid-a\n")
            make_netcdf(
                diagnostic_path, 4, file_id="diag-b", parent_id="init-b\ngrid-b\n"
            )
            with netCDF4.Dataset(coordinate_path) as coordinates, netCDF4.Dataset(
                diagnostic_path
            ) as diagnostics:
                with self.assertRaisesRegex(ValueError, "lineage mismatch"):
                    validate_same_mesh(
                        coordinates, diagnostics, coordinate_path, diagnostic_path
                    )

    def test_different_cell_counts_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            coordinate_path = Path(directory) / "init.nc"
            diagnostic_path = Path(directory) / "diag.nc"
            make_netcdf(coordinate_path, 4)
            make_netcdf(diagnostic_path, 5)
            with netCDF4.Dataset(coordinate_path) as coordinates, netCDF4.Dataset(
                diagnostic_path
            ) as diagnostics:
                with self.assertRaisesRegex(ValueError, "mesh mismatch"):
                    validate_same_mesh(
                        coordinates, diagnostics, coordinate_path, diagnostic_path
                    )


class PrecipitationTests(unittest.TestCase):
    def test_bucket_counters_reconstruct_cumulative_precipitation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "diag.nc"
            with netCDF4.Dataset(path, "w") as dataset:
                dataset.createDimension("Time", 1)
                dataset.createDimension("nCells", 1)
                for name, value in (("rainc", 5.0), ("rainnc", 2.0)):
                    variable = dataset.createVariable(name, "f8", ("Time", "nCells"))
                    variable[0, 0] = value
                for name, value in (("i_rainc", 2), ("i_rainnc", 1)):
                    variable = dataset.createVariable(name, "i4", ("Time", "nCells"))
                    variable[0, 0] = value
                dataset.config_bucket_rainc = 100.0
                dataset.config_bucket_rainnc = 50.0

            with netCDF4.Dataset(path) as dataset:
                totals, missing = precipitation_components(dataset, 0)
            self.assertEqual(totals, {"rainc": 205.0, "rainnc": 52.0})
            self.assertEqual(missing, set())

    def test_negative_increment_is_not_silently_clipped(self) -> None:
        previous = {"rainc": 99.0, "rainnc": 2.0}
        current = {"rainc": 1.0, "rainnc": 3.0}
        with self.assertRaisesRegex(ValueError, "bucket rollover"):
            precipitation_increment(current, previous, Path("diag.nc"))

    def test_positive_component_increments_are_summed(self) -> None:
        previous = {"rainc": 1.0, "rainnc": 2.0}
        current = {"rainc": 1.5, "rainnc": 4.0}
        self.assertEqual(
            precipitation_increment(current, previous, Path("diag.nc")), 2.5
        )


class TimeContinuityTests(unittest.TestCase):
    def test_expected_step_is_accepted(self) -> None:
        initial = datetime(2026, 10, 15, 0)
        validate_time_continuity(
            initial, None, initial, timedelta(hours=3), Path("diag-00.nc")
        )
        validate_time_continuity(
            initial + timedelta(hours=3),
            initial,
            initial,
            timedelta(hours=3),
            Path("diag-03.nc"),
        )

    def test_missing_output_is_rejected(self) -> None:
        initial = datetime(2026, 10, 15, 0)
        with self.assertRaisesRegex(ValueError, "time discontinuity"):
            validate_time_continuity(
                initial + timedelta(hours=6),
                initial,
                initial,
                timedelta(hours=3),
                Path("diag-06.nc"),
            )


class ShellInterfaceTests(unittest.TestCase):
    def test_shell_syntax(self) -> None:
        scripts = [
            ROOT / "install_wps.sh",
            ROOT / "prepare_beijing_case.sh",
            ROOT / "prepare_beijing_vr_mesh.sh",
            ROOT / "run_beijing_case.sh",
        ]
        subprocess.run(["bash", "-n", *map(str, scripts)], check=True)

    def test_help_documents_reproducibility_options(self) -> None:
        checks = {
            "prepare_beijing_case.sh": "--wps-geog",
            "prepare_beijing_vr_mesh.sh": "--mpas-tools-revision",
            "run_beijing_case.sh": "case.env",
        }
        for script, expected in checks.items():
            with self.subTest(script=script):
                result = subprocess.run(
                    [str(ROOT / script), "--help"],
                    check=True,
                    text=True,
                    stdout=subprocess.PIPE,
                )
                self.assertIn(expected, result.stdout)

    def test_wps_defaults_to_unified_io_stack(self) -> None:
        source = (ROOT / "install_wps.sh").read_text(encoding="utf-8")
        self.assertIn('MPI_PREFIX="$SCRIPT_DIR/local/io-stack"', source)
        self.assertIn('NETCDF_PREFIX="$SCRIPT_DIR/local/io-stack"', source)


if __name__ == "__main__":
    unittest.main()
