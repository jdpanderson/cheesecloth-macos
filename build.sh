#!/usr/bin/env bash
# Builds Cheesecloth.app from built cheesecloth binaries, signed ad hoc, and
# puts it in a disk image: dist/Cheesecloth-<version>.dmg. The version comes
# from the binaries.
#
# Usage: build.sh <source> <binary>...
#   <source> is a checkout of cheesecloth at the commit that built the
#   binaries. The app holds its README, LICENSE, THIRD-PARTY-NOTICES.md and
#   docs.
#   Each <binary> is cheesecloth for one architecture. The app is built for
#   the same architectures: one binary for this Mac only, or an arm64 and an
#   x86_64 binary for a universal app.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <source> <binary>..." >&2
  exit 2
fi
source=$1
shift
here=$(cd "$(dirname "$0")" && pwd)
stage=$(mktemp -d)
mounted=
cleanup() {
  if [[ -n "$mounted" ]]; then
    hdiutil detach -quiet "$mounted" || true
  fi
  rm -rf "$stage"
}
trap cleanup EXIT

# One binary with every architecture, unchanged apart from the signature
# that codesign adds below. It is not stripped, so backtraces show function
# names.
lipo -create "$@" -output "$stage/cheesecloth"
read -r -a archs <<<"$(lipo -archs "$stage/cheesecloth")"
if [[ ${#archs[@]} -ne $# ]]; then
  echo "expected $# architectures, found: ${archs[*]}" >&2
  exit 1
fi

# "cheesecloth 0.4.0"
version=$("$stage/cheesecloth" --version)
version=${version#cheesecloth }
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "unexpected version '$version'" >&2
  exit 1
fi

swift_args=(--package-path "$here/app" -c release)
for arch in "${archs[@]}"; do
  swift_args+=(--arch "$arch")
done
swift build "${swift_args[@]}"
products=$(swift build "${swift_args[@]}" --show-bin-path)

app="$stage/Cheesecloth.app"
contents="$app/Contents"
install -d "$contents/MacOS" "$contents/Helpers" "$contents/Resources/docs" \
  "$contents/Library/LaunchDaemons"
sed "s/VERSION/$version/g" "$here/app/Bundle/Info.plist" >"$contents/Info.plist"
install -m755 "$products/Cheesecloth" "$contents/MacOS/Cheesecloth"
install -m755 "$stage/cheesecloth" "$contents/Helpers/cheesecloth"
install -m644 "$here/app/Bundle/ca.janderson.cheesecloth.plist" "$contents/Library/LaunchDaemons/"
# The Swift package's resources (the menu-bar icon). Bundle.module finds
# them in Contents/Resources.
cp -R "$products/Cheesecloth_Cheesecloth.bundle" "$contents/Resources/"
install -m644 "$source/README.md" "$source/LICENSE" "$source/THIRD-PARTY-NOTICES.md" \
  "$contents/Resources/"
install -m644 "$source"/docs/*.md "$contents/Resources/docs/"

# The app icon, in every size an .icns holds, from app/Bundle/AppIcon.png
# (mockups/app-icon.png).
iconset="$stage/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$here/app/Bundle/AppIcon.png" \
    --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$here/app/Bundle/AppIcon.png" \
    --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$contents/Resources/AppIcon.icns"

plutil -lint "$contents/Info.plist" "$contents/Library/LaunchDaemons/ca.janderson.cheesecloth.plist"
xattr -cr "$app"

# Ad hoc: the helper first, then the app, which seals the helper. The
# hardened runtime is on, as a Developer ID signature will need.
codesign --force --sign - --options runtime "$contents/Helpers/cheesecloth"
codesign --force --sign - --options runtime "$app"

# The disk image holds the app and a link to /Applications, so the user
# drags the app there. Run from elsewhere, a quarantined app runs from a
# random read-only path, and its daemon registration would point there.
install -d "$stage/image"
ditto "$app" "$stage/image/Cheesecloth.app"
ln -s /Applications "$stage/image/Applications"
mkdir -p dist
dmg="dist/Cheesecloth-$version.dmg"
rm -f "$dmg"
hdiutil create -quiet -volname Cheesecloth -srcfolder "$stage/image" -fs HFS+ \
  -format UDZO -ov "$dmg"

# Check the app in the disk image, not the one built here.
hdiutil verify -quiet "$dmg"
mounted="$stage/mnt"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$mounted" "$dmg"
image_app="$mounted/Cheesecloth.app"
codesign --verify --strict --deep "$image_app"
for binary in MacOS/Cheesecloth Helpers/cheesecloth; do
  for arch in "${archs[@]}"; do
    lipo "$image_app/Contents/$binary" -verify_arch "$arch"
  done
done
"$image_app/Contents/Helpers/cheesecloth" --version
if [[ "$(readlink "$mounted/Applications")" != /Applications ]]; then
  echo "the disk image has no link to /Applications" >&2
  exit 1
fi
echo "$dmg"
