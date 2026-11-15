#!/usr/bin/env python3
"""Bahrain launch site data: NASA/USGS Landsat imagery (HLS L30 via NASA GIBS), NASA Blue Marble for the
Gulf around it, and SRTM-based elevation (AWS Open Data terrain tiles; SRTM is NASA/NGA) for shading and
placing the concept pad. Writes data/regions/bahrain_spaceport/ and data/bahrain.json.

    python3 tools/fetch_bahrain.py           # everything
    python3 tools/fetch_bahrain.py --site    # only the 3D patch around the pad (keeps the existing pad)
"""
import io, json, math, time, urllib.request
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "regions" / "bahrain_spaceport"
CACHE = ROOT / ".cache" / "bahrain"
# Bahrain's main island and the sea around it.
LAT0, LAT1, LON0, LON1 = 25.75, 26.35, 50.30, 50.90
# The wider Gulf seen as the rocket climbs.
G_LAT0, G_LAT1, G_LON0, G_LON1 = 22.05, 30.05, 46.6, 54.6
HLS_DATE = "2025-01-05"
GIBS = "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?SERVICE=WMS&REQUEST=GetMap&VERSION=1.3.0&CRS=EPSG:4326&FORMAT=image/jpeg"
TILES = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"


def get(url, name):
    CACHE.mkdir(parents=True, exist_ok=True)
    f = CACHE / name
    if not f.exists():
        req = urllib.request.Request(url, headers={"User-Agent": "NextFrontierExplorer-data/1.0"})
        for attempt in range(4):  # servers sometimes drop a connection; try again
            try:
                f.write_bytes(urllib.request.urlopen(req, timeout=120).read())
                break
            except OSError:
                if attempt == 3:
                    raise
                time.sleep(2 + attempt * 3)
    return f.read_bytes()


def gibs(layer, time, b, size):
    url = f"{GIBS}&LAYERS={layer}&TIME={time}&BBOX={b[0]},{b[2]},{b[1]},{b[3]}&WIDTH={size}&HEIGHT={size}"
    return Image.open(io.BytesIO(get(url, f"{layer}_{time}_{size}.jpg"))).convert("RGB")


def tile_xy(lat, lon, z):
    n = 2 ** z
    x = (lon + 180.0) / 360.0 * n
    y = (1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n
    return x, y


def elevation(n, z=12, box=None):
    """Elevation in metres on an n×n lat/lon grid over a lat/lon box (default: Bahrain; row 0 = north)."""
    lat0, lat1, lon0, lon1 = box or (LAT0, LAT1, LON0, LON1)
    x0, y0 = tile_xy(lat1, lon0, z)
    x1, y1 = tile_xy(lat0, lon1, z)
    tx0, ty0, tx1, ty1 = int(x0), int(y0), int(x1), int(y1)
    mosaic = np.zeros(((ty1 - ty0 + 1) * 256, (tx1 - tx0 + 1) * 256), np.float32)
    for ty in range(ty0, ty1 + 1):
        for tx in range(tx0, tx1 + 1):
            im = np.asarray(Image.open(io.BytesIO(get(TILES.format(z=z, x=tx, y=ty), f"t{z}_{tx}_{ty}.png"))).convert("RGB"), np.float32)
            mosaic[(ty - ty0) * 256:(ty - ty0 + 1) * 256, (tx - tx0) * 256:(tx - tx0 + 1) * 256] = im[..., 0] * 256 + im[..., 1] + im[..., 2] / 256 - 32768
    out = np.zeros((n, n), np.float32)
    for r in range(n):
        lat = lat1 - (lat1 - lat0) * (r + 0.5) / n
        for c in range(n):
            lon = lon0 + (lon1 - lon0) * (c + 0.5) / n
            px, py = tile_xy(lat, lon, z)
            out[r, c] = mosaic[int((py - ty0) * 256), int((px - tx0) * 256)]
    return out


# Small no-data gaps in the Landsat scene come through black: fill each from the valid pixels around it
# (normalised box averaging, widening until every gap is filled).
def fill_gaps(color):
    def box(a, size):
        r = size // 2
        p = np.pad(a, ((r + 1, r), (r + 1, r)), mode="edge")
        c = p.cumsum(0).cumsum(1)
        h_, w_ = a.shape
        return (c[size:size + h_, size:size + w_] - c[0:h_, size:size + w_] - c[size:size + h_, 0:w_] + c[0:h_, 0:w_]) / float(size * size)
    arr = np.asarray(color, np.float32).copy()
    valid = (arr.max(axis=2) >= 18).astype(np.float32)
    size = 5
    while valid.min() < 1.0 and size < 400:
        den = box(valid, size)
        ok = den > 0.05
        for ch in range(3):
            num = box(arr[..., ch] * valid, size)
            arr[..., ch] = np.where(valid > 0, arr[..., ch], np.where(ok, num / np.maximum(den, 1e-6), 0.0))
        valid = np.maximum(valid, ok.astype(np.float32))
        size = size * 2 + 1
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


SITE_KM = 16.0
SITE_N = 256


def site_patch(plat, plon):
    """The 3D launch site: a SITE_KM square centred on the pad. SRTM heights at zoom 14 (about 9 m tiles,
    resampled from SRTM's 30 m) and the same Landsat scene at 30 m, upsampled. Returns metadata."""
    half_lat = SITE_KM / 2.0 / 111.32
    half_lon = SITE_KM / 2.0 / (111.32 * math.cos(math.radians(plat)))
    b = (plat - half_lat, plat + half_lat, plon - half_lon, plon + half_lon)
    h = elevation(SITE_N, 14, b)
    h.astype("<f4").tofile(OUT / "site_height.f32")
    color = fill_gaps(gibs("HLS_L30_Nadir_BRDF_Adjusted_Reflectance", HLS_DATE, b, 1024))
    color.save(OUT / "site_color.jpgdata", format="JPEG", quality=90)
    return {"bbox": [round(v, 5) for v in b], "km": SITE_KM, "n": SITE_N,
            "min_m": round(float(h.min()), 1), "max_m": round(float(h.max()), 1)}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    n = 512
    h = elevation(n)
    land = h > 0.5
    # Hillshade from the elevation (sun from the north-west), blended lightly into the Landsat colour.
    hs = np.asarray(Image.fromarray(np.clip(h * 2.0, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)), np.float32) / 2.0
    gy, gx = np.gradient(hs, 1.0)
    shade = np.clip(1.0 + (-gx + gy) * 0.08, 0.88, 1.08)
    color = gibs("HLS_L30_Nadir_BRDF_Adjusted_Reflectance", HLS_DATE, (LAT0, LAT1, LON0, LON1), 2048)
    color = fill_gaps(color)
    big_shade = np.asarray(Image.fromarray((shade * 200).astype(np.uint8)).resize((2048, 2048), Image.BILINEAR), np.float32) / 200
    big_land = np.asarray(Image.fromarray(land.astype(np.uint8) * 255).resize((2048, 2048), Image.BILINEAR), np.float32) / 255
    c = np.asarray(color, np.float32)
    k = 1.0 + (big_shade - 1.0) * big_land
    color = Image.fromarray(np.clip(c * k[..., None], 0, 255).astype(np.uint8))
    color.save(OUT / "color.jpgdata", format="JPEG", quality=88)
    color.resize((384, 384), Image.LANCZOS).save(OUT / "minimap.jpgdata", format="JPEG", quality=85)
    h.astype("<f4").tofile(OUT / "height.f32")
    gulf = gibs("BlueMarble_NextGeneration", "2004-08-01", (G_LAT0, G_LAT1, G_LON0, G_LON1), 2048)
    gulf.save(OUT / "gulf.jpgdata", format="JPEG", quality=85)
    # Concept pad: the flattest open land near the island's southern desert.
    best = None
    for r in range(n):
        for col in range(n):
            lat = LAT1 - (LAT1 - LAT0) * (r + 0.5) / n
            lon = LON0 + (LON1 - LON0) * (col + 0.5) / n
            if not (25.88 <= lat <= 25.98 and 50.52 <= lon <= 50.62):
                continue
            win = h[max(r - 4, 0):r + 5, max(col - 4, 0):col + 5]
            if (win <= 0.5).any():
                continue
            score = float(win.std())
            if best is None or score < best[0]:
                best = (score, lat, lon, float(h[r, col]))
    _, plat, plon, pelev = best
    width_km = (LON1 - LON0) * 111.32 * math.cos(math.radians((LAT0 + LAT1) / 2))
    meta = {
        "name": "Bahrain Spaceport (concept)",
        "concept": True,
        "bbox": [LAT0, LAT1, LON0, LON1], "width_km": round(width_km, 1),
        "gulf_bbox": [G_LAT0, G_LAT1, G_LON0, G_LON1],
        "gulf_width_km": round((G_LON1 - G_LON0) * 111.32 * math.cos(math.radians(26.0)), 1),
        "pad": {"lat": round(plat, 4), "lon": round(plon, 4), "elev_m": round(pelev, 1)},
        "height_n": n, "height_max_m": round(float(h.max()), 1),
        "site": site_patch(plat, plon),
        "color_label": f"NASA/USGS Landsat (HLS L30, {HLS_DATE}) via NASA GIBS",
        "gulf_label": "NASA Blue Marble Next Generation via NASA GIBS",
        "dem_label": "SRTM-based terrain tiles (NASA/NGA SRTM via AWS Open Data)",
        "al_munther": {
            "name": "Al Munther",
            "launched": "2025-03-15",
            "orbit_km": 550,
            "summary": "Bahrain's first locally built satellite: a 3U CubeSat from the National Space Science Agency, launched on 15 March 2025 to a 550 km sun-synchronous orbit.",
            "url": "https://www.arabnews.pk/node/2593636/middle-east",
            "source": "Arab News, citing the Bahrain News Agency (not a NASA source)",
        },
        "milestone": {
            "id": "al_munther", "name": "Al Munther's orbit (Bahrain)", "km": 550, "bonus": 1000,
            "text": "Bahrain's first locally built satellite, Al Munther, circles Earth at about 550 km. It was launched on 15 March 2025.",
            "url": "https://www.arabnews.pk/node/2593636/middle-east",
            "source": "Arab News, citing the Bahrain News Agency (not a NASA source)",
        },
        "sources": [
            "https://gibs.earthdata.nasa.gov/ (HLS_L30_Nadir_BRDF_Adjusted_Reflectance, BlueMarble_NextGeneration)",
            "https://registry.opendata.aws/terrain-tiles/ (SRTM-based elevation)",
        ],
    }
    (ROOT / "data" / "bahrain.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False))
    print(json.dumps(meta["pad"]), "max", meta["height_max_m"], "m, width", meta["width_km"], "km")


if __name__ == "__main__":
    import sys
    if "--site" in sys.argv:
        OUT.mkdir(parents=True, exist_ok=True)
        path = ROOT / "data" / "bahrain.json"
        meta = json.loads(path.read_text())
        meta["site"] = site_patch(meta["pad"]["lat"], meta["pad"]["lon"])
        path.write_text(json.dumps(meta, indent=1, ensure_ascii=False))
        print(json.dumps(meta["site"]))
    else:
        main()
