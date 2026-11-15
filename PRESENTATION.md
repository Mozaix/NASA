# Next Frontier Explorer

**NASA Space Apps Challenge 2026: Space Mission Design Game**

Players plan a real mission, fly it, land it, and drive across terrain built from NASA elevation data.
It runs from a USB stick on macOS, Windows and Linux, with no internet.

## What makes it different

**The ground is real.** Gale Crater, Mount Sharp, Valles Marineris, Olympus Mons, Jezero, Shackleton, Tycho and Tranquility Base
are built from NASA mission elevation data. The HUD shows true elevation in metres as you drive.

**The physics is real.** The planner uses Hohmann transfers and the rocket equation. It finds the actual Mars launch
opportunities of 16 November 2026 and 4 January 2029 from JPL's orbital elements. Each world's gravity changes how the rover handles.

**The facts are real, and that is enforced.** Every prose fact is a verbatim NASA quote. The build downloads each source
page and drops any quote it cannot find there. No facts were dropped in the final build.

**It is honest about what is not real.** Procedural terrain, tinted maps, computed values and game assumptions are all labelled on screen.

## NASA data used

| Data | Source | Used for |
|---|---|---|
| Colour mosaics | Solar System Treks (Viking MDIM2.1, LRO WAC, MESSENGER, Magellan, Galileo/Voyager, Cassini) | Globes and terrain colour |
| Elevation | PDS: MOLA MEGDR (Mars), LOLA LDEM and polar 20 m (Moon) | 7 explorable regions with real terrain |
| Planet and moon values | NSSDC Planetary and Satellite Fact Sheets | Gravity, mass, atmosphere, temperature |
| 50 exoplanets | Exoplanet Archive, `pscomppars` | Procedural worlds from real values |
| Planet positions | JPL approximate orbital elements | Launch windows and the cruise view |
| Star map | NASA SVS Deep Star Maps 2020 | The sky |
| 59 points of interest and 65 body facts | science.nasa.gov and nasa.gov | Fact cards |

Full credits are in `data/SOURCES.md` and in-game under Credits & Sources.

**A choice judges may ask about:** Treks serves elevation as 8-bit images, which gave Tranquility only 16 height levels in our test.
So heights come from the same missions' 16-bit PDS files, and the Treks layers are kept as a cross-check (correlation 0.99 or higher in every region tested).

## 3-minute demo

Before starting: launch the game, set Settings to Fullscreen, and return to the menu. Press **F2** for presenter mode:
a pitch timer against 3:00 and talking points for each screen, in the bottom-left corner. Press **F2** again for the timer only
if the notes should stay off the projector, and **F3** to restart the timer.

**0:00 Pitch (15 s).** "You plan a real mission and then land on real NASA terrain."

**0:15 Planner (45 s).** New Mission, with Mars selected.
- Point at the facts panel: every number comes from NASA.
- Open **Spacecraft** and drag Propellant down. Delta-v turns red: the rocket equation just said no. Click **Auto-design** to fix it.
- Open **Launch Window**. Drag the slider off the peak and watch the penalty rise. Click **Jump to the best window**.
- Open **Review**, then click **LAUNCH**.

**1:00 Launch and cruise (25 s).** Press Space to go for launch, then Space again to skip to T-10: "This is a concept spaceport in Bahrain, in 3D from NASA SRTM heights and Landsat imagery." After liftoff press **P** for the autopilot so the rocket stays out of the red. Say: "Stress peaks partway up, just like a real rocket's Max Q. If you hold it in the red, the rocket breaks up, and the game explains why." Press Space in the green for the departure burn.
In the cruise view, press **M** to switch to true scale: "This is how empty space really is." Press M again, then **Faster**. When the debris dodge appears: "You're riding on top of the spacecraft. Answer to fire the thrusters." Answer one question.

**1:25 Landing (25 s).** In orbit, click **Begin descent**. Press **P** for the autopilot, so the demo cannot crash.
Point out that the terrain below is real Mars elevation.

**1:50 Surface (45 s).** Drive to the nearest beacon. A NASA fact card appears with the elevation measured at that spot.
Hold **E** to collect a sample. Turn toward Mount Sharp: "This mountain is real, and the HUD shows the real elevation."

**2:35 Debrief (15 s).** Press Esc and end the mission. Point at "What this mission showed": it explains this flight using its own numbers, beside NASA quotes. Say that the same flow reaches 16 solar system worlds and 50 exoplanets.

**2:50 Close (10 s).** "Everything you saw runs offline, from NASA data, and every source is listed in the game."

**If you have more time:** Shackleton Crater is the most striking site, with long shadows and a dark crater floor. Press L for headlights.

## Other modes

**Play Demo** is a shorter mission with one planning page and a spinning hologram of the spacecraft. It asks three questions before the mission and offers the same three afterward, then shows the change for that player and the average on that computer. These numbers are a small, informal check, not a study.
**Play 2D** lets people build rockets, earn money from height and compete on today's leaderboard.
Each part card shows its predicted effect on height.

## Technical facts

- Godot 4.7.2 with the Mobile renderer. Terrain is displaced on the GPU from one shared mesh per detail level.
- Roughly 120 to 170 fps on average per scene, uncapped at 1600x900 on Medium, measured on an Apple M3 with 8 GB of memory. About 393 MB of video memory.
- Under 1 GB total on the USB stick, well under the 4 GB limit.
- Automated tests check the physics against published values, fly the autopilot onto every site, and drive the rover over real terrain.

## Known limits

- Terrain is compressed horizontally and exaggerated vertically so it can be driven. The HUD shows the scale for each site.
- The launch-window penalty is a simplified model, and the planner says so.
- Part costs and masses are game values, labelled as such. So are rocket stress and strength, trick scores, rover health and the autopilot's emergency thrust.
- Not endorsed by NASA.

## How the project meets the judging rubric

| Criterion | What to show or say |
|---|---|
| **Influence** | Free, and it runs offline on macOS, Windows, Linux or in any browser, so any school can use it. Classroom mode turns it into a lesson for a whole class at once. |
| **Creativity** | A complete mission in one game: plan with real orbital mechanics, fly, land on real terrain. The debris dodge turns learning questions into the action itself. |
| **Validity** | Hohmann transfers, the rocket equation and real launch windows from JPL elements. Verbatim NASA quotes checked against their source pages. 1,700+ automated checks. Simplifications are labelled on screen. |
| **Relevance** | Covers designing a mission (target, launcher, payload, window, budget), launch, cruise, orbit, landing and surface science, with tips on every screen, a demo mode and classroom tools. |
| **Presentation** | Presenter mode keeps the pitch to 3:00 with notes per screen. Pitch deck and showcase video are in `pitch/`. |
| **Use of data** | NASA elevation, imagery, fact sheets, orbits and the Exoplanet Archive drive every core feature. Debris questions use the mission's own NASA numbers. Limits are stated (heights ×5 at the launch site, game values for stress and score). |
| **Use of technology** | Real NASA terrain streamed into a game engine, procedurally built launch complex, first-person debris view, and one codebase for three desktops and the web. |
| **Local impact** | Launches from a 3D concept spaceport in Bahrain built from NASA data. Links to Bahrain's own satellite, Al Munther. Classroom mode and a printable lesson sheet for Bahraini schools. |
