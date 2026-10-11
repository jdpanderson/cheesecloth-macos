#!/usr/bin/env bash
# Builds the macOS installer from a built cheesecloth binary:
# dist/cheesecloth-<version>-macos-<arch>.pkg. The binary must be for this
# Mac's architecture. The version comes from the binary.
#
# Usage: build.sh <binary> <source>
#   <source> is a checkout of cheesecloth at the commit that built <binary>.
#   The installer holds its README, LICENSE, THIRD-PARTY-NOTICES.md and docs.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <binary> <source>" >&2
  exit 2
fi
binary=$1
source=$2

# "cheesecloth 0.3.0"
version=$("$binary" --version)
version=${version#cheesecloth }
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "unexpected version '$version'" >&2
  exit 1
fi
arch=$(uname -m)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

install -d "$stage/root/usr/local/bin" "$stage/root/usr/local/share/doc/cheesecloth/docs"
install -m755 "$binary" "$stage/root/usr/local/bin/cheesecloth"
install -m644 "$source/README.md" "$source/LICENSE" "$source/THIRD-PARTY-NOTICES.md" \
  "$stage/root/usr/local/share/doc/cheesecloth/"
install -m644 "$source"/docs/*.md "$stage/root/usr/local/share/doc/cheesecloth/docs/"
xattr -cr "$stage/root"
# The binary is not stripped, so backtraces show function names, and it
# stays the same as the binary that was built or released.
lipo "$stage/root/usr/local/bin/cheesecloth" -verify_arch "$arch"
"$stage/root/usr/local/bin/cheesecloth" --version

mkdir -p dist
package="dist/cheesecloth-${version}-macos-${arch}.pkg"
pkgbuild --root "$stage/root" --identifier ca.janderson.cheesecloth \
  --version "$version" --install-location / --ownership recommended "$package"

# Inspect the actual archive without installing it or starting a daemon.
pkgutil --expand-full "$package" "$stage/expanded"
payload="$stage/expanded/Payload/usr/local/bin/cheesecloth"
cmp "$binary" "$payload"
"$payload" --version
