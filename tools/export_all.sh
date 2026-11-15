#!/bin/bash
# Builds all three versions into USB_BUILD/ and verifies the macOS signature.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=USB_BUILD/macOS/NextFrontierExplorer.app
rm -rf USB_BUILD
mkdir -p USB_BUILD/macOS USB_BUILD/Windows USB_BUILD/Linux USB_BUILD/Web
touch USB_BUILD/.gdignore  # keep builds out of the next build
godot --headless --import >/dev/null 2>&1 || true
godot --headless --export-release "macOS" "$APP"
godot --headless --export-release "Windows" USB_BUILD/Windows/NextFrontierExplorer.exe
godot --headless --export-release "Linux" USB_BUILD/Linux/NextFrontierExplorer.x86_64
# Browser version for local testing; GitHub builds and publishes its own (.github/workflows/web.yml).
godot --headless --export-release "Web" USB_BUILD/Web/index.html
# Apple Silicon refuses to run a broken signature, so sign ad hoc and prove it is valid.
# Sign outside ~/Documents: iCloud's file provider keeps adding attributes there, and codesign rejects them.
SIGN_DIR="$(mktemp -d)"
ditto --norsrc --noextattr --noacl "$APP" "$SIGN_DIR/NextFrontierExplorer.app"
codesign --force --deep --sign - --identifier org.spaceapps.nextfrontierexplorer "$SIGN_DIR/NextFrontierExplorer.app"
codesign --verify --deep --strict "$SIGN_DIR/NextFrontierExplorer.app"
rm -rf "$APP"
ditto --norsrc --noextattr --noacl "$SIGN_DIR/NextFrontierExplorer.app" "$APP"
# A zip keeps the signed bundle intact on any USB stick format.
ditto -c -k --norsrc --noextattr --keepParent "$SIGN_DIR/NextFrontierExplorer.app" USB_BUILD/macOS/NextFrontierExplorer-macOS.zip
rm -rf "$SIGN_DIR"
echo "macOS signature valid"
cp tools/USB_README.txt USB_BUILD/README.txt
cp data/SOURCES.md USB_BUILD/SOURCES.md
rm -f USB_BUILD/.gdignore
du -sh USB_BUILD/* USB_BUILD
