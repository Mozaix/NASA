NEXT FRONTIER EXPLORER
NASA Space Apps Challenge 2026: Space Mission Design Game

Design a space mission, fly it, land it, then drive across terrain
built from real NASA data. No internet is needed: everything is on this drive.


HOW TO START THE GAME
---------------------

macOS (Apple Silicon or Intel)
  1. Open the "macOS" folder.
  2. Double-click NextFrontierExplorer-macOS.zip to unpack it, then drag the
     app to your Desktop. It loads faster from there than from the USB stick.
     (NextFrontierExplorer.app beside the zip also runs directly from the stick.)
  3. The first time only: RIGHT-CLICK the app and choose "Open", then click
     "Open" again in the box that appears. The app is not signed by Apple,
     so double-clicking it the first time will be refused.
  4. On recent macOS versions the box may offer only "Done". If so, open
     System Settings > Privacy & Security, scroll down, and click "Open Anyway".
  If macOS still says the app is damaged, open Terminal and run:
     xattr -cr ~/Desktop/NextFrontierExplorer.app

Windows 10 or 11 (64-bit)
  1. Open the "Windows" folder.
  2. Double-click NextFrontierExplorer.exe. Keep the .exe and .pck files together.
  3. If SmartScreen warns you, click "More info", then "Run anyway".
     The game is not signed with a publisher certificate.

Linux (64-bit)
  1. Open the "Linux" folder in a terminal.
  2. Run:  chmod +x NextFrontierExplorer.x86_64
  3. Run:  ./NextFrontierExplorer.x86_64
     Keep the .x86_64 and .pck files together. If the USB stick does not allow
     running programs, copy the folder to your home directory first.


GAME MODES
----------
Play Main Game  The full mission: plan, launch, cruise, orbit, land, explore.
Play Demo       A short version with one simple planning page and a 3-question
                quiz before and after. Quiz results stay on this computer.
Play 2D         Build rockets, earn money from height, buy better parts.
                6 launches per game. Type your name at the end to join today's
                leaderboard. The next player starts fresh; the day's scores stay.
                Scores are saved on this computer only.


CONTROLS
--------
Keyboard and mouse, or any standard gamepad (plug it in before starting).

                        Keyboard          Gamepad
  Drive, steer          W A S D           Left stick
  Look around           Mouse or arrows   Right stick
  Main action           Space             A
  (ignite, burn, hop)
  Collect sample, scan  E (hold)          X (hold)
  Boost                 Shift             Right bumper
  Spin tricks (hold)    Q + W A S D       Left trigger + left stick
  Headlights            L                 Y
  Map / scale toggle    M                 Back
  Landing autopilot     P                 Left bumper
  Look down at the pad  C                 Press right stick
  Show exact numbers    Tab               D-pad up
  Pause                 Esc               Start

Keys can be changed in Settings.

Launch: press Space to go for launch; the countdown runs from T-30 (Space again skips to T-10).
        After liftoff, W/S throttle, A/D steer. If the stress needle stays in the red too long, the rocket breaks up.
Tricks: hold Q and press W/S to flip or A/D to spin, on the rocket or in a rover jump. Land the combo to bank it.
Rover: rocks cost health. Drive back to the lander to repair.


IF THE GAME RUNS SLOWLY
-----------------------
Open Settings and set Graphics to Low. Choosing Low also lowers the
rendering resolution, which helps most on older laptops.

The game needs a graphics driver with Metal, Vulkan or Direct3D 12 support.
On a very old Windows or Linux machine, update the graphics driver first.


ABOUT THE DATA
--------------
Every dataset and page used is listed in Credits & Sources inside the game,
and in SOURCES.md next to this file. Facts shown in the game are direct quotes
from NASA pages, or numbers from NASA data. Numbers the game computes are
labelled "derived".

This is a fan project made for the NASA Space Apps Challenge by Hosam and his team. It is not
endorsed by NASA. Godot Engine is used under the MIT licence.
