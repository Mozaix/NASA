#!/usr/bin/env python3
"""Download every NASA dataset the game uses, cache it, process it, and record its source.

    tools/.venv/bin/python tools/fetch_data.py            # everything (resumes from cache)
    tools/.venv/bin/python tools/fetch_data.py --only facts,exo

Raw downloads go to .cache/ (not shipped). Processed output goes to data/ (shipped in the game).
The network is allowed to drop: requests retry with long backoff and nothing is cached until a
download has completed.
"""
import argparse
import concurrent.futures as cf
import hashlib
import html
import json
import math
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date
from io import BytesIO
from pathlib import Path

import certifi
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import catalog as C  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / ".cache"
DATA = ROOT / "data"
UA = "NextFrontierExplorer-datafetch/1.0 (NASA Space Apps 2026 game)"
FS = "https://nssdc.gsfc.nasa.gov/planetary/factsheet/"
G = 6.6743e-11
Image.MAX_IMAGE_PIXELS = None
SSL = ssl.create_default_context(cafile=certifi.where())

WORLD_M = 4096.0     # every terrain is 4096 x 4096 game metres
HEIGHT_N = 1024      # height samples per side (4 m per vertex in game)
COLOR_N = 2048       # colour texture per side
PROVENANCE = {"generated": str(date.today()), "dropped_facts": [], "regions": {}}


# ------------------------------------------------------------------------------- network
class NotFound(Exception):
    pass


def http(url, byte_range=None, attempts=40, timeout=90):
    """GET with on-disk cache. Retries through outages; a 404 raises NotFound immediately."""
    key = url + (f"#{byte_range[0]}-{byte_range[1]}" if byte_range else "")
    path = CACHE / hashlib.sha256(key.encode()).hexdigest()[:32]
    if path.exists():
        return path.read_bytes()
    headers = {"User-Agent": UA}
    if byte_range:
        headers["Range"] = f"bytes={byte_range[0]}-{byte_range[1]}"
    for i in range(attempts):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=timeout, context=SSL) as r:
                body = r.read()
            if byte_range and len(body) != byte_range[1] - byte_range[0] + 1:
                raise IOError(f"short range read: {len(body)} bytes")
            tmp = path.with_suffix(f".{os.getpid()}.{id(body)}.tmp")
            tmp.write_bytes(body)
            tmp.replace(path)
            return body
        except urllib.error.HTTPError as e:
            if e.code in (403, 404, 410):
                raise NotFound(f"{e.code} {url}") from e
            err = e
        except Exception as e:  # DNS failures, resets and timeouts are all worth retrying
            err = e
        wait = min(30 * (i + 1), 300)
        print(f"  retry {i + 1} in {wait}s: {url[:90]} ({str(err)[:60]})", flush=True)
        time.sleep(wait)
    raise IOError(f"gave up on {url}")


def page_text(url):
    b = http(url).decode("utf8", "ignore")
    b = re.sub(r"(?is)<(script|style|noscript).*?</\1>", " ", b)
    b = re.sub(r"<[^>]+>", " ", b)
    return re.sub(r"\s+", " ", html.unescape(b))


def rows_of(url):
    """Parse an NSSDC fact sheet into table rows of cleaned cell text."""
    t = http(url).decode("latin1")
    out = []
    for row in re.findall(r"(?is)<tr[^>]*>(.*?)(?=<tr|</table)", t):
        cells = []
        for c in re.findall(r"(?is)<t[dh][^>]*>(.*?)(?=<t[dh]|</tr|$)", row):
            cells.append(re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", c))).strip())
        if any(cells):
            out.append(cells)
    return out


# ------------------------------------------------------------------------------- facts + bodies
def num(s):
    """'12,104' -> 12104.0, '0.384*' -> 0.384, 'Unknown*' -> None."""
    m = re.match(r"^-?[\d,]*\.?\d+", (s or "").replace(" ", ""))
    return float(m.group(0).replace(",", "")) if m else None


def verified(facts, label):
    keep = []
    for f in facts:
        if f["text"] in page_text(f["url"]):
            keep.append(f)
        else:
            PROVENANCE["dropped_facts"].append({"where": label, **f})
            print(f"  DROPPED fact not found on page ({label}): {f['text'][:70]}")
    return keep


def atmosphere_text(page):
    """Pull the surface pressure and composition lines out of an NSSDC planet page."""
    t = http(FS + page).decode("latin1")
    t = html.unescape(re.sub(r"<[^>]+>", "", t))
    i = t.find("Atmosphere")
    if i < 0:
        return {}
    sec = t[i:i + 2500]
    out = {}
    m = re.search(r"Surface pressure:\s*([^\n]+)", sec)
    if m:
        out["surface_pressure_text"] = re.sub(r"\s+", " ", m.group(1)).strip()
    m = re.search(r"(?:Atmospheric composition|composition)[^\n]*\n(.*?)(?:\n\s*\n|Minor)", sec, re.S)
    # Only accept text that actually lists percentages; some pages have prose in this position.
    if m and "%" in m.group(1):
        out["composition"] = re.sub(r"\s+", " ", m.group(1)).replace("Major :", "").replace("Major:", "").strip()
    m = re.search(r"Scale height:\s*([\d.]+)", sec)
    if m:
        out["scale_height_km"] = float(m.group(1))
    return out


def planetary_table():
    rows = rows_of(FS)
    header = next(r for r in rows if "MERCURY" in r)
    idx = {name: i for i, name in enumerate(header) if name}
    table = {}
    for r in rows:
        if r and r[0] and r is not header:
            table[re.sub(r"\s+", " ", r[0])] = r
    return idx, table


def sat_row(rows, label, nth=0):
    hits = [r for r in rows if r and re.match(rf"^{label}\b", r[0])]
    return hits[nth] if len(hits) > nth else None


def fetch_bodies():
    print("Bodies: planetary fact sheets")
    idx, table = planetary_table()

    def col(key, name):
        row = next((v for k, v in table.items() if k.startswith(key)), None)
        return row[idx[name]] if row and idx[name] < len(row) else None

    bodies = {}
    for bid, b in {**C.PLANETS, **{k: v for k, v in C.MOONS.items() if "col" in v}}.items():
        c = b["col"]
        d = {
            "id": bid, "name": b["name"], "kind": "moon" if "parent" in b else "planet",
            "parent": b.get("parent", "sun"),
            "mass_kg": num(col("Mass", c)) * 1e24,
            "radius_km": num(col("Diameter", c)) / 2,
            "density": num(col("Density", c)),
            "gravity": num(col("Gravity", c)),
            "gravity_source": "fact sheet",
            "escape_kms": num(col("Escape Velocity", c)),
            "rotation_hours": num(col("Rotation Period", c)),
            "day_hours": num(col("Length of Day", c)),
            "a_km": num(col("Distance from Sun", c)) * 1e6,
            "orbit_days": num(col("Orbital Period", c)),
            "orbit_kms": num(col("Orbital Velocity", c)),
            "incl_deg": num(col("Orbital Inclination", c)),
            "ecc": num(col("Orbital Eccentricity", c)),
            "obliquity_deg": num(col("Obliquity", c)),
            "temp_c": num(col("Mean Temperature", c)),
            "pressure_bar": num(col("Surface Pressure", c)),
            "n_moons": num(col("Number of Moons", c)),
            "rings": col("Ring System", c) == "Yes",
            "magnetic": col("Global Magnetic Field", c),
            "source_url": FS,
        }
        d.update(atmosphere_text(b["page"]))
        d["detail_url"] = FS + b["page"]
        bodies[bid] = d

    # Moons other than our own come from the satellite fact sheets. Those list mass and radius, so
    # surface gravity and escape velocity are computed and labelled as derived.
    for bid, b in C.MOONS.items():
        if "sat" not in b:
            continue
        page, label = b["sat"]
        rows = rows_of(FS + page)
        bulk = sat_row(rows, label, 0)
        orbit = sat_row(rows, label, 1)
        mass = num(bulk[1]) * 1e20
        radii = [num(x) for x in bulk[2].split(" x ")]
        radius = sum(radii) / len(radii)
        grav = G * mass / (radius * 1e3) ** 2
        d = {
            "id": bid, "name": b["name"], "kind": "moon", "parent": b["parent"],
            "mass_kg": mass, "radius_km": radius, "density": num(bulk[3]),
            "gravity": round(grav, 3), "gravity_source": "derived: G x mass / radius^2",
            "escape_kms": round(math.sqrt(2 * G * mass / (radius * 1e3)) / 1e3, 3),
            "a_km": num(orbit[1]) * 1e3 if orbit else None,
            "orbit_days": num(orbit[2]) if orbit and len(orbit) > 2 else None,
            "source_url": FS + page,
        }
        bodies[bid] = d

    # The fact sheet gives the Moon's distance from Earth, marked with an asterisk.
    for bid, facts in C.BODY_FACTS.items():
        bodies[bid]["facts"] = verified(facts, bid)
        print(f"  {bid:10s} g={bodies[bid]['gravity']} R={bodies[bid]['radius_km']:.0f} km, "
              f"{len(bodies[bid]['facts'])} facts")
    for bid, m in C.GLOBAL_MAPS.items():
        bodies[bid]["map_credit"] = m["credit"]
    return bodies


def fetch_elements():
    print("JPL Keplerian elements")
    t = html.unescape(re.sub(r"<[^>]+>", "", http("https://ssd.jpl.nasa.gov/planets/approx_pos.html").decode("utf8", "ignore")))
    t = t[t.find("Table 1"):]
    out = {}
    names = {"Mercury": "mercury", "Venus": "venus", "EM Bary": "earth", "Mars": "mars", "Jupiter": "jupiter",
             "Saturn": "saturn", "Uranus": "uranus", "Neptune": "neptune"}
    for label, bid in names.items():
        m = re.search(re.escape(label) + r"\s+((?:-?[\d.]+\s+){6})\s*((?:-?[\d.]+\s+){6})", t)
        vals, rates = [list(map(float, g.split())) for g in m.groups()]
        out[bid] = {"a_au": vals[0], "e": vals[1], "i_deg": vals[2], "L_deg": vals[3], "peri_deg": vals[4], "node_deg": vals[5],
                    "L_rate_deg_cy": rates[3]}
    return {"epoch": "J2000", "valid": "1800 AD - 2050 AD", "source_url": "https://ssd.jpl.nasa.gov/planets/approx_pos.html", "planets": out}


# ------------------------------------------------------------------------------- exoplanets
EXO_COLS = "pl_name,hostname,pl_rade,pl_bmasse,pl_orbper,pl_orbsmax,pl_eqt,st_teff,st_rad,sy_dist,disc_year,discoverymethod"
TAP = "https://exoplanetarchive.ipac.caltech.edu/TAP/sync?format=json&query="


def classify(r):
    rade = r.get("pl_rade") or 1.0
    if rade < 1.6:
        return "terrestrial"
    if rade < 2.2:
        return "super_earth"
    if rade < 6.0:
        return "neptune_like"
    return "gas_giant"


def fetch_exo():
    print("Exoplanets: NASA Exoplanet Archive")
    names = ",".join("'" + n.replace("'", "''") + "'" for n in C.EXO_NAMES)
    q = f"select {EXO_COLS} from pscomppars where pl_name in ({names})"
    rows = json.loads(http(TAP + urllib.parse.quote(q)))
    have = {r["pl_name"] for r in rows}
    missing = [n for n in C.EXO_NAMES if n not in have]
    if missing:
        print("  not in archive under these names:", missing)
    if len(rows) < 50:
        q = (f"select top 200 {EXO_COLS} from pscomppars where pl_rade is not null and pl_bmasse is not null "
             "and pl_eqt is not null and st_teff is not null and sy_dist < 60 order by sy_dist")
        for r in json.loads(http(TAP + urllib.parse.quote(q))):
            if len(rows) >= 50:
                break
            if r["pl_name"] not in have:
                rows.append(r)
                have.add(r["pl_name"])
    facts = {k: verified(v, "exo:" + k) for k, v in C.EXO_FACTS.items()}
    out = []
    for r in rows:
        d = {k: r.get(k) for k in EXO_COLS.split(",")}
        d["id"] = "exo_" + re.sub(r"[^a-z0-9]+", "_", r["pl_name"].lower()).strip("_")
        d["class"] = classify(r)
        d["has_surface"] = d["class"] in ("terrestrial", "super_earth")
        d["derived"] = {}
        # Equilibrium temperature is missing for some planets. Blackbody estimate from the star, labelled.
        if d["pl_eqt"] is None and d["st_teff"] and d["st_rad"] and d["pl_orbsmax"]:
            ratio = d["st_rad"] * 6.957e8 / (2 * d["pl_orbsmax"] * 1.496e11)
            d["pl_eqt"] = round(d["st_teff"] * math.sqrt(ratio))
            d["derived"]["pl_eqt"] = "blackbody estimate from star temperature, star radius and orbit size"
        if d["pl_bmasse"] and d["pl_rade"]:
            d["gravity"] = round(G * d["pl_bmasse"] * 5.9722e24 / (d["pl_rade"] * 6.371e6) ** 2, 2)
            d["derived"]["gravity"] = "G x archive mass / archive radius^2"
        else:
            d["gravity"] = None
        d["source_url"] = "https://exoplanetarchive.ipac.caltech.edu/overview/" + urllib.parse.quote(r["pl_name"])
        out.append(d)
    out.sort(key=lambda d: d["sy_dist"] if d["sy_dist"] is not None else 1e9)
    print(f"  {len(out)} planets, {sum(d['has_surface'] for d in out)} with a solid surface")
    return {"planets": out, "class_facts": facts, "source_url": C.SOURCES_EXTRA[2][1], "columns": EXO_COLS}


# ------------------------------------------------------------------------------- Treks tiles
def trek_template(body, layer):
    caps = http(f"{C.TREK}/{body}/EQ/{layer}/1.0.0/WMTSCapabilities.xml").decode("utf8", "ignore")
    tpl = re.search(r'template="([^"]+)"', caps).group(1)
    max_level = len(re.findall(r"<TileMatrix>", caps)) - 1
    return tpl.replace("{Style}", "default").replace("{TileMatrixSet}", "default028mm"), max_level


def tile(tpl, z, row, col):
    u = tpl.replace("{TileMatrix}", str(z)).replace("{TileRow}", str(row)).replace("{TileCol}", str(col))
    try:
        return Image.open(BytesIO(http(u)))
    except NotFound:
        return None  # sparse layers legitimately omit some tiles


def stitch(body, layer, z, r0, r1, c0, c1, mode="RGB"):
    tpl, _ = trek_template(body, layer)
    ncols = 2 ** (z + 1)
    w, h = (c1 - c0 + 1) * 256, (r1 - r0 + 1) * 256
    canvas = Image.new(mode, (w, h))
    jobs = [(r, c) for r in range(r0, r1 + 1) for c in range(c0, c1 + 1)]

    def one(job):
        r, c = job
        return r, c, tile(tpl, z, r, c % ncols)

    with cf.ThreadPoolExecutor(8) as ex:
        for r, c, im in ex.map(one, jobs):
            if im is not None:
                canvas.paste(im.convert(mode), ((c - c0) * 256, (r - r0) * 256))
    return canvas


def real_max_level(body, layer, lat, lon):
    """Treks capabilities can advertise zoom levels with no tiles, so test for an actual tile."""
    tpl, mx = trek_template(body, layer)
    for z in range(mx, -1, -1):
        deg = 180.0 / 2 ** z
        if tile(tpl, z, min(int((90 - lat) / deg), 2 ** z - 1), int(((lon + 180) % 360) / deg)) is not None:
            return z
    raise IOError(f"no tiles at all for {layer}")


def tone_region(img, body):
    """Display grading only, stated in SOURCES.md. Heights and positions are untouched.
    Mars: Viking's blue-white haze patches read as snow, so they are pulled back to surface tones.
    Moon: dark mare is exposed up so it stays readable without changing relative brightness."""
    a = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    if body == "mars":
        lum = a.mean(axis=2, keepdims=True)
        haze = np.clip((a[..., 2:3] / np.maximum(a[..., 0:1], 0.02) - 0.72) / 0.25, 0, 1)
        surface = np.minimum(lum, 0.62) * np.array([1.28, 0.92, 0.68])
        a = a * (1 - haze) + surface * haze
        a = np.minimum(a, 0.82 + (a - 0.82) * 0.25)
    elif body == "moon":
        a = a * min(0.40 / max(float(a.mean()), 0.02), 2.4)
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))


def fill_gaps(img, threshold=4):
    """Fill missing-data pixels (pure black) from their surroundings. Real gaps exist in Magellan,
    Voyager and Galileo coverage; filled pixels are noted in SOURCES.md."""
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    mask = a.max(axis=2) < threshold
    if not mask.any():
        return img
    # JPEG blocks ring around each gap, so grow the mask a little to take the fringe with it.
    grown = Image.fromarray(mask.astype(np.uint8) * 255).resize((mask.shape[1] // 2, mask.shape[0] // 2), Image.BOX)
    mask = mask | (np.asarray(grown.resize((mask.shape[1], mask.shape[0]), Image.BILINEAR)) > 30)
    h, w = mask.shape

    def smooth(arr, factor):
        small = Image.fromarray(arr, mode="F").resize((max(w // factor, 1), max(h // factor, 1)), Image.BOX)
        return np.asarray(small.resize((w, h), Image.BILINEAR), dtype=np.float32)

    out = a.copy()
    weight = (~mask).astype(np.float32)
    for factor in (4, 12, 32, 96, 256):
        wt = smooth(weight, factor)
        ok = (wt > 0.05) & mask
        for c in range(3):
            out[..., c][ok] = (smooth(out[..., c] * weight, factor)[ok] / wt[ok])
        weight[ok] = 1.0
        mask = mask & ~ok
        if not mask.any():
            break
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def apply_tint(img, tint):
    if not tint:
        return img
    return Image.fromarray(np.clip(np.asarray(img.convert("RGB"), dtype=np.float32) * np.array(tint), 0, 255).astype(np.uint8))


def require_content(img, label):
    a = np.asarray(img.convert("L"), dtype=np.float32)
    if (a < 4).mean() > 0.5:
        raise IOError(f"{label}: over half the image is black, so tiles are probably missing")
    return img


def trek_global(body, layer, level):
    z = min(level, real_max_level(body, layer, 0.0, 0.0))
    return stitch(body, layer, z, 0, 2 ** z - 1, 0, 2 ** (z + 1) - 1)


def trek_crop(body, layer, lat0, lat1, lon0, lon1, out_w, out_h, mode="RGB", want_px=None):
    """Equirectangular crop. lat0 > lat1 (north first). Longitudes in -180..180 and may cross 180."""
    mx = real_max_level(body, layer, (lat0 + lat1) / 2, (lon0 + lon1) / 2)
    want = want_px or out_w
    z = 0
    while z < mx and (lon1 - lon0) / 360 * 2 ** (z + 1) * 256 < want:
        z += 1
    deg = 180.0 / 2 ** z / 256.0  # degrees per pixel at this level
    cf0, cf1 = (lon0 + 180) / deg / 256, (lon1 + 180) / deg / 256
    rf0, rf1 = (90 - lat0) / deg / 256, (90 - lat1) / deg / 256
    c0, c1, r0, r1 = int(math.floor(cf0)), int(math.floor(cf1)), int(math.floor(rf0)), min(int(math.floor(rf1)), 2 ** z - 1)
    im = stitch(body, layer, z, r0, r1, c0, c1, mode)
    box = ((cf0 - c0) * 256, (rf0 - r0) * 256, (cf1 - c0) * 256, (rf1 - r0) * 256)
    resample = Image.LANCZOS if mode == "RGB" else Image.BICUBIC
    return im.resize((out_w, out_h), resample, box=box)


# ------------------------------------------------------------------------------- PDS elevation
def parse_label(url):
    t = http(url).decode("latin1")

    def g(key, cast=float, default=None):
        m = re.search(rf"^\s*{key}\s*=\s*\"?([-\w.+]+)", t, re.M)
        return cast(m.group(1)) if m else default

    return {
        "lines": g("LINES", int), "samples": g("LINE_SAMPLES", int), "type": g("SAMPLE_TYPE", str),
        "scale": g("SCALING_FACTOR", float, 1.0), "max_lat": g("MAXIMUM_LATITUDE"), "min_lat": g("MINIMUM_LATITUDE"),
        "west": g("WESTERNMOST_LONGITUDE"), "east": g("EASTERNMOST_LONGITUDE"), "res": g("MAP_RESOLUTION"),
        "map_scale": g("MAP_SCALE"), "line_off": g("LINE_PROJECTION_OFFSET"), "samp_off": g("SAMPLE_PROJECTION_OFFSET"),
    }


def read_rows(url, lab, first, last):
    """Range-read rows first..last inclusive, in chunks so a dropped connection loses little."""
    rowbytes = lab["samples"] * 2
    dt = ">i2" if lab["type"].startswith("MSB") else "<i2"
    chunk = 200
    spans = [(a, min(a + chunk - 1, last)) for a in range(first, last + 1, chunk)]

    def one(span):
        return np.frombuffer(http(url, (span[0] * rowbytes, (span[1] + 1) * rowbytes - 1)), dtype=dt)

    with cf.ThreadPoolExecutor(4) as ex:
        parts = list(ex.map(one, spans))
    return np.concatenate(parts).reshape(-1, lab["samples"]).astype(np.float32) * lab["scale"]


def cyl_dem(region, lat0, lat1, lon0, lon1):
    kind, name = region["dem"]
    base = (C.PDS + "/mgs/mgs-m-mola-5-megdr-l3-v1/mgsl_300x/meg128/" if kind == "mola"
            else C.PDS + "/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/") + name
    lab = parse_label(base + ".lbl")
    west = lab["west"] or 0.0
    lon0e, lon1e = lon0 % 360, (lon0 % 360) + (lon1 - lon0)
    res = lab["res"]
    fl0, fl1 = (lab["max_lat"] - lat0) * res, (lab["max_lat"] - lat1) * res
    fs0, fs1 = (lon0e - west) * res, (lon1e - west) * res
    if fs0 < 0 or fs1 > lab["samples"] or fl0 < 0 or fl1 > lab["lines"]:
        raise ValueError(f"{name} does not contain region: {fl0, fl1, fs0, fs1} of {lab}")
    r0, r1 = int(fl0), min(int(math.ceil(fl1)), lab["lines"] - 1)
    a = read_rows(base + ".img", lab, r0, r1)
    box = (fs0, fl0 - r0, fs1, fl1 - r0)
    # Samples outside the crop are cut by box, so only the kept columns matter.
    im = Image.fromarray(a, mode="F").resize((HEIGHT_N, HEIGHT_N), Image.BICUBIC, box=box)
    return np.asarray(im, dtype=np.float32), lab


def polar_dem(region):
    """Crop the polar stereographic LDEM around the crater. Returns height and the crop geometry."""
    name = region["dem"][1]
    base = C.PDS + "/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/" + name
    lab = parse_label(base + ".lbl")
    scale_km = lab["map_scale"] if lab["map_scale"] < 1 else lab["map_scale"] / 1000.0
    R = 1737.4
    t = 2 * R * math.tan(math.radians((90 + region["lat"]) / 2))
    cx, cy = t * math.sin(math.radians(region["lon"])), t * math.cos(math.radians(region["lon"]))
    half = region["width_km"] / 2
    L0, S0 = lab["line_off"], lab["samp_off"]
    # PDS polar LDEM convention: x = (sample - S0 - 1) * scale, y = (1 + L0 - line) * scale
    s0, s1 = (cx - half) / scale_km + S0 + 1, (cx + half) / scale_km + S0 + 1
    l0, l1 = 1 + L0 - (cy + half) / scale_km, 1 + L0 - (cy - half) / scale_km
    r0, r1 = int(l0) - 1, int(math.ceil(l1))
    a = read_rows(base + ".img", lab, r0, r1)
    im = Image.fromarray(a, mode="F").resize((HEIGHT_N, HEIGHT_N), Image.BOX, box=(s0 - 1, l0 - 1 - r0, s1 - 1, l1 - 1 - r0))
    return np.asarray(im, dtype=np.float32), lab, (cx, cy)


# ------------------------------------------------------------------------------- terrain output
def save_terrain(rid, h, color_img, meta, hscale, vexag):
    out = DATA / "regions" / rid
    out.mkdir(parents=True, exist_ok=True)
    h = h.astype("<f4")
    (out / "height.f32").write_bytes(h.tobytes())
    # World-space normals so lighting matches the exaggerated terrain the player actually sees.
    texel_world = WORLD_M / HEIGHT_N
    world_h = h / hscale * vexag
    dzdy, dzdx = np.gradient(world_h, texel_world)
    n = np.dstack([-dzdx, np.ones_like(h), -dzdy])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    # Soften lighting only. The heights used for physics and readouts are not changed.
    for axis in (0, 1):
        n = np.roll(n, 1, axis) * 0.25 + n * 0.5 + np.roll(n, -1, axis) * 0.25
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(out / "normal.pngdata", format="PNG")
    color_img.convert("RGB").save(out / "color.jpgdata", format="JPEG", quality=92, subsampling=0)
    (out / "minimap.jpgdata").write_bytes(_jpeg(color_img.convert("RGB").resize((384, 384), Image.LANCZOS)))
    meta.update({"height_min_m": float(h.min()), "height_max_m": float(h.max()), "height_n": HEIGHT_N,
                 "world_m": WORLD_M, "hscale": hscale, "vexag": vexag})
    return meta


def _jpeg(img):
    b = BytesIO()
    img.save(b, format="JPEG", quality=88)
    return b.getvalue()


def nomen_lookup(body, name):
    """Official coordinates from the Treks copy of the IAU nomenclature. Returns (lat, lon) or None."""
    q = urllib.parse.quote(name)
    url = (f"https://trek.nasa.gov/{body.lower()}/TrekServices/ws/index/eq/searchItems?proj=urn:ogc:def:crs:IAU2000::0"
           f"&start=0&rows=8&key={q}&facetKeys=itemType&facetValues=nomenclature")
    try:
        docs = json.loads(http(url, attempts=6))["response"]["docs"]
    except Exception as e:
        print(f"  nomenclature lookup failed for {name}: {str(e)[:60]}")
        return None
    for d in docs:
        if d.get("title", "").lower() == name.lower() and "POINT" in d.get("shape", ""):
            lon, lat = map(float, re.findall(r"-?[\d.]+", d["shape"])[:2])
            return lat, (lon + 180) % 360 - 180
    return None


def build_dem_region(rid, r):
    print(f"Region {rid}: {r['name']}")
    body_R = {"mars": 3389.5, "moon": 1737.4}[r["body"]]
    km_per_deg = 2 * math.pi * body_R / 360
    hscale = r["width_km"] * 1000 / WORLD_M
    info = {"id": rid, "body": r["body"], "name": r["name"], "real_elevation": True, "dem_label": r["dem_label"],
            "width_km": r["width_km"], "landing_name": r["landing"], "lat": r["lat"], "lon": r["lon"], "polar": bool(r.get("polar"))}
    px_uv = None
    if r.get("polar"):
        h, lab, centre = polar_dem(r)
        # The WAC mosaic has hard seams this close to the pole, so the surface is shaded from the real
        # LOLA heights instead. Two sun directions keep the crater interior readable. See PLAN.md D9.
        H = np.asarray(Image.fromarray(h, mode="F").resize((COLOR_N, COLOR_N), Image.BICUBIC))
        dy, dx = np.gradient(H, r["width_km"] * 1000 / COLOR_N)
        shade = 0.46 + 0.62 * np.clip(dx * 0.75 + dy * 0.35, -0.6, 0.6) + 0.22 * np.clip(-dx * 0.3 + dy * 0.6, -0.6, 0.6)
        g = np.clip(shade, 0.05, 1.0)
        col = Image.fromarray((np.dstack([g * 0.97, g * 0.97, g]) * 255).astype(np.uint8))
        info["color_label"] = "Shaded from LOLA elevation (WAC mosaic has seams at the pole)"
        half = r["width_km"] / 2

        def uv_off(xkm, ykm):
            return (xkm + half) / (2 * half), (half - ykm) / (2 * half)
        pts = {"landing": uv_off(*r["landing_offset_km"])}
        for p in r["pois"]:
            pts[p["name"]] = uv_off(*p["offset_km"])
    else:
        dlat = r["width_km"] / km_per_deg
        dlon = dlat / math.cos(math.radians(r["lat"]))
        lat0, lat1 = r["lat"] + dlat / 2, r["lat"] - dlat / 2
        lon0, lon1 = r["lon"] - dlon / 2, r["lon"] + dlon / 2
        h, lab = cyl_dem(r, lat0, lat1, lon0, lon1)
        col = require_content(trek_crop(*r["trek"], lat0, lat1, lon0, lon1, COLOR_N, COLOR_N), rid)
        col = tone_region(col, r["body"])
        info["color_label"] = C.GLOBAL_MAPS[r["body"]]["credit"]

        def uv_ll(lat, lon):
            return (((lon - lon0 + 180) % 360 - 180) / dlon, (lat0 - lat) / dlat)
        pts = {"landing": uv_ll(*r["landing_ll"])}
        for p in r["pois"]:
            lat, lon = p["lat"], p["lon"]
            if p.get("nomen"):
                hit = nomen_lookup(r["body"], p["nomen"])
                if hit:
                    lat, lon = hit
                    p["coords_source"] = "IAU nomenclature via NASA Treks"
            p["lat"], p["lon"] = lat, lon
            pts[p["name"]] = uv_ll(lat, lon)
        px_uv = (lat0, lat1, lon0, lon1)

    def elev(uv):
        return float(h[min(int(uv[1] * HEIGHT_N), HEIGHT_N - 1), min(int(uv[0] * HEIGHT_N), HEIGHT_N - 1)])

    pois = []
    for p in r["pois"]:
        u, v = pts[p["name"]]
        if not (0.02 < u < 0.98 and 0.02 < v < 0.98):
            raise ValueError(f"POI {p['name']} is outside region {rid}: {u:.3f},{v:.3f}")
        kept = verified([{"text": p["text"], "url": p["url"]}], f"{rid}/{p['name']}")
        if not kept:
            continue
        pois.append({"name": p["name"], "u": u, "v": v, "elev_m": round(elev((u, v))), "sample": p["sample"], "fact": kept[0],
                     "lat": p.get("lat"), "lon": p.get("lon"), "coords_source": p.get("coords_source", "catalog")})
    info["pois"] = pois
    info["landing_uv"] = pts["landing"]
    # Which dataset produced each number is recorded for the judges.
    if r.get("trek_dem") and px_uv:
        info["trek_dem_check"] = trek_dem_check(r, h, *px_uv)
    print(f"  elevation {h.min():.0f}..{h.max():.0f} m  {info.get('trek_dem_check', '')}")
    PROVENANCE["regions"][rid] = {"dem": r["dem_label"], "check": info.get("trek_dem_check")}
    return save_terrain(rid, h, col, info, hscale, r["vexag"])


def trek_dem_check(r, h, lat0, lat1, lon0, lon1):
    """Compare the 16-bit PDS heights with the Treks 8-bit DEM for the same ground."""
    try:
        g = np.asarray(trek_crop(*r["trek_dem"], lat0, lat1, lon0, lon1, 256, 256, mode="L", want_px=256), dtype=np.float64)
    except Exception as e:
        return {"error": str(e)[:80]}
    small = np.asarray(Image.fromarray(h, mode="F").resize((256, 256), Image.BOX), dtype=np.float64)
    if g.std() == 0:
        return {"error": "flat Treks tile"}
    slope, inter = np.polyfit(g.ravel(), small.ravel(), 1)
    return {"correlation": round(float(np.corrcoef(g.ravel(), small.ravel())[0, 1]), 4),
            "treks_m_per_grey_level": round(float(slope), 1), "treks_grey_levels_here": int(len(np.unique(g.astype(np.uint8))))}


# Procedural relief for bodies that have real imagery but no bundled DEM. Always labelled in-game.
def spectral(n, beta, rng):
    fx = np.fft.fftfreq(n)[:, None]
    fy = np.fft.fftfreq(n)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1
    spec = (rng.normal(size=(n, n)) + 1j * rng.normal(size=(n, n))) / f ** (beta / 2)
    spec[0, 0] = 0
    a = np.fft.ifft2(spec).real
    return (a - a.mean()) / a.std()


def add_craters(h, rng, count, rmin, rmax, depth):
    n = h.shape[0]
    Y, X = np.mgrid[0:n, 0:n]
    for _ in range(count):
        r = rmin * (rmax / rmin) ** (rng.random() ** 2.2)
        cx, cy = rng.random() * n, rng.random() * n
        x0, x1, y0, y1 = max(int(cx - 2 * r), 0), min(int(cx + 2 * r), n), max(int(cy - 2 * r), 0), min(int(cy + 2 * r), n)
        d = np.hypot(X[y0:y1, x0:x1] - cx, Y[y0:y1, x0:x1] - cy) / r
        bowl = np.where(d < 1, d * d - 1, 0.0)
        rim = 0.22 * np.exp(-((d - 1) / 0.28) ** 2)
        h[y0:y1, x0:x1] += (bowl + rim) * depth * (r / rmax) ** 0.7
    return h


def procedural_relief(style, relief_m, lum, seed):
    rng = np.random.default_rng(seed)
    n = HEIGHT_N
    base = spectral(n, 3.6, rng)
    if style == "cratered":
        h = base * 0.35 + add_craters(np.zeros((n, n)), rng, 140, 8, 150, 1.0)
    elif style == "icy_cratered":
        h = base * 0.3 + add_craters(np.zeros((n, n)), rng, 70, 6, 90, 0.8) + np.abs(spectral(n, 3.0, rng)) * 0.2
    elif style == "volcanic":
        ridged = 1 - np.abs(spectral(n, 3.2, rng))
        h = base * 0.7 + ridged * 0.5 + add_craters(np.zeros((n, n)), rng, 12, 20, 90, 0.5)
    elif style == "icy":
        h = base * 0.25 + (1 - np.abs(spectral(n, 2.6, rng))) ** 3 * 0.8
    elif style == "dunes":
        Y, X = np.mgrid[0:n, 0:n]
        warp = spectral(n, 3.8, rng) * 18
        h = base * 0.5 + np.sin((X + warp * 3 + Y * 0.25) / 11.0) * 0.16
    else:
        h = base * 0.8
    if lum is not None:
        h = h + 0.5 * (lum - lum.mean()) / max(lum.std(), 1e-3)  # bright/dark terrain follows the imagery
    # Remove the sharpest detail: it reads as noise and makes slopes unfairly steep at game scale.
    small = Image.fromarray(h.astype(np.float32), mode="F").resize((n // 3, n // 3), Image.BOX)
    h = np.asarray(small.resize((n, n), Image.BICUBIC), dtype=np.float32)
    h = (h - h.min()) / (h.max() - h.min())
    return (h * relief_m - relief_m / 2).astype(np.float32)


def build_image_region(rid, r, bodies):
    print(f"Region {rid}: {r['name']} (real imagery, procedural relief)")
    lat, lon = r["lat"], r["lon"]
    gm = C.GLOBAL_MAPS[r["body"]]
    if r.get("nomen") and "trek" in gm:
        hit = nomen_lookup(gm["trek"][0], r["nomen"])
        if hit:
            lat, lon = hit
    w = r["width_deg"]
    dlat = min(w, 170 - abs(lat) * 2 + 40)
    lat0, lat1 = min(lat + dlat / 2, 89.5), max(lat - dlat / 2, -89.5)
    dlon = min(w / max(math.cos(math.radians(lat)), 0.2), 300)
    lon0, lon1 = lon - dlon / 2, lon + dlon / 2
    if "trek" in gm:
        col = trek_crop(*gm["trek"], lat0, lat1, lon0, lon1, COLOR_N, COLOR_N, want_px=COLOR_N // 2)
    else:
        im = Image.open(BytesIO(http(gm["url"]))).convert("RGB")
        W, H = im.size
        box = ((lon0 + 180) / 360 * W, (90 - lat0) / 180 * H, (lon1 + 180) / 360 * W, (90 - lat1) / 180 * H)
        col = im.resize((COLOR_N, COLOR_N), Image.BICUBIC, box=box)
    col = require_content(apply_tint(fill_gaps(col, gm.get("gap", 4)), gm.get("tint")), rid)
    lum = np.asarray(col.convert("L").resize((HEIGHT_N, HEIGHT_N), Image.BILINEAR), dtype=np.float32)
    seed = int(hashlib.sha256(rid.encode()).hexdigest()[:8], 16)
    h = procedural_relief(r["style"], r["relief_m"], lum, seed)
    body_R = bodies[r["body"]]["radius_km"]
    width_km = (lat0 - lat1) * 2 * math.pi * body_R / 360
    hscale = width_km * 1000 / WORLD_M
    vexag = max(1.0, min(30.0, 0.05 * WORLD_M * hscale / r["relief_m"]))  # keep relief readable on small moons
    rng = np.random.default_rng(seed)
    facts = bodies[r["body"]].get("facts", [])
    samples = ["regolith", "core", "rock", "core"]
    pois = []
    for i, f in enumerate(facts[:4]):
        ang = rng.random() * 0.8 + i * math.tau / 4
        rad = 0.16 + rng.random() * 0.22
        u, v = 0.5 + math.cos(ang) * rad, 0.5 + math.sin(ang) * rad
        elev = float(h[int(v * HEIGHT_N), int(u * HEIGHT_N)])
        pois.append({"name": f"Survey site {'ABCD'[i]}", "u": u, "v": v, "elev_m": None, "sample": samples[i], "fact": f, "elev_game": elev})
    info = {"id": rid, "body": r["body"], "name": r["name"], "real_elevation": False, "color_label": gm["credit"],
            "dem_label": "Procedural relief shaped by the real image (no bundled elevation data)", "width_km": round(width_km, 1),
            "landing_name": r["name"], "lat": lat, "lon": lon, "polar": False, "pois": pois, "landing_uv": (0.5, 0.5)}
    return save_terrain(rid, h, col, info, hscale, vexag)


# ------------------------------------------------------------------------------- pipeline
def write_json(name, obj):
    DATA.mkdir(exist_ok=True)
    (DATA / name).write_text(json.dumps(obj, indent=1, ensure_ascii=False), encoding="utf8")


def fetch_globals():
    (DATA / "textures").mkdir(parents=True, exist_ok=True)
    for bid, m in C.GLOBAL_MAPS.items():
        out = DATA / "textures" / f"{bid}.jpgdata"
        print("Global map:", bid)
        if "trek" in m:
            im = trek_global(*m["trek"], m["level"])
        else:
            im = Image.open(BytesIO(http(m["url"]))).convert("RGB")
            if im.width > 4096:
                im = im.resize((4096, 2048), Image.LANCZOS)
        im = require_content(apply_tint(fill_gaps(im, m.get("gap", 4)), m.get("tint")), bid)
        im.save(out, format="JPEG", quality=90)
        print(f"  {im.size} {out.stat().st_size // 1024} KB")


def fetch_fonts():
    (ROOT / "assets" / "fonts").mkdir(parents=True, exist_ok=True)
    for name, url in C.FONTS.items():
        (ROOT / "assets" / "fonts" / name).write_bytes(http(url))


def write_sources(bodies, exo, regions):
    L = ["# Data sources", "",
         f"Generated by `tools/fetch_data.py` on {PROVENANCE['generated']}. All data is bundled; the game never goes online.",
         "This game is not endorsed by NASA. NASA data and imagery are credited below under NASA's media usage guidelines.", "",
         "## Datasets", ""]
    L += [f"- {n}: {u}" for n, u in C.SOURCES_EXTRA]
    L += ["", "## Global planet and moon maps", ""]
    L += [f"- **{b.title()}**: {m['credit']}" + (f" ({m['url']})" if "url" in m else f" (layer `{m['trek'][1]}`)") for b, m in C.GLOBAL_MAPS.items()]
    L += ["- **Saturn, Uranus, Neptune, Triton**: no bundled map. Rendered with a procedural shader, labelled in-game.", "",
          "## Explorable regions", "", "| Region | Body | Elevation | Colour | Check against Treks 8-bit DEM |", "|---|---|---|---|---|"]
    for rid, r in regions.items():
        chk = r.get("trek_dem_check") or {}
        c = f"r = {chk['correlation']}, {chk['treks_m_per_grey_level']} m per grey level" if "correlation" in chk else "n/a"
        L.append(f"| {r['name']} | {r['body'].title()} | {r['dem_label']} | {r['color_label']} | {c} |")
    L += ["", "Elevations on real-data regions are true metres from NASA PDS. Scale and vertical exaggeration are shown in the HUD.",
          "PDS is used instead of the Treks DEM layers because Treks serves those as 8-bit images (see PLAN.md, D1).", "",
          "## Science facts", "", "Prose facts are verbatim quotes. Each was checked against the page text when this file was generated.", ""]
    urls = {}
    for b in bodies.values():
        for f in b.get("facts", []):
            urls[f["url"]] = urls.get(f["url"], 0) + 1
    for r in regions.values():
        for p in r["pois"]:
            urls[p["fact"]["url"]] = urls.get(p["fact"]["url"], 0) + 1
    for fl in exo["class_facts"].values():
        for f in fl:
            urls[f["url"]] = urls.get(f["url"], 0) + 1
    L += [f"- {u} ({n} facts)" for u, n in sorted(urls.items())]
    L += ["", f"Exoplanets: {len(exo['planets'])} confirmed planets from `pscomppars`; columns `{exo['columns']}`.",
          "Values the game computes rather than reads are labelled \"derived\" where they appear.", "",
          "## Not from NASA", "", "- Spacecraft part costs, masses and engine figures are game values.",
          "- Sky colours and exoplanet surfaces are artistic interpretation driven by the data above.",
          "- Fonts: Space Grotesk and JetBrains Mono (SIL Open Font License), from Google Fonts.",
          "- Sound and music: synthesised by `tools/make_audio.py`.",
          "- Region colour is display-graded: Viking haze patches are toned down on Mars and dark mare is exposed up on the Moon.",
          "- Black missing-data areas in Treks mosaics are filled from surrounding pixels. Venus (radar) and Titan (near-infrared) are tinted to suggest their appearance.", ""]
    if PROVENANCE["dropped_facts"]:
        L += ["## Facts dropped at build time", ""] + [f"- {d['where']}: {d['text'][:80]}" for d in PROVENANCE["dropped_facts"]] + [""]
    (DATA / "SOURCES.md").write_text("\n".join(L), encoding="utf8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="comma list: facts,exo,globals,regions,images,fonts")
    a = ap.parse_args()
    only = set(filter(None, a.only.split(",")))
    want = lambda k: not only or k in only  # noqa: E731
    CACHE.mkdir(exist_ok=True)
    DATA.mkdir(exist_ok=True)
    bodies = fetch_bodies()
    exo = fetch_exo()
    if want("facts"):
        write_json("bodies.json", bodies)
        write_json("elements.json", fetch_elements())
    if want("exo"):
        write_json("exoplanets.json", exo)
    if want("fonts"):
        fetch_fonts()
    if want("globals"):
        fetch_globals()
    regions = {}
    path = DATA / "regions.json"
    if path.exists():
        regions = json.loads(path.read_text(encoding="utf8"))
    if want("regions"):
        for rid, r in C.REGIONS.items():
            regions[rid] = build_dem_region(rid, r)
            write_json("regions.json", regions)
    if want("images"):
        for rid, r in C.IMAGE_REGIONS.items():
            regions[rid] = build_image_region(rid, r, bodies)
            write_json("regions.json", regions)
    write_sources(bodies, exo, regions)
    write_json("provenance.json", PROVENANCE)
    print("Done. Dropped facts:", len(PROVENANCE["dropped_facts"]))


if __name__ == "__main__":
    main()
