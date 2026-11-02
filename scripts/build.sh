#!/usr/bin/env bash
# Builds the signed repository site from the downloaded packages: a reprepro archive
# (dists/, pool/), the public key, a ready-made deb822 source file, the fetch state and an
# index page. The signing key must already be in the gpg keyring (GNUPGHOME).
#
# Usage: scripts/build.sh <incoming dir> <state file> <site dir> <base url>
#   base url: where the site is served, e.g. https://develata.me/apt-repo/ (trailing slash)
set -euo pipefail

incoming=$1
state=$2
site=$3
base_url=$4
root=$(cd "$(dirname "$0")/.." && pwd)

# reprepro keeps its database next to conf/; build in a scratch base so nothing lands in the
# checkout, and write the published tree straight into the site directory.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -r "$root/conf" "$work/conf"
mkdir -p "$site"

mapfile -t debs < <(find "$incoming" -type f -name '*.deb' | sort)
if [[ ${#debs[@]} -eq 0 ]]; then
  echo "error: no packages in $incoming" >&2
  exit 1
fi
for deb in "${debs[@]}"; do
  reprepro --basedir "$work" --outdir "$site" includedeb stable "$deb"
done
reprepro --basedir "$work" --outdir "$site" export stable
reprepro --basedir "$work" list stable

mkdir -p "$site/keys"
cp "$root/keys/develata-archive-keyring.gpg" "$root/keys/develata-archive-keyring.asc" "$site/keys/"
cp "$state" "$site/state.json"

cat > "$site/develata.sources" <<EOF
Types: deb
URIs: $base_url
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/develata-archive-keyring.gpg
EOF

fingerprint=$(gpg --show-keys --with-colons "$root/keys/develata-archive-keyring.asc" | awk -F: '$1 == "fpr" { print $10; exit }')
packages=$(reprepro --basedir "$work" list stable | sed -E 's/^[^:]+: //' | sed -E 's/&/\&amp;/g; s/</\&lt;/g' | sed -E 's#^(.*)$#<li><code>\1</code></li>#')

sed -e "s#@BASE_URL@#$base_url#g" -e "s#@FINGERPRINT@#$fingerprint#g" "$root/site/index.html" \
  | awk -v packages="$packages" '{ if ($0 == "@PACKAGES@") print packages; else print }' > "$site/index.html"
