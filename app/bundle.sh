#!/usr/bin/env bash
# Builds Cheesecloth.app from a built cheesecloth binary, for this Mac's
# architecture, signed ad hoc. The version comes from the binary.
#
# Usage: app/bundle.sh <binary> <out dir>
#   Writes <out dir>/Cheesecloth.app, replacing one that is there.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <binary> <out dir>" >&2
  exit 2
fi
binary=$1
out=$2
here=$(cd "$(dirname "$0")" && pwd)

# "cheesecloth 0.4.0"
version=$("$binary" --version)
version=${version#cheesecloth }
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "unexpected version '$version'" >&2
  exit 1
fi
lipo "$binary" -verify_arch "$(uname -m)"

swift build --package-path "$here" -c release
products=$(swift build --package-path "$here" -c release --show-bin-path)

app="$out/Cheesecloth.app"
rm -rf "$app"
contents="$app/Contents"
install -d "$contents/MacOS" "$contents/Helpers" "$contents/Resources" \
  "$contents/Library/LaunchDaemons"
sed "s/VERSION/$version/g" "$here/Bundle/Info.plist" >"$contents/Info.plist"
install -m755 "$products/Cheesecloth" "$contents/MacOS/Cheesecloth"
install -m755 "$binary" "$contents/Helpers/cheesecloth"
install -m644 "$here/Bundle/ca.janderson.cheesecloth.plist" "$contents/Library/LaunchDaemons/"
cp -R "$products/Cheesecloth_Cheesecloth.bundle" "$contents/Resources/"

# The app icon, in every size an .icns holds, from Bundle/AppIcon.png
# (mockups/app-icon.png).
iconset=$(mktemp -d)/AppIcon.iconset
trap 'rm -rf "$(dirname "$iconset")"' EXIT
mkdir "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$here/Bundle/AppIcon.png" \
    --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$here/Bundle/AppIcon.png" \
    --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$contents/Resources/AppIcon.icns"

plutil -lint "$contents/Info.plist" "$contents/Library/LaunchDaemons/ca.janderson.cheesecloth.plist"
xattr -cr "$app"

# Ad hoc: the helper first, then the app, which seals the helper.
codesign --force --sign - --options runtime "$contents/Helpers/cheesecloth"
codesign --force --sign - --options runtime "$app"
codesign --verify --strict --deep "$app"
"$contents/Helpers/cheesecloth" --version
echo "$app"
