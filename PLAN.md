# Next Frontier Explorer: Plan

NASA Space Apps Challenge 2026, "Space Mission Design Game".
Design a mission, fly it, land it, and explore real terrain built from NASA data.

## Stack

| Item | Choice | Reason |
|---|---|---|
| Engine | Godot 4.7.2, GDScript | As requested; latest stable at build time |
| Renderer | **Mobile** | Best fit for a 60 fps target on integrated GPUs. Volumetrics and SDFGI are not needed |
| Data pipeline | Python (`tools/fetch_data.py`), numpy + Pillow + certifi | Cached, re-runnable, records provenance |
| Runtime network | None | All data is bundled inside the game's `.pck` |

## Architecture

```
autoload/   Data (reads bundled JSON), Game (mission state), Orbital (physics),
            Settings (config + input map), Audio (procedural sound bus), Flow (scene changes)
scenes/     main_menu, planner, launch, transfer, orbit, landing, surface, debrief,
            archive, settings, credits  (scenes are thin; scripts build the content)
scripts/    terrain.gd (GPU chunk terrain), rover.gd, planet.gd, ui_kit.gd, fact_card.gd
shaders/    terrain, planet_procedural, atmosphere, rings, starfield, sun, cloud_deck
data/       processed JSON/textures/heightmaps + SOURCES.md (runtime data)
tools/      fetch_data.py, make_audio.py, smoke tests
USB_BUILD/  final exports
```

### Terrain: one shared grid mesh, displaced on the GPU
Height data stays in an `RF` texture. Chunks share a few grid meshes (one per LOD) and
are displaced in the vertex shader using per-instance uniforms. CPU cost is one distance
check per chunk, and skirts hide LOD cracks. The same heights feed `Terrain.height_at()`,
which drives the rover, lander and POI placement, so visuals and physics always agree.

## Scene flow

Main menu → Mission Planner → Launch → Transfer → Orbit → Landing → Surface → Debrief.
Side screens: Archive (every fact card and source), Settings, Credits.

## Milestones (one git commit each)

1. Data pipeline: `fetch_data.py`, processed data, `SOURCES.md`
2. Core: autoloads, UI kit, menu, orbital mechanics with tests
3. Vertical slice: planner → Mars landing → explore Gale Crater
4. Full flow: launch, transfer, orbit, debrief, scoring
5. All targets: moons, exoplanets, gas-giant probes, solar-system view with scale toggle
6. Polish: settings, gamepad, audio, archive, quality presets, performance pass
7. Export: three builds in `USB_BUILD/`, README, PRESENTATION

Every milestone: headless run to catch script errors, then fix errors and warnings.

## Decisions

Recorded as they are made. Anything that differs from the brief is marked **DEVIATION**.

### D1. **DEVIATION**: elevation comes from PDS 16-bit data, not Treks DEM tiles
The brief named Treks WMTS for elevation. Treks serves those layers as 8-bit greyscale PNGs.
Measured against the 16-bit products at global scale:

| Layer | Metres per grey level | RMS against PDS |
|---|---|---|
| `Mars_MGS_MOLA_DEM_mosaic_global_463m_8` | 114.9 m | 164 m |
| `LRO_LOLA_DEM_Global_128ppd_v04` | 77.0 m | 290 m |

That quantisation shows up as stair-stepped crater walls and makes heights unreliable.
So heights are read from the same missions' NASA PDS products, which are true 16-bit metres
fetched with HTTP range requests:

- Mars: MOLA MEGDR 128 pixels/degree (`mgs-m-mola-5-megdr-l3-v1`)
- Moon: LOLA LDEM 128 pixels/degree, and the 20 m polar product for Shackleton (`lro-l-lola-3-rdr-v1`)

Treks is still the source for all colour mosaics. `fetch_data.py` also downloads the Treks DEM
for each region and records the correlation against PDS in `data/SOURCES.md`, so the
substitution can be checked. If PDS is unreachable it falls back to smoothed Treks data
and marks the region as such.

### D2. Terrain scale is compressed, and the game says so
Real regions are tens to hundreds of km across. Each region declares a horizontal scale and a
vertical exaggeration, and the HUD displays both. Real elevation readouts are converted back
to true metres, so numbers on screen are measured data rather than game units.

### D3. Facts must be traceable
Numeric facts come from parsed fact sheets. Prose facts live in a curated list, each with a
source URL and a phrase that `fetch_data.py` must find in the downloaded page. A fact that fails
this check is dropped from the game. Values the game computes itself are labelled "derived".

### D4. Bodies without good elevation data
Where there is a real image mosaic but no bundled DEM, the surface uses real imagery with
procedural relief, labelled in the UI. Exoplanet surfaces are procedural from archive values,
also labelled. Gas and ice giants have no surface, so the player flies an atmospheric probe.

### D5. Exoplanet travel is a stated game assumption
A Hohmann transfer does not apply between stars. The planner shows the honest time at
Voyager-like speed, then offers a concept interstellar sail with a clearly labelled assumed speed.

### D6. Spacecraft parts are game values
Costs, masses and Isp are gameplay values in the range of real hardware. They are labelled
as game values and never presented as NASA facts.

### D7. Audio is synthesised
All sound is generated by `tools/make_audio.py`, so there are no licensing questions.

### D8. No NASA logos
NASA data is credited, but NASA insignia are not used, following NASA's media usage guidelines.
The game states that it is not endorsed by NASA.

### D9. Shackleton is shaded from elevation, not the WAC mosaic
The WAC global mosaic shows hard wedge-shaped seams this close to the pole. The Shackleton surface is
therefore shaded directly from the 20 m LOLA polar heights and labelled as such. Tranquility and Tycho use WAC.

### D10. Treks zoom levels are tested, not trusted
Treks capabilities can advertise zoom levels that have no tiles. The pipeline probes for a real tile
and stops with an error if an image comes out mostly black, instead of shipping blank terrain.

### D11. Natural colour over science products
Mercury uses the MESSENGER BDR basemap rather than the false-colour enhanced map, which is bright blue
and would mislead. Venus (radar) and Titan (near-infrared) are tinted, and the credit says so.

### D12. Colour is display-graded, and says so
Viking's blue-white haze reads as snow, and dark lunar mare is hard to see, so region colour is graded for
display. Heights and positions are untouched. Missing-data gaps are filled from nearby pixels. `SOURCES.md` states both.

### D13. Landing pads move to the nearest flat ground
Height exaggeration turns real slopes into impossible ones. A pad stays on its real coordinate when that ground
is safe (Gale, Jezero, Olympus, Tranquility), and otherwise moves to the nearest safe spot (Valles 7.5 km real, Shackleton 1.8 km).
On procedural sites the move can be larger in "real" km, which has no meaning there because the relief is generated.

### D14. Physics follows the rendered triangles
`Terrain.height_at()` uses the same triangles and diagonal as the finest mesh, and the chunk under the vehicle is
always the finest mesh. This removed a gap of up to 0.35 m that let vehicles sink into the ground.

### D15. macOS signing happens outside `~/Documents`
iCloud's file provider adds attributes to files in `~/Documents`, and `codesign` rejects them. `tools/export_all.sh`
signs ad hoc in a temporary folder, verifies the result, and also ships a zip. The app is not notarized,
because that needs a paid Apple Developer account.

## Status

All seven milestones are complete. `godot --headless --path . res://tests/run_tests.tscn` runs the test suite.

Not tested on real hardware or platforms:
- The Windows and Linux executables were never run. Only their game data packs were run, on this Mac's engine.
- Gatekeeper's behaviour on another Mac. This Mac let a quarantined copy run, so it cannot show what a judge would see.
- A physical gamepad. Bindings were tested with simulated events.
- A physical USB stick. A real exFAT disk image was used instead.

## Added after the first release

- **Demo mode, new HUD, look-down landing view, smoother terrain.**
- **2D Rocket Builder.** Part stats are game values. Earth's values and the height milestones come from NASA sources.
  Each game is 6 launches. Money and parts reset after a score is saved. Scores are kept per calendar day on the local computer.
- **Player-report fixes.** Launch stress can break up the rocket (a game value shaped like real dynamic pressure), spin tricks with a multiplier on the rocket and in rover jumps (bonus capped at 100 mission points), rover health and solid rocks (repair at the lander), brighter headlights, smoother probe.
  The autopilot can overdrive the engine when a late handover needs it (a game value), and diverts to safe ground if it can't reach the pad.
  An off-window or slow-engine transfer now bends its path to meet the planet on arrival day. It is not a true Hohmann arc in those cases, and the off-window delta-v penalty stands for that cost.
