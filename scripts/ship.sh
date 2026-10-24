#!/bin/bash
# Ship a powervpn release end to end from the maintainer machine, after
# hhh2210/powervpn-cli has a vX.Y.Z tag pushed: wait for that tag's tap-sync
# CI, open the tap release PR (scripts/release.sh), wait for its bottle
# build, publish it with the pr-pull workflow, then upgrade the local
# Homebrew install. Every step talks to GitHub through the local `gh` login,
# so no CI job ever holds tap credentials.
#
# Safe to rerun after an interruption: an open release PR, or a pushed
# release branch without one, is picked up again, and a formula that already
# pins the version with a bottle skips straight to the local upgrade. The one
# step it never does is the root install of the native backend: when that is
# needed it prints the sudo command and exits 0.
#
# Known limit: brew pr-pull takes the newest bottle artifacts for the PR head.
# Do not rerun the PR's tests.yml while this script is publishing.
#
# Usage: scripts/ship.sh <version>    (e.g. scripts/ship.sh 0.2.2)
set -euo pipefail

if [[ "$#" -ne 1 ]]
then
  echo "usage: scripts/ship.sh <version>   e.g. scripts/ship.sh 0.2.2" >&2
  exit 64
fi
version="$1"
if [[ ! "${version}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
then
  echo "error: expected a version like 0.2.2, got '${version}'" >&2
  exit 64
fi
tag="v${version}"
branch="powervpn-${version}"
cli_repo="hhh2210/powervpn-cli"
tap_repo="hhh2210/homebrew-powervpn"
formula_name="hhh2210/powervpn/powervpn"
tarball_url="https://github.com/${cli_repo}/archive/refs/tags/${tag}.tar.gz"

tap_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)

fail() {
  echo "error: $*" >&2
  exit 70
}

# Waits up to ~2 minutes for workflow $2 in repo $1 to have a run that the
# jq expression $3 (an array of run ids, newest first) lists, then watches it
# and fails unless it succeeds. With $4 = only, more than one candidate is an
# error instead of taking the newest.
watch_run() {
  local repo="$1" workflow="$2" ids_expr="$3" mode="${4:-newest}"
  local ids="" count=0 attempt run_id
  for attempt in $(seq 24)
  do
    ids=$(gh run list --repo "${repo}" --workflow "${workflow}" --limit 50 \
      --json databaseId,headBranch,headSha,event --jq "${ids_expr} | map(tostring) | join(\" \")")
    count=$(wc -w <<<"${ids}")
    [[ "${count}" -gt 0 ]] && break
    [[ "${attempt}" -lt 24 ]] && sleep 5
  done
  [[ "${count}" -gt 0 ]] || fail "no ${workflow} run found in ${repo}"
  if [[ "${mode}" == only && "${count}" -gt 1 ]]
  then
    fail "${count} new ${workflow} runs in ${repo} (${ids}); another publish is running, check them by hand"
  fi
  run_id="${ids%% *}"
  echo "    https://github.com/${repo}/actions/runs/${run_id}"
  gh run watch "${run_id}" --repo "${repo}" --exit-status --interval 30 >/dev/null ||
    fail "${workflow} run ${run_id} did not succeed"
}

# Prints "bottled" when the tap's formula at ref $1 pins this version and its
# arm64_sequoia bottle sha256 is the digest of this version's asset on the
# bottles release, "pinned" when it pins the version otherwise (a release PR
# still carries the previous version's bottle block), and nothing when it
# does not pin this version.
formula_state() {
  local formula bottle_sha asset_sha
  formula=$(gh api "repos/${tap_repo}/contents/Formula/powervpn.rb?ref=$1" \
    -H 'Accept: application/vnd.github.raw')
  grep -q "^  url \"${tarball_url}\"" <<<"${formula}" || return 0
  bottle_sha=$(sed -n 's/^    sha256 arm64_sequoia: *"\([0-9a-f]\{64\}\)"$/\1/p' <<<"${formula}")
  asset_sha=$(gh api "repos/${tap_repo}/releases/tags/bottles" \
    --jq ".assets[] | select(.name == \"powervpn-${version}.arm64_sequoia.bottle.tar.gz\") | .digest" |
    sed -n 's/^sha256://p')
  if [[ -n "${bottle_sha}" && "${bottle_sha}" == "${asset_sha}" ]]
  then
    echo bottled
  else
    echo pinned
  fi
}

# Prints the number of the open release PR from this repository's own
# branch, or nothing; a PR from a fork never counts.
release_pr() {
  local prs count
  prs=$(gh pr list --repo "${tap_repo}" --head "${branch}" --base main --state open \
    --json number,isCrossRepository \
    --jq '[.[] | select(.isCrossRepository | not) | .number | tostring] | join(" ")')
  count=$(wc -w <<<"${prs}")
  [[ "${count}" -le 1 ]] || fail "several open PRs from ${branch}: ${prs}"
  echo "${prs}"
}

echo "==> checking ${cli_repo} tag ${tag}"
tag_sha=$(gh api "repos/${cli_repo}/commits/${tag}" --jq .sha 2>/dev/null) ||
  fail "tag ${tag} is not on ${cli_repo}; push it first (see TAGGING.md step 1)"
echo "    ${tag_sha}"

echo "==> waiting for tap-sync CI on ${tag}"
watch_run "${cli_repo}" tap-sync.yml \
  "[.[] | select(.event == \"push\" and .headBranch == \"${tag}\" and .headSha == \"${tag_sha}\") | .databaseId]"

state=$(formula_state main)
if [[ "${state}" == pinned ]]
then
  fail "tap main pins ${tag} without a bottle; publish it by hand (TAGGING.md step 3)"
fi
if [[ "${state}" == bottled ]]
then
  echo "==> tap main already ships ${tag} with a bottle"
else
  pr=$(release_pr)
  if [[ -n "${pr}" ]]
  then
    echo "==> reusing open release PR #${pr}"
  elif gh api "repos/${tap_repo}/branches/${branch}" --silent 2>/dev/null
  then
    echo "==> ${branch} is pushed without a PR; opening one"
    gh pr create --repo "${tap_repo}" --base main --head "${branch}" \
      --title "powervpn ${version}" --body "Pin the v${version} source tarball. CI builds the bottle." >/dev/null
    pr=$(release_pr)
  else
    "${tap_root}/scripts/release.sh" "${version}"
    # release.sh leaves this checkout on the release branch; go back so a
    # checkout that is also Homebrew's installed tap is not left on it.
    git -C "${tap_root}" switch --quiet - || fail "could not switch ${tap_root} back from ${branch}"
    pr=$(release_pr)
  fi
  [[ -n "${pr}" ]] || fail "no open release PR from ${branch}"

  echo "==> checking what PR #${pr} changes"
  head_sha=$(gh pr view "${pr}" --repo "${tap_repo}" --json headRefOid --jq .headRefOid)
  files=$(gh pr view "${pr}" --repo "${tap_repo}" --json files --jq '[.files[].path] | join(" ")')
  [[ "${files}" == "Formula/powervpn.rb" ]] ||
    fail "PR #${pr} changes '${files}', expected only Formula/powervpn.rb"
  pr_state=$(formula_state "${head_sha}")
  [[ "${pr_state}" == pinned ]] || fail "PR #${pr} does not pin ${tarball_url}"
  workdir=$(mktemp -d)
  trap 'rm -rf "${workdir}"' EXIT
  curl -fsSL "${tarball_url}" -o "${workdir}/source.tar.gz"
  sha=$(shasum -a 256 "${workdir}/source.tar.gz" | awk '{print $1}')
  pr_formula=$(gh api "repos/${tap_repo}/contents/Formula/powervpn.rb?ref=${head_sha}" \
    -H 'Accept: application/vnd.github.raw')
  grep -q "^  sha256 \"${sha}\"" <<<"${pr_formula}" ||
    fail "PR #${pr} pins a sha256 that is not the ${tag} tarball's (${sha})"

  echo "==> waiting for the bottle build on PR #${pr}"
  watch_run "${tap_repo}" tests.yml \
    "[.[] | select(.event == \"pull_request\" and .headSha == \"${head_sha}\") | .databaseId]"
  current_head=$(gh pr view "${pr}" --repo "${tap_repo}" --json headRefOid --jq .headRefOid)
  [[ "${current_head}" == "${head_sha}" ]] ||
    fail "PR #${pr} moved while its checks ran; rerun this script"

  echo "==> publishing PR #${pr} at ${head_sha}"
  known=$(gh run list --repo "${tap_repo}" --workflow publish.yml --limit 50 \
    --json databaseId --jq '[.[].databaseId]')
  gh workflow run publish.yml --repo "${tap_repo}" \
    -f pull_request="${pr}" -f head_sha="${head_sha}"
  new_runs="[.[] | select(.event == \"workflow_dispatch\") | .databaseId] - ${known}"
  watch_run "${tap_repo}" publish.yml "${new_runs}" only
  # Another dispatch may have shown up first and been the one watched; any
  # second new run means this one's outcome was not the one observed.
  new_count=$(gh run list --repo "${tap_repo}" --workflow publish.yml --limit 50 \
    --json databaseId,event --jq "${new_runs} | length")
  [[ "${new_count}" -eq 1 ]] ||
    fail "${new_count} publish runs started during this publish; check them by hand"
  state=$(formula_state main)
  [[ "${state}" == bottled ]] ||
    fail "publish finished but tap main does not ship ${tag} with a bottle"
fi

echo "==> upgrading the local install"
brew update --quiet
installed_tap=$(brew --repository hhh2210/powervpn)
tap_branch=$(git -C "${installed_tap}" branch --show-current)
[[ "${tap_branch}" == main ]] ||
  fail "Homebrew's tap checkout ${installed_tap} is on '${tap_branch}', not main; run: git -C ${installed_tap} switch main && brew update"
current=$(brew list --versions powervpn 2>/dev/null | awk '{print $NF}' || true)
if [[ -z "${current}" ]]
then
  brew install "${formula_name}"
elif [[ "${current}" != "${version}" ]]
then
  brew upgrade "${formula_name}"
fi
installed=$(powervpn --version)
[[ "${installed}" == "${version}" ]] ||
  fail "powervpn --version prints '${installed}', expected ${version}"
keg=$(brew --prefix "${formula_name}")
grep -Eq '"poured_from_bottle": *true' "${keg}/INSTALL_RECEIPT.json" ||
  fail "powervpn ${version} was built from source, not poured from the bottle; run: brew reinstall ${formula_name}"
echo "    powervpn ${installed}, poured from the bottle"

echo "==> checking the native backend"
if powervpn native status
then
  echo "==> shipped ${tag}"
else
  # 1 means not installed or out of date, which only a root install fixes;
  # anything else is a real error whose next: line says what to do.
  status=$?
  [[ "${status}" -eq 1 ]] || fail "powervpn native status exited ${status}; follow its next: line"
  echo "==> shipped ${tag}; finish with the sudo command on the next: line above (it needs you at the keyboard)"
fi
