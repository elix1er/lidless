#!/bin/zsh
# Regenerate Assets/icon.png and Resources/AppIcon.icns from Assets/icon.svg. Needs rsvg-convert (brew install librsvg).
set -euo pipefail
cd "${0:A:h}/.."

iconset=$(mktemp -d)/AppIcon.iconset
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  rsvg-convert -w $size -h $size Assets/icon.svg -o "$iconset/icon_${size}x${size}.png"
  rsvg-convert -w $((size * 2)) -h $((size * 2)) Assets/icon.svg -o "$iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
rsvg-convert -w 1024 -h 1024 Assets/icon.svg -o Assets/icon.png
echo "Wrote Resources/AppIcon.icns and Assets/icon.png"
