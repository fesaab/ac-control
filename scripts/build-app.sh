#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP_ROOT="$PWD"
swift build -c release
BINARY_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$APP_ROOT/dist/AC Control.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY_DIR/ACControl" "$APP_DIR/Contents/MacOS/ACControl"
python3 - "$APP_DIR" "$APP_ROOT" <<'PYINFO'
import plistlib, sys
from pathlib import Path
app=Path(sys.argv[1])
info={
    'CFBundleName':'AC Control', 'CFBundleDisplayName':'AC Control',
    'CFBundleIdentifier':'com.fesaab.ac-control', 'CFBundleExecutable':'ACControl',
    'CFBundlePackageType':'APPL', 'CFBundleShortVersionString':'1.2.0',
    'CFBundleVersion':'3', 'LSMinimumSystemVersion':'14.0', 'LSUIElement':True,
    'NSHighResolutionCapable':True, 'ACControlEnvPath':str(Path(sys.argv[2])/'.env'),
    'NSHumanReadableCopyright':'Copyright © 2026 Felipe Nisrallah Saab'
}
(app/'Contents'/'Info.plist').write_bytes(plistlib.dumps(info))
PYINFO
codesign --force --sign - "$APP_DIR"
printf 'App pronto: %s\n' "$APP_DIR"
