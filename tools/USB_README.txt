NEXT FRONTIER EXPLORER
NASA Space Apps Challenge 2026: Space Mission Design Game

Design a space mission, fly it, land it, then drive across terrain
built from real NASA data. No internet is needed: everything is on this drive.


HOW TO START THE GAME
---------------------

macOS (Apple Silicon or Intel)
  1. Open the "macOS" folder.
  2. Copy NextFrontierExplorer.app to your computer's Desktop or
     Applications folder. It runs faster from there than from the USB stick.
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
  Headlights            L                 Y
  Map / scale toggle    M                 Back
  Landing autopilot     P                 Left bumper
  Pause                 Esc               Start

Keys can be changed in Settings.


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

This is a fan project made for the NASA Space Apps Challenge. It is not
endorsed by NASA. Godot Engine is used under the MIT licence.
