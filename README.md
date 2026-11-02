# Develata APT Repository

A signed APT repository for Debian and Ubuntu packages of software published by Develata, served from GitHub Pages at <https://develata.me/apt-repo/>.

## Use it

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://develata.me/apt-repo/keys/develata-archive-keyring.gpg | sudo tee /etc/apt/keyrings/develata-archive-keyring.gpg > /dev/null
curl -fsSL https://develata.me/apt-repo/develata.sources | sudo tee /etc/apt/sources.list.d/develata.sources > /dev/null
sudo apt update
sudo apt install rssr-app
```

Signing key: `A09B 4ADB D586 5C3E A6FB  7FFA 451D 75F9 C40D 5AC9` (`Develata APT Repository`, RSA 4096, no expiry). The same key is in [`keys/`](keys/).

| Package | Software | Source asset |
| --- | --- | --- |
| `rssr-app` | [RSS-Reader](https://github.com/Develata/RSS-Reader) desktop app | `RSS-Reader-linux-x86_64.deb` |

## How it works

The repository holds no packages. [`sources.json`](sources.json) lists, per project, which `.deb` assets to publish. The [Publish](.github/workflows/publish.yml) workflow (on push, every four hours, or by hand):

1. downloads those assets from each project's latest GitHub release (no drafts or prereleases) and checks each against the SHA-256 digest GitHub records ([`scripts/fetch.sh`](scripts/fetch.sh));
2. on a scheduled run, stops if the result matches the deployed `state.json`;
3. builds the archive with reprepro ([`conf/distributions`](conf/distributions)), signs `Release` / `InRelease` with the key from the `APT_SIGNING_KEY` secret, and adds the public key, the deb822 source file and the index page ([`scripts/build.sh`](scripts/build.sh));
4. verifies both signatures with `gpgv`, then deploys the site to GitHub Pages.

Only the latest release of each package is published; older versions stay downloadable from the project's GitHub releases. One suite (`stable`) and one component (`main`) serve all supported distributions; each package's `Depends` decides where it installs.

## Add a package

Add an entry to `sources.json` with the project repository and its `.deb` asset names, push, and check the Publish run. A project needs no secret or token of its own.

An asset may also be a list of names, tried in order. This publishes a Debian packaging revision added to an existing release (same program, fixed packaging, version `X.Y.Z-1`) ahead of the regular asset, and falls back to the regular asset once a later release no longer carries the revision. RSS-Reader currently uses this for `0.2.2-1`, which fixes the desktop entry name; the stale first name can be removed after the next release.

## Signing key

- The private key is the `APT_SIGNING_KEY` repository secret (ASCII-armored, no passphrase). Keep an offline backup together with its revocation certificate; losing it means every user has to import a new key.
- To rotate: generate a new key, publish its public half next to the old one, sign with both for a transition period, then remove the old key.
