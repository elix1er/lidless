#!/bin/zsh
# Build Lidless.app (and the displaytool CLI). Pass --install to copy the app to /Applications.
set -euo pipefail
cd "${0:A:h}"

app=build/Lidless.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
xcrun swiftc -O Sources/*.swift -o "$app/Contents/MacOS/Lidless"
xcrun swiftc -O Sources/Display.swift Tools/displaytool/main.swift -o build/displaytool
codesign --force --sign - "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Lidless || true
  while pgrep -qx Lidless; do sleep 0.2; done
  rm -rf /Applications/Lidless.app
  cp -R "$app" /Applications/
  open /Applications/Lidless.app
  echo "Installed to /Applications and launched"
fi
