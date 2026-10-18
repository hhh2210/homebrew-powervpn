#!/bin/bash
# Release helper for this tap: after hhh2210/powervpn-cli has a vX.Y.Z tag
# pushed, download that tag's tarball, pin its sha256 into
# Formula/powervpn.rb on a release branch cut from origin/main, and open a
# pull request. CI builds the bottle on that PR; publish it with the
# `brew pr-pull` workflow.
#
# Usage: scripts/release.sh <version>    (e.g. scripts/release.sh 0.2.0)
set -euo pipefail

if [[ "$#" -ne 1 ]]
then
  echo "usage: scripts/release.sh <version>   e.g. scripts/release.sh 0.2.0" >&2
  exit 64
fi
version="$1"
branch="powervpn-${version}"

tap_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
formula="${tap_root}/Formula/powervpn.rb"
url="https://github.com/hhh2210/powervpn-cli/archive/refs/tags/v${version}.tar.gz"

cd "${tap_root}"
# Check everything that can fail before touching the formula.
status=$(git status --porcelain)
if [[ -n "${status}" ]]
then
  echo "error: the tap checkout has uncommitted changes" >&2
  exit 70
fi
git fetch --quiet origin main
if git rev-parse --verify --quiet "refs/heads/${branch}" >/dev/null ||
   git ls-remote --exit-code --heads origin "${branch}" >/dev/null
then
  echo "error: branch ${branch} already exists" >&2
  exit 70
fi

workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT
tarball="${workdir}/powervpn-cli-v${version}.tar.gz"

echo "==> downloading ${url}"
# -f makes curl fail on 404, which is what happens when the tag is not pushed yet.
curl -fsSL "${url}" -o "${tarball}"

echo "==> computing sha256"
sha=$(shasum -a 256 "${tarball}" | awk '{print $1}')
echo "    ${sha}"
if [[ ! "${sha}" =~ ^[0-9a-f]{64}$ ]]
then
  echo "error: refusing to write an invalid sha256: '${sha}'" >&2
  exit 70
fi

git switch --quiet -c "${branch}" origin/main
echo "==> rewriting ${formula}"
# Only the formula's own two-space-indented stanza: the strongswan resource
# block (four spaces) has its own url/sha256 that must stay pinned.
sed -i '' \
  -e "s|^  url .*|  url \"${url}\"|" \
  -e "s|^  sha256 .*|  sha256 \"${sha}\"|" \
  "${formula}"
grep -q "^  sha256 \"${sha}\"" "${formula}" || {
  echo "error: formula rewrite failed" >&2
  exit 70
}
grep -q '^    sha256 ' "${formula}" || {
  echo "error: resource sha256 lost" >&2
  exit 70
}
ruby -c "${formula}" >/dev/null
if git diff --quiet -- Formula/powervpn.rb
then
  echo "error: formula unchanged after rewrite (same version already pinned?)" >&2
  exit 70
fi

git commit --quiet -m "powervpn ${version}" -- Formula/powervpn.rb
git push --quiet -u origin "${branch}"
pr_url=$(gh pr create --repo hhh2210/homebrew-powervpn --base main --head "${branch}" \
  --title "powervpn ${version}" --body "Pin the v${version} source tarball. CI builds the bottle.")
echo "==> opened ${pr_url}"
echo "==> when its checks are green, publish the bottle and the formula:"
echo "    gh workflow run publish.yml --repo hhh2210/homebrew-powervpn -f pull_request=${pr_url##*/}"
