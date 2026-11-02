#!/usr/bin/env bash
# Downloads the packages listed in sources.json from each project's latest GitHub release
# (not drafts or prereleases) into <incoming dir>, checks every file against the SHA-256
# digest GitHub records for it, and writes <state file>: one entry per package file, sorted,
# so two runs that fetched the same releases produce byte-identical state.
#
# Usage: scripts/fetch.sh <incoming dir> <state file>   (needs gh, jq, sha256sum)
set -euo pipefail

incoming=$1
state=$2
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$incoming"

entries=()
while IFS= read -r source; do
  repo=$(jq -r '.repo' <<<"$source")
  release=$(gh api "repos/$repo/releases/latest")
  tag=$(jq -r '.tag_name' <<<"$release")
  while IFS= read -r asset; do
    digest=$(jq -r --arg name "$asset" '.assets[] | select(.name == $name) | .digest // empty' <<<"$release")
    if [[ -z $digest ]]; then
      echo "error: $repo $tag has no asset $asset with a digest" >&2
      exit 1
    fi
    expected=${digest#sha256:}
    # One directory per repository keeps equal asset names from different projects apart.
    dir="$incoming/${repo//\//_}"
    mkdir -p "$dir"
    gh release download "$tag" --repo "$repo" --pattern "$asset" --dir "$dir" --clobber
    actual=$(sha256sum "$dir/$asset" | cut -d' ' -f1)
    if [[ $actual != "$expected" ]]; then
      echo "error: $repo $tag $asset has SHA-256 $actual, GitHub records $expected" >&2
      exit 1
    fi
    echo "fetched $repo $tag $asset ($actual)"
    entries+=("$(jq -cn --arg repo "$repo" --arg tag "$tag" --arg asset "$asset" --arg sha256 "$actual" \
      '{repo: $repo, tag: $tag, asset: $asset, sha256: $sha256}')")
  done < <(jq -r '.assets[]' <<<"$source")
done < <(jq -c '.[]' "$root/sources.json")

printf '%s\n' "${entries[@]}" | jq -s 'sort_by(.repo, .asset)' > "$state"
