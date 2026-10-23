"""Shared helpers: read MPAS cell polygons as lon/lat degrees for plotting."""

from __future__ import annotations

import math

import netCDF4
import numpy as np

EARTH_RADIUS_KM = 6371.229


def great_circle_km(lat_rad, lon_rad, lat0_deg, lon0_deg):
    lat0, lon0 = math.radians(lat0_deg), math.radians(lon0_deg)
    dlat = lat_rad - lat0
    dlon = (lon_rad - lon0 + math.pi) % (2.0 * math.pi) - math.pi
    hav = np.sin(dlat / 2) ** 2 + np.cos(lat_rad) * math.cos(lat0) * np.sin(dlon / 2) ** 2
    return EARTH_RADIUS_KM * 2.0 * np.arcsin(np.sqrt(np.clip(hav, 0.0, 1.0)))


def read_cells(path):
    """Return a dict with cell centres (deg), area scale (km) and polygons."""
    with netCDF4.Dataset(path) as ds:
        lat = np.asarray(ds["latCell"][:])
        lon = np.asarray(ds["lonCell"][:])
        area = np.asarray(ds["areaCell"][:])
        n_edges = np.asarray(ds["nEdgesOnCell"][:])
        voc = np.asarray(ds["verticesOnCell"][:])
        vid = np.asarray(ds["indexToVertexID"][:])
        vlat = np.degrees(np.asarray(ds["latVertex"][:]))
        vlon = np.degrees(np.asarray(ds["lonVertex"][:]))
        radius = float(ds.getncattr("sphere_radius"))
        mask = np.asarray(ds["bdyMaskCell"][:]) if "bdyMaskCell" in ds.variables else None
    # verticesOnCell stores global vertex IDs; map them back to array positions.
    lookup = np.full(vid.max() + 1, -1, dtype=np.int64)
    lookup[vid] = np.arange(vid.size)
    scale = np.sqrt(area / radius**2) * EARTH_RADIUS_KM
    return {
        "lat": lat, "lon": lon, "scale": scale, "n_edges": n_edges,
        "voc": voc, "lookup": lookup, "vlat": vlat, "vlon": vlon, "mask": mask,
    }


def polygons(cells, index, center_on_180=False):
    """Polygons (lon, lat in degrees) for the selected cell indices.

    Longitudes follow the cell centre: 0..360 by default, -180..180 when
    center_on_180 is true (for global maps centred on Greenwich).
    """
    out = []
    for i in index:
        ids = cells["voc"][i, : cells["n_edges"][i]]
        k = cells["lookup"][ids]
        plon = cells["vlon"][k].copy()
        plat = cells["vlat"][k]
        c = math.degrees(cells["lon"][i]) % 360.0
        if center_on_180 and c >= 180.0:
            c -= 360.0
        plon = (plon - c + 180.0) % 360.0 - 180.0 + c  # keep each polygon contiguous
        out.append(np.column_stack((plon, plat)))
    return out


def lon_deg(lon_rad):
    return np.degrees(lon_rad) % 360.0
