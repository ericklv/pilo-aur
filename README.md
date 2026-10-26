# pilo-aur

Personal pacman repository (`[void]`), built by GitHub Actions and served from the [`x86_64` release](https://github.com/ericklv/pilo-aur/releases/tag/x86_64).

| Package | Upstream |
|---|---|
| `kubeterm-bin` | [kbterm/kubeterm](https://github.com/kbterm/kubeterm) |
| `radar-bin` | [skyhook-io/radar](https://github.com/skyhook-io/radar) |
| `zlack-bin` | [ericklv/zlack](https://github.com/ericklv/zlack) |
| `hoppscotch-bin` | [hoppscotch/releases](https://github.com/hoppscotch/releases) |
| `kubetray-git` | [ericklv/kubetray](https://github.com/ericklv/kubetray) (latest commit) |
| `browser-switcher-git` | [ericklv/browser-switcher](https://github.com/ericklv/browser-switcher) (latest commit) |
| `fetch-git` | [areofyl/fetch](https://github.com/areofyl/fetch) (latest commit) |
| `orchard` | [SFG5453/Orchard](https://github.com/SFG5453/Orchard) (built from source) |

## Usage

Trust the signing key:

```sh
curl -sL https://github.com/ericklv/pilo-aur/releases/download/x86_64/void.asc | sudo pacman-key --add -
sudo pacman-key --lsign-key 15DB79BC23EDE3921716D576342DED8209D44721
```

Add to `/etc/pacman.conf`:

```ini
[void]
SigLevel = Required DatabaseRequired
Server = https://github.com/ericklv/pilo-aur/releases/download/x86_64
```

Then:

```sh
sudo pacman -Sy radar-bin kubeterm-bin zlack-bin hoppscotch-bin kubetray-git browser-switcher-git fetch-git orchard
```

Updates arrive with the usual `sudo pacman -Syu`.

## How it works

`.github/workflows/build.yml` runs twice a day at 06:00 and 18:00 UTC-5 (and on manual dispatch or PKGBUILD changes) and calls `build.sh`, which for every line in `packages.txt`:

1. Checks the upstream latest release (or latest commit for `-git` packages) and bumps `pkgver`, `pkgrel`, `sha256sums` and `.SRCINFO` if needed.
2. Builds the package if it isn't already in the release, signs it, and adds it to the `void` database with `repo-add --sign`.
3. Uploads packages, signatures and database to the release, and deletes the previous versions.

Bumped PKGBUILDs are committed back by the bot.

## Adding a package

Create `<pkgname>/PKGBUILD` (with `.SRCINFO`) and add a line to `packages.txt`:

- `<pkgname> <owner/repo>`: tracks the upstream latest release (bumps `pkgver`, or `_tag` if the PKGBUILD defines it).
- `<pkgname> -`: VCS package rebuilt whenever `pkgver()` reports a new commit.
- `<pkgname> latest.sh`: for upstreams without GitHub releases; `<pkgname>/latest.sh` prints the latest version.

## Secrets

- `GPG_PRIVATE_KEY`: ASCII-armored private key `15DB79BC…09D44721` (no passphrase).
