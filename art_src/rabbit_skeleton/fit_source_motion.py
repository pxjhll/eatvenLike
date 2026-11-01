"""Measure per-part similarity transforms from the seven original PNG poses.

Reads images only; image cutting is performed by Godot's native asset builder.
Outputs inspectable numeric fit data and retains original unequal frame durations.
Requires numpy, scipy and Pillow. No model, API, sine-wave gait or old poses.
"""
from __future__ import annotations

import hashlib
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage, optimize

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
CUTS = json.loads((HERE / "cuts.json").read_text(encoding="utf-8"))
PARTS = json.loads((HERE / "parts_manifest.json").read_text(encoding="utf-8"))
SOURCE = json.loads((ROOT / "art_src/rabbit_walk_frames/source_manifest.json").read_text(encoding="utf-8"))


def read(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"), dtype=np.float64) / 255.0


def fit_view(view: str) -> tuple[str, dict]:
    config = CUTS["views"][view]
    source_meta = next(row for row in SOURCE["directions"] if row["key"] == view)
    paths = [ROOT / f"art_src/rabbit_walk_frames/frames/{view}/{i:02}.png" for i in range(1, 8)]
    frames = [read(path) for path in paths]
    base_index = config["base_frame"] - 1
    base = frames[base_index]
    outside = base[:, :, 3] < 0.05
    distance = ndimage.distance_transform_edt(~outside)
    result = [{"source_frame": i + 1, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "parts": {}} for i, path in enumerate(paths)]
    ordered = sorted(PARTS["views"][view]["parts"].items(), key=lambda item: 0 if item[0] == "head" else 1)
    for part, piece in ordered:
        if part == "face":
            continue
        if not piece["visible"]:
            for frame in result:
                frame["parts"][part] = {"transform": [0, 0, 0, 1, 1], "error": 0}
            continue
        x, y, w, h = piece["rect"]
        local = read(ROOT / f"art/rabbit_skeleton/{view}/{part}.png")
        mask = np.zeros((256, 256), dtype=bool)
        mask[y:y+h, x:x+w] = local[:, :, 3] > 0.75
        # Include genuine outside-silhouette samples, never artificial cut edges.
        halo = ndimage.binary_dilation(mask, iterations=2) & outside
        points = mask | halo
        if part == "head":
            # Blinking is an expression swap, not a change of skull placement.
            internal_black = (base[:, :, :3].mean(axis=2) < 0.25) & (distance > 7)
            points &= ~internal_black
        yy, xx = np.where(points)
        stride = max(1, len(xx) // 1800)
        xx, yy = xx[::stride], yy[::stride]
        expected = base[yy, xx].copy()
        expected[:, :3] *= expected[:, 3:4]
        weights = np.where(distance[yy, xx] < 4, 4.0, 1.0)
        weights *= np.where(base[yy, xx, :3].mean(axis=1) < 0.3, 2.0, 1.0)
        pivot = np.array(config["pivots"][part], dtype=float)
        delta = np.stack([xx-pivot[0], yy-pivot[1]])
        if part == "head":
            bounds = [(-7,7),(-7,7),(-0.10,0.10),(0.96,1.04),(0.96,1.04)]
        elif part.startswith("ear"):
            bounds = [(-7,7),(-7,7),(-0.15,0.15),(0.97,1.03),(0.97,1.03)]
        elif part.startswith("foot"):
            bounds = [(-8,8),(-7,7),(-0.18,0.18),(0.96,1.04),(0.96,1.04)]
        elif part.startswith("arm"):
            bounds = [(-7,7),(-6,6),(-0.30,0.30),(0.97,1.03),(0.97,1.03)]
        else:
            bounds = [(-6,6),(-6,6),(-0.07,0.07),(0.97,1.03),(0.97,1.03)]
        for index, target in enumerate(frames):
            if index == base_index:
                params, error = np.array([0,0,0,1,1]), 0.0
            else:
                def loss(params: np.ndarray) -> float:
                    dx, dy, angle, sx, sy = params
                    c, s = np.cos(angle), np.sin(angle)
                    px = pivot[0]+dx+c*sx*delta[0]-s*sy*delta[1]
                    py = pivot[1]+dy+s*sx*delta[0]+c*sy*delta[1]
                    sampled = np.stack([ndimage.map_coordinates(target[:, :, ch], [py,px], order=1, mode="constant", cval=0, prefilter=False) for ch in range(4)], axis=1)
                    sampled[:, :3] *= sampled[:, 3:4]
                    residual = (sampled-expected)**2
                    residual[:, 3] *= 2.0
                    regularize = 0.0007*(angle**2)+0.004*((sx-1)**2+(sy-1)**2)
                    return float(np.mean(residual.mean(axis=1)*weights)+regularize)
                # A deterministic translation search avoids local minima on flat fills.
                seeds = [np.array([dx,dy,0,1,1], dtype=float) for dx in [-4,0,4] for dy in [-3,0,3]]
                seed = min(seeds, key=loss)
                fitted = optimize.minimize(loss, seed, method="Powell", bounds=bounds, options={"maxiter":32,"xtol":0.025,"ftol":1e-5})
                params, error = fitted.x, fitted.fun
            result[index]["parts"][part] = {"transform": [round(float(v),5) for v in params], "error": round(float(error),6)}
    print(f"Fitted {view}: seven original poses, {source_meta['cycle_ms']}ms", flush=True)
    return view, {"base_frame":config["base_frame"], "durations_ms":source_meta["durations_ms"], "cycle_ms":source_meta["cycle_ms"], "frames":result}


if __name__ == "__main__":
    with ThreadPoolExecutor(max_workers=5) as pool:
        views = dict(pool.map(fit_view, CUTS["views"]))
    (HERE / "source_fit.json").write_text(json.dumps({"source":"rabbit_walk_frames", "method":"masked similarity fitting against actual source PNGs", "views":views}, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
