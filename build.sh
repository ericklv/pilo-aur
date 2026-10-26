#!/usr/bin/env bash
# build.sh — bump PKGBUILDs from upstream releases, build what's missing,
# sign it and publish it to the pacman repo stored in a GitHub Release.
#
# Env:
#   GH_REPO   owner/repo that hosts the release (required unless DRY_RUN=1)
#   DRY_RUN=1 skip every write to GitHub (build + sign + repo-add only)
#
# packages.txt: "<dir> <owner/repo>" tracks upstream releases;
#               "<dir> -" builds a VCS package at its latest commit

set -euo pipefail

REPO_NAME=void
TAG=x86_64
OUT="$PWD/out"
DRY_RUN=${DRY_RUN:-0}

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

# makepkg refuses to run as root (CI container), so drop to "builder" there
as_builder() {
  if [ "$(id -u)" = 0 ]; then
    id builder &>/dev/null || useradd -m builder
    chown -R builder "$1"
    su builder -c "cd '$1' && $2"
  else
    (cd "$1" && bash -c "$2")
  fi
}

KEYID=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')
[ -n "$KEYID" ] || { echo "no secret GPG key available" >&2; exit 1; }
export GPGKEY=$KEYID

mkdir -p "$OUT"

assets=""
if [ "$DRY_RUN" != 1 ]; then
  gh release view "$TAG" &>/dev/null ||
    gh release create "$TAG" --title "$REPO_NAME ($TAG)" --notes "pacman repository, see README"
  assets=$(gh release view "$TAG" --json assets -q '.assets[].name')
  # keep the existing database so repo-add only adds/replaces entries
  if grep -qxF "$REPO_NAME.db.tar.gz" <<<"$assets"; then
    gh release download "$TAG" -D "$OUT" --clobber \
      -p "$REPO_NAME.db.tar.gz" -p "$REPO_NAME.files.tar.gz"
  fi
fi

built=()
stale=()

while read -r dir upstream; do
  [ -z "$dir" ] || [[ $dir == \#* ]] && continue
  pkgdir="$PWD/$dir"

  if [ "$(id -u)" = 0 ]; then
    makedeps=$(cd "$pkgdir" && source PKGBUILD && echo "${makedepends[@]}")
    [ -z "$makedeps" ] || pacman -S --needed --noconfirm $makedeps
  fi

  if [ "$upstream" = - ]; then
    # VCS package: fetch sources so pkgver() rewrites pkgver to the latest commit
    as_builder "$pkgdir" "makepkg -od --nodeps --noconfirm && makepkg --printsrcinfo > .SRCINFO"
  else
    # bump _tag when the PKGBUILD derives pkgver from it, pkgver otherwise
    var=pkgver
    grep -q '^_tag=' "$pkgdir/PKGBUILD" && var=_tag
    latest=$(gh api "repos/$upstream/releases/latest" --jq .tag_name)
    latest=${latest#v}
    current=$(sed -n "s/^$var=//p" "$pkgdir/PKGBUILD")
    if [ -n "$latest" ] && [ "$latest" != "$current" ]; then
      log "$dir: $current -> $latest"
      sed -i "s/^$var=.*/$var=$latest/; s/^pkgrel=.*/pkgrel=1/" "$pkgdir/PKGBUILD"
      as_builder "$pkgdir" "updpkgsums && makepkg --printsrcinfo > .SRCINFO"
    fi
  fi

  pkgfile=$(as_builder "$pkgdir" "makepkg --packagelist" | grep -v -- "-debug-" | head -1)
  pkgfile=$(basename "$pkgfile")
  if grep -qxF "$pkgfile" <<<"$assets"; then
    log "$dir: $pkgfile already published"
    continue
  fi

  log "$dir: building $pkgfile"
  as_builder "$pkgdir" "makepkg -f --nodeps --noconfirm"
  cp "$pkgdir/$pkgfile" "$OUT/"
  gpg --batch --yes --detach-sign --no-armor -u "$KEYID" "$OUT/$pkgfile"
  built+=("$OUT/$pkgfile" "$OUT/$pkgfile.sig")

  pkgname=$(sed -n 's/^pkgname=//p' "$pkgdir/PKGBUILD")
  while read -r old; do
    [ -n "$old" ] && [ "$old" != "$pkgfile" ] && [ "$old" != "$pkgfile.sig" ] && stale+=("$old")
  done < <(grep -E "^$pkgname-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst(\.sig)?$" <<<"$assets" || true)
done < packages.txt

if [ ${#built[@]} = 0 ]; then
  log "nothing new to publish"
  exit 0
fi

log "updating $REPO_NAME database"
pkgs=()
for f in "${built[@]}"; do [[ $f == *.zst ]] && pkgs+=("$f"); done
repo-add --sign --key "$KEYID" "$OUT/$REPO_NAME.db.tar.gz" "${pkgs[@]}"

# Releases can't hold symlinks: publish real copies under the names pacman requests
for f in "$OUT/$REPO_NAME".{db,files}{,.sig}; do
  cp --remove-destination "$(readlink -f "$f")" "$f"
done
gpg --armor --export "$KEYID" > "$OUT/$REPO_NAME.asc"

if [ "$DRY_RUN" = 1 ]; then
  log "DRY_RUN: would upload"; ls -l "$OUT"
  [ ${#stale[@]} = 0 ] || log "DRY_RUN: would delete ${stale[*]}"
  exit 0
fi

log "uploading to release $TAG"
gh release upload "$TAG" --clobber "${built[@]}" "$OUT/$REPO_NAME".{db,files}{,.sig} \
  "$OUT/$REPO_NAME".{db,files}.tar.gz{,.sig} "$OUT/$REPO_NAME.asc"
for old in "${stale[@]}"; do
  log "removing old asset $old"
  gh release delete-asset "$TAG" "$old" --yes
done
