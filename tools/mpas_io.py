"""Small, reusable checks for MPAS NetCDF post-processing scripts."""

from __future__ import annotations

from pathlib import Path

import netCDF4


def _identifier(value: object) -> str:
    """Return one normalized MPAS file identifier."""

    return str(value).strip()


def _parent_identifiers(dataset: netCDF4.Dataset) -> list[str]:
    """Return MPAS parent IDs in nearest-to-farthest order."""

    value = getattr(dataset, "parent_id", "")
    return [item.strip() for item in str(value).splitlines() if item.strip()]


def validate_same_mesh(
    coordinates: netCDF4.Dataset,
    diagnostics: netCDF4.Dataset,
    coordinates_path: str | Path,
    diagnostics_path: str | Path,
) -> bool:
    """Validate mesh size and, when present, MPAS file lineage.

    ``True`` means that file_id/parent_id metadata proved the relationship.
    ``False`` means only nCells could be checked because lineage metadata was
    absent. A mismatch always raises ``ValueError``.
    """

    if "nCells" not in coordinates.dimensions:
        raise ValueError(f"{coordinates_path} has no nCells dimension")
    if "nCells" not in diagnostics.dimensions:
        raise ValueError(f"{diagnostics_path} has no nCells dimension")

    coordinate_cells = len(coordinates.dimensions["nCells"])
    diagnostic_cells = len(diagnostics.dimensions["nCells"])
    if coordinate_cells != diagnostic_cells:
        raise ValueError(
            f"mesh mismatch: {coordinates_path} has {coordinate_cells} cells, "
            f"but {diagnostics_path} has {diagnostic_cells}"
        )

    coordinate_id = _identifier(getattr(coordinates, "file_id", ""))
    diagnostic_id = _identifier(getattr(diagnostics, "file_id", ""))
    coordinate_parents = _parent_identifiers(coordinates)
    diagnostic_parents = _parent_identifiers(diagnostics)

    # An init/static/grid file is an ancestor of diagnostics. History and
    # diagnostics files are siblings whose nearest parent is the same init.
    related = (
        bool(coordinate_id and coordinate_id == diagnostic_id)
        or bool(coordinate_id and coordinate_id in diagnostic_parents)
        or bool(diagnostic_id and diagnostic_id in coordinate_parents)
        or bool(
            coordinate_parents
            and diagnostic_parents
            and coordinate_parents[0] == diagnostic_parents[0]
        )
    )
    has_lineage = bool(
        (coordinate_id or coordinate_parents) and (diagnostic_id or diagnostic_parents)
    )
    if has_lineage and not related:
        raise ValueError(
            "mesh lineage mismatch: "
            f"{coordinates_path} (file_id={coordinate_id or 'missing'}) is not "
            f"an ancestor or sibling of {diagnostics_path} "
            f"(file_id={diagnostic_id or 'missing'})"
        )
    return has_lineage
