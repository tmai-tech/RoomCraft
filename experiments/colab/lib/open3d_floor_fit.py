"""Open3D offline floor plan fit from RoomCraft Home Scan XYZ (+131).

Usage (Colab / local with open3d installed):

  from open3d_floor_fit import fit_rect_from_xyz
  w_m, l_m, cov = fit_rect_from_xyz("scan_floor.xyz")
  print(w_m * 3.28084, l_m * 3.28084)  # feet

RoomCraft writes `home_scans/<id>_floor.xyz` after each walk (device docs dir).
"""
from __future__ import annotations

import math
from pathlib import Path
from typing import Iterable, List, Tuple


def load_xyz(path: str | Path) -> List[Tuple[float, float, float]]:
    pts: List[Tuple[float, float, float]] = []
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 3:
            continue
        pts.append((float(parts[0]), float(parts[1]), float(parts[2])))
    return pts


def fit_rect_from_xyz(
    path: str | Path,
    percentile_lo: float = 0.02,
    percentile_hi: float = 0.98,
) -> Tuple[float, float, float]:
    """Return (width_m, length_m, coverage_approx) via PCA + percentile hull.

    Pure-Python stand-in for Open3D plane RANSAC + OBB when open3d is absent.
    With open3d available, prefer plane segmentation on the cloud first.
    """
    pts = load_xyz(path)
    if len(pts) < 4:
        raise ValueError("need ≥4 floor points")
    xs = [p[0] for p in pts]
    zs = [p[2] for p in pts]
    cx = sum(xs) / len(xs)
    cz = sum(zs) / len(zs)
    sxx = sxz = szz = 0.0
    for x, _, z in pts:
        dx, dz = x - cx, z - cz
        sxx += dx * dx
        sxz += dx * dz
        szz += dz * dz
    n = float(len(pts))
    sxx /= n
    sxz /= n
    szz /= n
    trace = sxx + szz
    det = sxx * szz - sxz * sxz
    disc = max(0.0, (trace * trace) / 4 - det)
    lam1 = trace / 2 + math.sqrt(disc)
    ux, uz = sxz, lam1 - sxx
    if abs(ux) + abs(uz) < 1e-9:
        ux, uz = 1.0, 0.0
    un = math.hypot(ux, uz)
    ux, uz = ux / un, uz / un
    vx, vz = -uz, ux
    us = [(x - cx) * ux + (z - cz) * uz for x, _, z in pts]
    vs = [(x - cx) * vx + (z - cz) * vz for x, _, z in pts]
    us.sort()
    vs.sort()

    def pct(arr: List[float], p: float) -> float:
        if not arr:
            return 0.0
        t = max(0.0, min(1.0, p)) * (len(arr) - 1)
        i = int(t)
        f = t - i
        if i >= len(arr) - 1:
            return arr[-1]
        return arr[i] * (1 - f) + arr[i + 1] * f

    side_a = abs(pct(us, percentile_hi) - pct(us, percentile_lo))
    side_b = abs(pct(vs, percentile_hi) - pct(vs, percentile_lo))
    # angular coverage (8 bins)
    bins = [0] * 8
    for x, _, z in pts:
        a = math.atan2(z - cz, x - cx)
        i = int((a + math.pi) / (2 * math.pi) * 8)
        bins[max(0, min(7, i))] += 1
    cov = sum(1 for c in bins if c > 0) / 8.0
    return max(side_a, side_b), min(side_a, side_b), cov


def try_open3d_plane_fit(path: str | Path) -> Tuple[float, float] | None:
    """If open3d is installed, RANSAC floor plane + axis-aligned OBB extents."""
    try:
        import open3d as o3d  # type: ignore
        import numpy as np  # type: ignore
    except Exception:
        return None
    pcd = o3d.io.read_point_cloud(str(path), format="xyz")
    if len(pcd.points) < 20:
        return None
    plane_model, inliers = pcd.segment_plane(
        distance_threshold=0.05, ransac_n=3, num_iterations=500
    )
    floor = pcd.select_by_index(inliers)
    aabb = floor.get_axis_aligned_bounding_box()
    ext = aabb.get_extent()
    # drop vertical axis (smallest extent often height of floor slab)
    dims = sorted([float(ext[0]), float(ext[1]), float(ext[2])], reverse=True)
    return dims[0], dims[1]


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("usage: open3d_floor_fit.py path.xyz")
        raise SystemExit(2)
    w, l, cov = fit_rect_from_xyz(sys.argv[1])
    print(f"pure: {w:.3f} x {l:.3f} m  cover={cov:.2f}")
    o3 = try_open3d_plane_fit(sys.argv[1])
    if o3:
        print(f"open3d: {o3[0]:.3f} x {o3[1]:.3f} m")
