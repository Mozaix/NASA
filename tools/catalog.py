"""Static catalogue for fetch_data.py: which NASA sources to pull and how to use them.

Everything prose-like here is a VERBATIM quote from a NASA page. fetch_data.py downloads each
page and drops any fact whose text is not found in it, so a typo or an invented claim cannot
reach the game.
"""

SCI = "https://science.nasa.gov/"
TREK = "https://trek.nasa.gov/tiles"
PDS = "https://pds-geosciences.wustl.edu"

# ---------------------------------------------------------------------------------------------
# Bodies that can be mission targets. col is the column in the planetary fact sheet;
# sat = (fact sheet page, row label) for moons.
# ---------------------------------------------------------------------------------------------
PLANETS = {
    "mercury": {"name": "Mercury", "col": "MERCURY", "page": "mercuryfact.html"},
    "venus": {"name": "Venus", "col": "VENUS", "page": "venusfact.html"},
    "earth": {"name": "Earth", "col": "EARTH", "page": "earthfact.html"},
    "mars": {"name": "Mars", "col": "MARS", "page": "marsfact.html"},
    "jupiter": {"name": "Jupiter", "col": "JUPITER", "page": "jupiterfact.html"},
    "saturn": {"name": "Saturn", "col": "SATURN", "page": "saturnfact.html"},
    "uranus": {"name": "Uranus", "col": "URANUS", "page": "uranusfact.html"},
    "neptune": {"name": "Neptune", "col": "NEPTUNE", "page": "neptunefact.html"},
}
MOONS = {
    "moon": {"name": "Moon", "parent": "earth", "col": "MOON", "page": "moonfact.html"},
    "io": {"name": "Io", "parent": "jupiter", "sat": ("joviansatfact.html", "Io")},
    "europa": {"name": "Europa", "parent": "jupiter", "sat": ("joviansatfact.html", "Europa")},
    "ganymede": {"name": "Ganymede", "parent": "jupiter", "sat": ("joviansatfact.html", "Ganymede")},
    "callisto": {"name": "Callisto", "parent": "jupiter", "sat": ("joviansatfact.html", "Callisto")},
    "titan": {"name": "Titan", "parent": "saturn", "sat": ("saturniansatfact.html", "Titan")},
    "enceladus": {"name": "Enceladus", "parent": "saturn", "sat": ("saturniansatfact.html", "Enceladus")},
    "triton": {"name": "Triton", "parent": "neptune", "sat": ("neptuniansatfact.html", "Triton")},
}

# ---------------------------------------------------------------------------------------------
# Global colour maps. Treks layers are stitched from WMTS tiles. level 2 = 2048x1024, 3 = 4096x2048.
# ---------------------------------------------------------------------------------------------
GLOBAL_MAPS = {
    "mars": {"trek": ("Mars", "Mars_Viking_MDIM21_ClrMosaic_global_232m"), "level": 3,
             "credit": "Viking MDIM2.1 colour mosaic (NASA/USGS), via NASA Solar System Treks"},
    "moon": {"trek": ("Moon", "LRO_WAC_Mosaic_Global_303ppd_v02"), "level": 3,
             "credit": "LRO WAC global mosaic (NASA/GSFC/ASU), via NASA Solar System Treks"},
    "mercury": {"trek": ("Mercury", "Mercury_MESSENGER_MDIS_Basemap_BDR_Mosaic_Global_166m"), "level": 2,
                "credit": "MESSENGER MDIS BDR basemap (NASA/JHUAPL), via NASA Solar System Treks"},
    "venus": {"trek": ("Venus", "Venus_Magellan_C3-MDIR_Global_Mosaic_2025m"), "level": 2, "gap": 22, "tint": (1.0, 0.82, 0.58),
              "credit": "Magellan C3-MDIR radar mosaic, tinted (NASA/JPL), via NASA Solar System Treks"},
    "io": {"trek": ("Io", "Io_GalileoSSI_Voyager_Global_Mosaic_ClrMerge_1km"), "level": 2,
           "credit": "Voyager ISS + Galileo SSI colour mosaic (NASA/USGS), via NASA Solar System Treks"},
    "europa": {"trek": ("Europa", "Europa_Voyager_GalileoSSI_global_mosaic_500m"), "level": 2,
               "credit": "Voyager + Galileo SSI mosaic (NASA/USGS), via NASA Solar System Treks"},
    "ganymede": {"trek": ("Ganymede", "Ganymede_Voyager_GalileoSSI_Global_ClrMosaic_1435m"), "level": 2,
                 "credit": "Voyager + Galileo SSI colour mosaic (NASA/USGS), via NASA Solar System Treks"},
    "callisto": {"trek": ("Callisto", "Callisto_Voyager_GalileoSSI_global_mosaic_1km"), "level": 2,
                 "credit": "Voyager + Galileo SSI mosaic (NASA/USGS), via NASA Solar System Treks"},
    "titan": {"trek": ("Titan", "Titan_ISS_P19658_Mosaic_Global_4km"), "level": 2, "gap": 16, "tint": (1.0, 0.78, 0.46),
              "credit": "Cassini ISS global mosaic PIA19658, tinted (NASA/JPL/SSI), via NASA Solar System Treks"},
    "enceladus": {"trek": ("Enceladus", "Enceladus_cyl_KH"), "level": 2,
                  "credit": "Cassini ISS colour mosaic (NASA/JPL/SSI), via NASA Solar System Treks"},
    "earth": {"url": "https://svs.gsfc.nasa.gov/vis/a000000/a002900/a002915/bluemarble-2048.png",
              "credit": "Blue Marble (NASA Scientific Visualization Studio, animation 2915)"},
    "jupiter": {"url": "https://images-assets.nasa.gov/image/PIA07782/PIA07782~orig.jpg",
                "credit": "Cassini cylindrical map of Jupiter, PIA07782 (NASA/JPL/SSI)"},
}
# Saturn, Uranus, Neptune and Triton have no suitable bundled global map: they use a labelled
# procedural shader driven by real values.

# ---------------------------------------------------------------------------------------------
# Explorable regions with REAL elevation (16-bit PDS). width_km is real-world width.
# ---------------------------------------------------------------------------------------------
_MDIM = ("Mars", "Mars_Viking_MDIM21_ClrMosaic_global_232m")
_MDEM = ("Mars", "Mars_MGS_MOLA_DEM_mosaic_global_463m_8")
_WAC = ("Moon", "LRO_WAC_Mosaic_Global_303ppd_v02")
_LDEM8 = ("Moon", "LRO_LOLA_DEM_Global_128ppd_v04")

REGIONS = {
    "gale": {
        "body": "mars", "name": "Gale Crater", "lat": -5.2, "lon": 137.6, "width_km": 190.0, "vexag": 2.5,
        "trek": _MDIM, "trek_dem": _MDEM, "dem": ("mola", "megt00n090hb"),
        "dem_label": "MOLA MEGDR 128 pixels/degree", "landing": "Aeolis Palus (Curiosity's plain)",
        "landing_ll": (-4.59, 137.44),
        "pois": [
            {"name": "Bradbury Landing", "lat": -4.5895, "lon": 137.4417, "url": SCI + "mission/msl-curiosity/science/",
             "text": "Landing at Gale Crater, Mars Science Laboratory is assessing whether Mars ever had an environment capable of supporting microbial life.", "sample": "regolith"},
            {"name": "Aeolis Mons (Mount Sharp)", "nomen": "Aeolis Mons", "lat": -5.083, "lon": 137.845, "url": SCI + "mission/msl-curiosity/science/",
             "text": "At center is the \"clay-bearing unit,\" a region with a unique story to tell about the history of water on Mount Sharp, the 3-mile-tall (5-kilometer-tall) mountain Curiosity has been ascending since 2014.", "sample": "core"},
            {"name": "Yellowknife Bay", "lat": -4.59, "lon": 137.46, "url": SCI + "mission/msl-curiosity/",
             "text": "Early in its mission, Curiosity's scientific tools found chemical and mineral evidence of past habitable environments on Mars.", "sample": "core"},
            {"name": "Crater floor sediments", "lat": -5.55, "lon": 137.25, "url": SCI + "mission/msl-curiosity/",
             "text": "It hunts for special rocks that formed in water and/or have signs of organics.", "sample": "rock"},
            {"name": "Gale's northern rim", "lat": -4.25, "lon": 137.95, "url": SCI + "mars/facts/",
             "text": "NASA missions have found lots of evidence that Mars was much wetter and warmer, with a thicker atmosphere, billions of years ago.", "sample": "rock"},
        ],
    },
    "jezero": {
        "body": "mars", "name": "Jezero Crater", "lat": 18.45, "lon": 77.5, "width_km": 90.0, "vexag": 3.0,
        "trek": _MDIM, "trek_dem": _MDEM, "dem": ("mola", "megt44n000hb"),
        "dem_label": "MOLA MEGDR 128 pixels/degree", "landing": "Octavia E. Butler landing site",
        "landing_ll": (18.4447, 77.4508),
        "pois": [
            {"name": "Octavia E. Butler Landing", "lat": 18.4447, "lon": 77.4508, "url": SCI + "mission/mars-2020-perseverance/mars-rock-samples/",
             "text": "NASA’s Perseverance rover landed in Jezero Crater, an area with an ancient delta, on Feb. 18, 2021.", "sample": "regolith"},
            {"name": "Western delta", "lat": 18.51, "lon": 77.39, "url": SCI + "mission/mars-2020-perseverance/",
             "text": "Scientists believe the area was once flooded with water and was home to an ancient river delta.", "sample": "core"},
            {"name": "Crater lake floor", "lat": 18.36, "lon": 77.62, "url": SCI + "mission/mars-2020-perseverance/",
             "text": "The rover discovered a habitable, stable lake, delta, and river system in Jezero Crater's history.", "sample": "rock"},
            {"name": "Sampling area", "lat": 18.47, "lon": 77.42, "url": SCI + "mission/mars-2020-perseverance/",
             "text": "These samples record the history of the Jezero Crater landing site, and may even preserve signs of ancient life.", "sample": "core"},
        ],
    },
    "valles": {
        "body": "mars", "name": "Valles Marineris (Coprates)", "lat": -13.3, "lon": -62.5, "width_km": 340.0, "vexag": 1.6,
        "trek": _MDIM, "trek_dem": _MDEM, "dem": ("mola", "megt00n270hb"),
        "dem_label": "MOLA MEGDR 128 pixels/degree", "landing": "Coprates Chasma floor",
        "landing_ll": (-13.3, -62.0),
        "pois": [
            {"name": "Coprates Chasma", "nomen": "Coprates Chasma", "lat": -13.3, "lon": -61.5, "url": SCI + "resource/valles-marineris-the-grand-canyon-of-mars/",
             "text": "The canyon runs about 2,400 miles (3,870 kilometers) in length, spans about 370 miles (600 kilometers) across at its widest, and descends about 5.8 miles (9.3 kilometers) at its deepest.", "sample": "core"},
            {"name": "Canyon system overview", "lat": -12.2, "lon": -63.3, "url": SCI + "resource/valles-marineris-the-grand-canyon-of-mars/",
             "text": "The center of the scene shows the entire Valles Marineris canyon system, extending from Noctis Labyrinthus, the arcuate system of graben to the west, to the chaotic terrain to the east.", "sample": "rock"},
            {"name": "Southern plateau", "lat": -15.2, "lon": -62.5, "url": SCI + "resource/valles-marineris-the-grand-canyon-of-mars/",
             "text": "South of Valles Marineris is very ancient terrain covered by many impact craters.", "sample": "regolith"},
            {"name": "Tharsis view", "lat": -14.2, "lon": -64.0, "url": SCI + "resource/valles-marineris-the-grand-canyon-of-mars/",
             "text": "The three Tharsis volcanoes (dark red spots), each about 25 kilometers high, are visible to the west.", "sample": "rock"},
        ],
    },
    "olympus": {
        "body": "mars", "name": "Olympus Mons", "lat": 18.65, "lon": -133.8, "width_km": 760.0, "vexag": 1.5,
        "trek": _MDIM, "trek_dem": _MDEM, "dem": ("mola", "megt44n180hb"),
        "dem_label": "MOLA MEGDR 128 pixels/degree", "landing": "Southern flank of Olympus Mons",
        "landing_ll": (17.0, -133.8),
        "pois": [
            {"name": "Olympus Mons summit", "nomen": "Olympus Mons", "lat": 18.65, "lon": -133.8, "url": SCI + "mars/facts/",
             "text": "This dynamic planet has seasons, polar ice caps, extinct volcanoes, canyons, and weather.", "sample": "rock"},
            {"name": "Aureole plains", "lat": 21.6, "lon": -136.4, "url": SCI + "photojournal/olympus-mons/",
             "text": "Much of the plains surrounding the volcano are covered by the ridged and grooved 'aureole' of Olympus Mons.", "sample": "regolith"},
            {"name": "Southern escarpment", "lat": 15.9, "lon": -133.6, "url": SCI + "mars/facts/",
             "text": "Instead, they're looking for signs of life that existed long ago, when Mars was warmer and covered with water.", "sample": "core"},
        ],
    },
    "shackleton": {
        "body": "moon", "name": "Shackleton Crater", "lat": -89.67, "lon": 129.2, "width_km": 80.0, "vexag": 2.0,
        "polar": True, "trek": _WAC, "dem": ("ldem_polar", "polar/img/ldem_85s_20m"),
        "dem_label": "LOLA polar LDEM, 20 m/pixel", "landing": "Connecting ridge near the south pole",
        "landing_offset_km": (11.0, 4.0),
        "pois": [
            {"name": "Shackleton rim", "offset_km": (9.5, 0.0), "url": SCI + "moon/moon-water-and-ices/",
             "text": "These lightless areas of the Moon are called “permanently shadowed regions.”", "sample": "regolith"},
            {"name": "Permanently shadowed floor", "offset_km": (0.0, 0.0), "url": SCI + "moon/moon-water-and-ices/",
             "text": "The LRO and LCROSS findings added to a growing body of evidence that water exists on the Moon in the form of ice within permanently shadowed regions.", "sample": "core"},
            {"name": "Ice prospecting site", "offset_km": (-12.0, 14.0), "url": SCI + "moon/facts/",
             "text": "The discovery that the Moon harbors water ice , and that the highest concentrations occur within darkened craters at the poles, makes the Moon a little more hospitable for future human colonists.", "sample": "core"},
            {"name": "South polar ridge", "offset_km": (14.0, 12.0), "url": SCI + "mission/lro/",
             "text": "The orbiter is also helping NASA identify areas near the Moon’s South Pole with crucial resources like water and extended sunlight, which provides power for equipment and supports exploration activities.", "sample": "rock"},
        ],
    },
    "tranquility": {
        "body": "moon", "name": "Tranquility Base", "lat": 0.67, "lon": 23.47, "width_km": 70.0, "vexag": 5.0,
        "trek": _WAC, "trek_dem": _LDEM8, "dem": ("ldem", "cylindrical/img/ldem_128"),
        "dem_label": "LOLA LDEM 128 pixels/degree", "landing": "Sea of Tranquility", "landing_ll": (0.60, 23.30),
        "pois": [
            {"name": "Apollo 11 landing site", "lat": 0.6741, "lon": 23.4730, "url": "https://www.nasa.gov/history/apollo-11-mission-overview/",
             "text": "Partially piloted manually by Armstrong, the Eagle landed in the Sea of Tranquility in Site 2 at 0 degrees, 41 minutes, 15 seconds north latitude and 23 degrees, 26 minutes east longitude.", "sample": "regolith"},
            {"name": "Mare basalts", "lat": 0.35, "lon": 23.80, "url": SCI + "moon/facts/",
             "text": "Apollo astronauts brought back a total of 842 pounds (382 kilograms) of lunar rocks and soil to Earth.", "sample": "rock"},
            {"name": "Cratered mare", "lat": 0.95, "lon": 23.10, "url": SCI + "moon/facts/",
             "text": "The Moon has a solid, rocky surface cratered and pitted from impacts by asteroids, meteorites, and comets.", "sample": "core"},
        ],
    },
    "tycho": {
        "body": "moon", "name": "Tycho Crater", "lat": -43.3, "lon": -11.2, "width_km": 150.0, "vexag": 2.0,
        "trek": _WAC, "trek_dem": _LDEM8, "dem": ("ldem", "cylindrical/img/ldem_128"),
        "dem_label": "LOLA LDEM 128 pixels/degree", "landing": "Tycho crater floor", "landing_ll": (-43.0, -11.6),
        "pois": [
            {"name": "Tycho central peak", "nomen": "Tycho", "lat": -43.3, "lon": -11.2, "url": SCI + "moon/lunar-craters/",
             "text": "Lunar impact craters are the depressions left behind after an asteroid, meteoroid, or comet collides with the Moon.", "sample": "rock"},
            {"name": "Tycho rim", "lat": -42.5, "lon": -11.3, "url": SCI + "moon/lunar-craters/",
             "text": "Moon craters fascinate us because they are a record of the process that built and shaped our entire solar system, the fingerprints of history pressed into the lunar surface .", "sample": "core"},
            {"name": "Ejecta blanket", "lat": -44.3, "lon": -12.2, "url": SCI + "moon/facts/",
             "text": "The Moon has a solid, rocky surface cratered and pitted from impacts by asteroids, meteorites, and comets.", "sample": "regolith"},
        ],
    },
}

# Regions with real imagery but procedural relief (labelled in-game).
# Crop centre and width in degrees, cut from Treks tiles of the body's global map.
IMAGE_REGIONS = {
    "mercury_site": {"body": "mercury", "name": "Caloris Planitia", "nomen": "Caloris Planitia", "lat": 30.0, "lon": 161.0, "width_deg": 24.0, "style": "cratered", "relief_m": 2500},
    "venus_site": {"body": "venus", "name": "Maxwell Montes", "nomen": "Maxwell Montes", "lat": 65.0, "lon": 3.3, "width_deg": 26.0, "style": "volcanic", "relief_m": 6000},
    "earth_site": {"body": "earth", "name": "Florida coast", "lat": 28.5, "lon": -81.0, "width_deg": 22.0, "style": "rolling", "relief_m": 800},
    "io_site": {"body": "io", "name": "Loki Patera", "nomen": "Loki Patera", "lat": 13.0, "lon": 51.0, "width_deg": 26.0, "style": "volcanic", "relief_m": 3500},
    "europa_site": {"body": "europa", "name": "Conamara Chaos", "nomen": "Conamara Chaos", "lat": 9.5, "lon": -86.0, "width_deg": 24.0, "style": "icy", "relief_m": 900},
    "ganymede_site": {"body": "ganymede", "name": "Galileo Regio", "nomen": "Galileo Regio", "lat": 35.0, "lon": -145.0, "width_deg": 24.0, "style": "icy_cratered", "relief_m": 1800},
    "callisto_site": {"body": "callisto", "name": "Valhalla", "nomen": "Valhalla", "lat": 14.0, "lon": -56.0, "width_deg": 26.0, "style": "cratered", "relief_m": 2200},
    "titan_site": {"body": "titan", "name": "Huygens landing region", "lat": -10.3, "lon": 167.7, "width_deg": 28.0, "style": "dunes", "relief_m": 700},
    "enceladus_site": {"body": "enceladus", "name": "South polar terrain", "lat": -72.0, "lon": 60.0, "width_deg": 30.0, "style": "icy", "relief_m": 1200},
}

# ---------------------------------------------------------------------------------------------
# Prose facts per body: verbatim quotes, verified against the downloaded page.
# ---------------------------------------------------------------------------------------------
def _q(path, *texts, base=SCI):
    return [{"text": t, "url": base + path} for t in texts]

BODY_FACTS = {
    "mercury": _q("mercury/facts/",
        "Because the planet is so close to the Sun, day temperatures can reach highs of 800°F (430°C).",
        "Without an atmosphere to retain that heat at night, temperatures can dip as low as -290°F (-180°C).",
        "Despite its proximity to the Sun, Mercury is not the hottest planet in our solar system – that title belongs to nearby Venus, thanks to its dense atmosphere.",
        "But Mercury is the fastest planet, zipping around the Sun every 88 Earth days.")
        + _q("mission/messenger/", "MESSENGER finally entered orbit around Mercury at 00:45 UT March 18, 2011, nearly seven years after launch."),
    "venus": _q("venus/facts/",
        "It's the hottest planet in our solar system, and is sometimes called Earth's twin.",
        "And the atmospheric pressure at the surface is about 93 times what it is at sea level on Earth.",
        "Below Venus' dense, persistent clouds, the surface has volcanoes and deformed mountains.",
        "At the tops of Venus’ clouds, whipped around the planet by winds measured as high as 224 mph (360 kph), we find another transformation.")
        + _q("mission/magellan/", "Magellan was designed to use a Synthetic Aperture Radar (SAR) to map 70% of the Venusian surface down to a resolution of 390 to 985 feet (120 to 300 meters)."),
    "earth": _q("earth/facts/",
        "Most notably, Earth is unique in that most of our planet is covered in liquid water, since the temperature allows liquid water to exist for extended periods of time.",
        "Earth's vast oceans provided a convenient place for life to begin about 3.8 billion years ago.",
        "Earth's axis of rotation is tilted 23.4 degrees with respect to the plane of Earth's orbit around the Sun.",
        "As Earth orbits the Sun, it completes one rotation every 23.9 hours."),
    "moon": _q("moon/facts/",
        "The Moon has a very thin and tenuous atmosphere called an exosphere.",
        "Apollo astronauts brought back a total of 842 pounds (382 kilograms) of lunar rocks and soil to Earth.",
        "Humans didn't see the lunar far side until a Soviet spacecraft flew past in 1959.",
        "The Moon's weak atmosphere and its lack of liquid water cannot support life as we know it."),
    "mars": _q("mars/facts/",
        "This dynamic planet has seasons, polar ice caps, extinct volcanoes, canyons, and weather.",
        "NASA missions have found lots of evidence that Mars was much wetter and warmer, with a thicker atmosphere, billions of years ago.",
        "From this distance, it takes sunlight 13 minutes to travel from the Sun to Mars.")
        + _q("mission/viking-1/", "NASA's Viking 1 made the first truly successful landing on Mars.")
        + _q("mission/mars-pathfinder/", "The computer inflated these large air bags about 330 feet (100 meters) above the surface of Mars."),
    "jupiter": _q("jupiter/facts/",
        "It's the largest planet in our solar system – if it were a hollow shell, 1,000 Earths could fit inside.",
        "But it has the shortest day in the solar system, taking about 9.9 hours to spin around once on its axis.",
        "Jupiter’s iconic Great Red Spot is a giant storm bigger than Earth that has raged for hundreds of years.",
        "From this distance, it takes sunlight 43 minutes to travel from the Sun to Jupiter."),
    "saturn": _q("saturn/facts/",
        "Saturn is not the only planet to have rings, but none are as spectacular or as complex as Saturn's.",
        "From the jets of water that spray from Saturn's moon Enceladus to the methane lakes on smoggy Titan , the Saturn system is a rich source of scientific discovery and still holds many mysteries.",
        "From this distance, it takes sunlight 80 minutes to travel from the Sun to Saturn.")
        + _q("mission/cassini/", "It began the first in-depth, up-close study of Saturn and its system of rings and moons in 2004."),
    "uranus": _q("uranus/facts/",
        "The ice giant is surrounded by 13 faint rings and 28 small moons.",
        "Uranus rotates at a nearly 90-degree angle from the plane of its orbit.",
        "It was discovered in 1781 by astronomer William Herschel, although he originally thought it was either a comet or a star.",
        "From this distance, it takes sunlight 2 hours and 40 minutes to travel from the Sun to Uranus."),
    "neptune": _q("neptune/facts/",
        "In 2011 Neptune completed its first 165-year orbit since its discovery in 1846.",
        "The warm light we see here on our home planet is roughly 900 times as bright as sunlight on Neptune.",
        "More than 200 years later, the ice giant became the first planet located through mathematical predictions rather than through regular observations of the sky.")
        + _q("mission/cassini/", "So far, each of these worlds has been visited by only one brief spacecraft flyby (Voyager 2, in 1986 and 1989, respectively)."),
    "io": _q("jupiter/jupiter-moons/io/",
        "Io is caught in a tug-of-war between Jupiter's massive gravity and the smaller but precisely timed pulls from two neighboring moons that orbit farther from Jupiter—Europa and Ganymede.",
        "Io’s volcanoes are at times so powerful that they are seen with large telescopes on Earth, and Io even has lakes of molten silicate lava on its surface.",
        "It was Voyager 1 that spotted the first signs of the little moon’s powerful volcanism in 1979."),
    "europa": _q("jupiter/jupiter-moons/europa/europa-facts/",
        "It shows strong evidence for an ocean of liquid water beneath its icy crust.",
        "Based on Europa's icy composition, scientists think the most likely material to create this magnetic signature is a global ocean of salty water.")
        + _q("mission/europa-clipper/",
        "Europa Clipper will try to determine if Jupiter's icy moon Europa currently has habitable conditions.",
        "It will orbit Jupiter, and conduct 49 close flybys of Europa."),
    "ganymede": _q("jupiter/jupiter-moons/ganymede/",
        "Jupiter’s icy moon Ganymede is the largest moon in our solar system, even bigger than the planet Mercury, and the dwarf planet Pluto.",
        "There’s strong evidence that Ganymede has an underground saltwater ocean that may hold more water than all the water on Earth's surface.",
        "The dark areas are the older, more heavily cratered regions and the light areas are younger, tectonically deformed regions."),
    "callisto": _q("jupiter/jupiter-moons/callisto/",
        "Callisto is Jupiter’s second largest moon and the third largest moon in our solar system.",
        "Data from NASA’s Galileo spacecraft in the 1990s revealed Callisto may have a secret: a salty ocean beneath its surface.",
        "Galileo orbited Jupiter until the mission ended in 2003."),
    "titan": _q("saturn/moons/titan/facts/",
        "It has clouds, rain, rivers, lakes and seas of liquid hydrocarbons like methane and ethane.",
        "This mammoth moon is the only moon in the solar system with a dense atmosphere, and it’s the only world besides Earth that has standing bodies of liquid, including rivers, lakes and seas, on its surface.",
        "Like Earth, Titan’s atmosphere is primarily nitrogen, plus a small amount of methane.",
        "Titan is also thought to have a subsurface ocean of water.")
        + _q("mission/dragonfly/", "Dragonfly is expected to make one flight every 1-2 Titan days, which is called a Tsol and lasts about 16 Earth days."),
    "enceladus": _q("saturn/moons/enceladus/",
        "A handful of worlds are thought to have liquid water oceans beneath their frozen shell, but Enceladus sprays its ocean out into space where spacecraft can sample it.",
        "From these samples, scientists have determined that Enceladus has most of the chemical ingredients needed for life, and likely has hydrothermal vents releasing hot, mineral-rich water into its ocean.",
        "Because Enceladus reflects so much sunlight, the surface temperature is extremely cold, about minus 330 degrees Fahrenheit (minus 201 degrees Celsius).",
        "In particular, the south polar region of Enceladus is almost entirely free of impact craters."),
    "triton": _q("neptune/moons/triton/",
        "Triton's thin atmosphere is composed mainly of nitrogen with small amounts of methane.",
        "It is so cold that most of Triton's nitrogen is condensed as frost, giving its surface an icy sheen that reflects 70 percent of the sunlight that hits it.",
        "NASA's Voyager 2―the only spacecraft to fly past Neptune and Triton―found surface temperatures of -391degrees Fahrenheit (-235 degrees Celsius).",
        "During its 1989 flyby, Voyager 2 also found Triton has active geysers, making it one of the few geologically active moons in our solar system."),
}

# General exoplanet science, grouped by the planet class that fetch_data.py derives.
EXO_FACTS = {
    "terrestrial": _q("exoplanets/terrestrial/",
        "Terrestrial planets (Earth sized and smaller) are rocky worlds, composed of rock, silicate, water and/or carbon.",
        "To determine if some of these worlds have atmospheres, oceans or other signs of habitability, it takes more investigation.",
        "We've found rocky planets in Earth's size range, at the right distance from their parent stars to harbor liquid water (this is known as the habitable zone)."),
    "super_earth": _q("exoplanets/terrestrial/",
        "Larger terrestrial exoplanets (those at least twice as massive as Earth) are classified as super-Earths .")
        + _q("exoplanets/super-earth/", "Super-Earths can be up to 10 times more massive than Earth."),
    "neptune_like": _q("exoplanets/neptune-like/",
        "Neptunian planets typically have hydrogen and helium-dominated atmospheres with cores of rock and heavier metals.",
        "By analyzing the amount of light blocked by the planet at different wavelengths, called spectroscopy, researchers can determine which molecules make up the atmosphere."),
    "gas_giant": _q("exoplanets/gas-giant/",
        "Similar in size to Jupiter, these gas-dominated planets orbit extremely close to their parent stars, circling them in as few as 18 hours.")
        + _q("exoplanets/planet-types/",
        "Gas giants are planets the size of Saturn or Jupiter, the largest planet in our solar system, or much, much larger.",
        "They likely have a mixture of interior compositions, but all will have hydrogen and helium-dominated outer atmospheres and rocky cores."),
    "general": _q("exoplanets/planet-types/",
        "Most have been discovered by the \"transit\" method – watching for the tiniest of shadows as a planet crosses the face of its star.",
        "Our nearest neighboring star, Proxima Centauri, was found to possess at least one planet – probably a rocky one."),
}

# Exoplanets chosen by name so the list has famous worlds; topped up to ~50 by query.
EXO_NAMES = [
    "Proxima Cen b", "TRAPPIST-1 b", "TRAPPIST-1 c", "TRAPPIST-1 d", "TRAPPIST-1 e", "TRAPPIST-1 f", "TRAPPIST-1 g", "TRAPPIST-1 h",
    "Kepler-22 b", "Kepler-452 b", "Kepler-186 f", "Kepler-16 b", "Kepler-10 b", "Kepler-442 b", "Kepler-69 c", "Kepler-62 f", "Kepler-90 h",
    "51 Peg b", "HD 209458 b", "HD 189733 b", "WASP-12 b", "WASP-121 b", "WASP-39 b", "WASP-96 b", "WASP-76 b", "KELT-9 b",
    "55 Cnc e", "GJ 1214 b", "GJ 486 b", "K2-18 b", "LHS 1140 b", "LHS 475 b", "TOI-700 d", "TOI-1452 b", "TOI-270 d", "Ross 128 b",
    "Teegarden's Star b", "GJ 667 C c", "Wolf 1061 c", "HR 8799 b", "HR 8799 e", "bet Pic b", "PSR B1257+12 c", "COCONUTS-2 b", "HIP 67522 b",
    "CoRoT-7 b", "GJ 1132 b", "L 98-59 d", "TOI-178 d", "HAT-P-7 b",
]

SOURCES_EXTRA = [
    ("NASA Solar System Treks (WMTS tiles and nomenclature)", "https://trek.nasa.gov/"),
    ("Planetary Fact Sheet", "https://nssdc.gsfc.nasa.gov/planetary/factsheet/"),
    ("NASA Exoplanet Archive, table pscomppars (TAP)", "https://exoplanetarchive.ipac.caltech.edu/TAP/sync"),
    ("JPL Keplerian elements for approximate planet positions", "https://ssd.jpl.nasa.gov/planets/approx_pos.html"),
    ("MOLA MEGDR elevation (PDS Geosciences Node)", PDS + "/missions/mgs/megdr.html"),
    ("LOLA LDEM elevation (PDS Geosciences Node)", PDS + "/missions/lro/lola.htm"),
    ("Deep Star Maps 2020 (NASA Scientific Visualization Studio 4851)", "https://svs.gsfc.nasa.gov/4851"),
]

FONTS = {
    "SpaceGrotesk.ttf": "https://github.com/google/fonts/raw/main/ofl/spacegrotesk/SpaceGrotesk%5Bwght%5D.ttf",
    "JetBrainsMono.ttf": "https://github.com/google/fonts/raw/main/ofl/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf",
}
