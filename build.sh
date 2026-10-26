#!/usr/bin/env bash
# build.sh — bump PKGBUILDs from upstream releases, build what's missing,
# sign it and publish it to the pacman repo stored in a GitHub Release.
#
# Env:
#   GH_REPO   owner/repo that hosts the release (required unless DRY_RUN=1)
#   DRY_RUN=1 skip every write to GitHub (build + sign + repo-add only)
#
# packages.txt: "<dir> <owner/repo>" tracks upstream releases;
#               "<dir> -" builds a VCS package at its latest commit;
#               "<dir> latest.sh" takes the version printed by <dir>/latest.sh

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

# Runs in a subshell per package (results go to $OUT/.built and $OUT/.stale)
# so one broken package doesn't stop the rest from being published.
process_pkg() {
  local dir=$1 upstream=$2
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
    if [ "$upstream" = latest.sh ]; then
      latest=$(bash "$pkgdir/latest.sh")
    else
      latest=$(gh api "repos/$upstream/releases/latest" --jq .tag_name)
    fi
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
    return
  fi

  log "$dir: building $pkgfile"
  as_builder "$pkgdir" "makepkg -f --nodeps --noconfirm"
  cp "$pkgdir/$pkgfile" "$OUT/"
  gpg --batch --yes --detach-sign --no-armor -u "$KEYID" "$OUT/$pkgfile"
  printf '%s\n' "$OUT/$pkgfile" "$OUT/$pkgfile.sig" >> "$OUT/.built"

  pkgname=$(sed -n 's/^pkgname=//p' "$pkgdir/PKGBUILD")
  while read -r old; do
    [ -n "$old" ] && [ "$old" != "$pkgfile" ] && [ "$old" != "$pkgfile.sig" ] && echo "$old" >> "$OUT/.stale"
  done < <(grep -E "^$pkgname-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst(\.sig)?$" <<<"$assets" || true)
}

rm -f "$OUT/.built" "$OUT/.stale"
failed=()
while read -r dir upstream; do
  [ -z "$dir" ] || [[ $dir == \#* ]] && continue
  set +e
  (set -e; process_pkg "$dir" "$upstream") </dev/null
  rc=$?
  set -e
  if [ $rc != 0 ]; then
    log "$dir: FAILED (exit $rc), skipping"
    failed+=("$dir")
    # drop a half-done bump so the next run retries from a clean recipe
    git checkout -- "$dir" 2>/dev/null || true
  fi
done < packages.txt

mapfile -t built < <(cat "$OUT/.built" 2>/dev/null)
mapfile -t stale < <(cat "$OUT/.stale" 2>/dev/null)

finish() {
  if [ ${#failed[@]} != 0 ]; then
    echo "failed packages: ${failed[*]}" >&2
    exit 1
  fi
  exit 0
}

if [ ${#built[@]} = 0 ]; then
  log "nothing new to publish"
  finish
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
  finish
fi

log "uploading to release $TAG"
gh release upload "$TAG" --clobber "${built[@]}" "$OUT/$REPO_NAME".{db,files}{,.sig} \
  "$OUT/$REPO_NAME".{db,files}.tar.gz{,.sig} "$OUT/$REPO_NAME.asc"
for old in "${stale[@]}"; do
  log "removing old asset $old"
  gh release delete-asset "$TAG" "$old" --yes
done
finish
