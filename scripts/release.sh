#!/bin/bash
# Release helper for this tap: after hhh2210/powervpn-cli has a vX.Y.Z tag
# pushed, download that tag's tarball, pin its sha256 into
# Formula/powervpn.rb, then commit and push the tap.
#
# Usage: scripts/release.sh <version>    (e.g. scripts/release.sh 0.1.0)
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: scripts/release.sh <version>   e.g. scripts/release.sh 0.1.0" >&2
  exit 64
fi
version="$1"

tap_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
formula="$tap_root/Formula/powervpn.rb"
url="https://github.com/hhh2210/powervpn-cli/archive/refs/tags/v${version}.tar.gz"

[ -f "$formula" ] || { echo "error: formula not found: $formula" >&2; exit 70; }

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
tarball="$workdir/powervpn-cli-v${version}.tar.gz"

echo "==> downloading $url"
# -f makes curl fail on 404, which is what happens when the tag is not pushed yet.
curl -fsSL "$url" -o "$tarball"

echo "==> computing sha256"
sha=$(shasum -a 256 "$tarball" | awk '{print $1}')
echo "    $sha"

if [ -z "$sha" ] || [ "$sha" = "__SHA256__" ] || ! [[ "$sha" =~ ^[0-9a-f]{64}$ ]]; then
  echo "error: refusing to write empty or placeholder sha256: '${sha}'" >&2
  exit 70
fi

echo "==> rewriting $formula"
sed -i '' \
  -e "s|^[[:space:]]*url .*|  url \"$url\"|" \
  -e "s|^[[:space:]]*version .*|  version \"$version\"|" \
  -e "s|^[[:space:]]*sha256 .*|  sha256 \"$sha\"|" \
  "$formula"
grep -q "sha256 \"$sha\"" "$formula" || { echo "error: formula rewrite failed" >&2; exit 70; }

echo "==> ruby -c $formula"
ruby -c "$formula" >/dev/null

cd "$tap_root"
if git diff --quiet -- Formula/powervpn.rb; then
  echo "error: formula unchanged after rewrite (same version already pinned?)" >&2
  exit 70
fi
git add Formula/powervpn.rb
git commit -m "powervpn ${version}: pin source tarball sha256" -- Formula/powervpn.rb
git push origin HEAD:main
echo "==> done. verify with:"
echo "    brew update && brew reinstall hhh2210/powervpn/powervpn --build-from-source"
