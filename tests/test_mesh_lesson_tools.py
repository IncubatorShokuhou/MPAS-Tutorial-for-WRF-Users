#!/usr/bin/env python3
"""Regression checks for the lesson-9 mesh helpers (no JIGSAW needed)."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

import netCDF4
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from make_custom_mesh import (  # noqa: E402
    EARTH_RADIUS_M,
    cell_width_km,
    great_circle_km,
    to_mpas_atmosphere,
)

ARGS = Namespace(latitude=39.9042, longitude=116.4074, fine_km=60.0, coarse_km=240.0,
                 fine_radius_km=1500.0, transition_km=6000.0)


class CellWidthTests(unittest.TestCase):
    def test_profile_limits_and_slope(self) -> None:
        r = np.array([0.0, 1500.0, 4500.0, 7500.0, 15000.0])
        np.testing.assert_allclose(cell_width_km(r, ARGS), [60, 60, 150, 240, 240])

    def test_distance_to_self_is_zero(self) -> None:
        d = great_circle_km(np.array([39.9042]), np.array([116.4074]), 39.9042, 116.4074)
        self.assertLess(float(d[0]), 1e-6)


class UnitSphereTests(unittest.TestCase):
    def test_scaling_and_density(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base, grid = Path(tmp) / "base_mesh.nc", Path(tmp) / "test.grid.nc"
            with netCDF4.Dataset(base, "w") as ds:
                ds.sphere_radius = EARTH_RADIUS_M
                ds.on_a_sphere = "YES"
                ds.createDimension("nCells", 2)
                ds.createDimension("nEdges", 1)
                ds.createVariable("latCell", "f8", ("nCells",))[:] = np.radians([39.9042, -30.0])
                ds.createVariable("lonCell", "f8", ("nCells",))[:] = np.radians([116.4074, -60.0])
                ds.createVariable("xCell", "f8", ("nCells",))[:] = [EARTH_RADIUS_M, 0.0]
                ds.createVariable("areaCell", "f8", ("nCells",))[:] = [EARTH_RADIUS_M**2, 0.0]
                ds.createVariable("dcEdge", "f8", ("nEdges",))[:] = [EARTH_RADIUS_M]
                ds.createVariable("meshDensity", "f8", ("nCells",))[:] = 1.0
            to_mpas_atmosphere(base, grid, ARGS)
            with netCDF4.Dataset(grid) as ds:
                self.assertEqual(float(ds.sphere_radius), 1.0)
                np.testing.assert_allclose(ds["xCell"][:], [1.0, 0.0])
                np.testing.assert_allclose(ds["areaCell"][:], [1.0, 0.0])
                np.testing.assert_allclose(ds["dcEdge"][:], [1.0])
                np.testing.assert_allclose(ds["meshDensity"][:], [1.0, (60.0 / 240.0) ** 4])
                self.assertAlmostEqual(float(ds["nominalMinDc"][:]) * EARTH_RADIUS_M, 60000.0)


class ShellSyntaxTests(unittest.TestCase):
    def test_scripts_parse(self) -> None:
        for script in ("install_mesh_tools.sh", "make_beijing_region.sh"):
            subprocess.run(["bash", "-n", str(ROOT / script)], check=True)


if __name__ == "__main__":
    unittest.main()
