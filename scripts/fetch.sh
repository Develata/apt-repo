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
  # An asset is a name, or a list of names tried in order: a packaging revision added to a
  # release (e.g. `-0.2.2-1.deb`) is listed first and falls back to the regular asset once a
  # later release no longer carries it.
  while IFS= read -r choice; do
    asset='' digest=''
    while IFS= read -r name; do
      digest=$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .digest // empty' <<<"$release")
      if [[ -n $digest ]]; then
        asset=$name
        break
      fi
    done < <(jq -r 'if type == "array" then .[] else . end' <<<"$choice")
    if [[ -z $asset ]]; then
      echo "error: $repo $tag has none of $choice with a digest" >&2
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
  done < <(jq -c '.assets[]' <<<"$source")
done < <(jq -c '.[]' "$root/sources.json")

printf '%s\n' "${entries[@]}" | jq -s 'sort_by(.repo, .asset)' > "$state"
