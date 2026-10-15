#!/usr/bin/env bash
# Update PKGBUILD + .SRCINFO to the latest upstream botmux release.
#
# Usage: scripts/update-pkg.sh [--check] [--force] [--version X.Y.Z] [--srcinfo-only]
#   --check          only report; exit 0 and print update status, change nothing
#   --force          re-run even if pkgver is already current (refreshes sums/.SRCINFO)
#   --version X.Y.Z  use this upstream version instead of "latest"
#   --srcinfo-only   just regenerate .SRCINFO from PKGBUILD
#
# Writes "updated=true|false" and "version=X.Y.Z" to $GITHUB_OUTPUT when set.
# Needs: bash, curl, sha256sum, sed, sort, (python3 or jq for the API reply).
set -euo pipefail

REPO="deepcoldy/botmux"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

CHECK=0 FORCE=0 WANT="" SRCINFO_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --force) FORCE=1 ;;
    --srcinfo-only) SRCINFO_ONLY=1 ;;
    --version) WANT="${2:?--version needs a value}"; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

log() { printf '%s\n' "$*" >&2; }
out() { [ -n "${GITHUB_OUTPUT:-}" ] && printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT" || true; }

curl_api() {
  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' "${auth[@]}" "$@"
}

current_pkgver() { sed -n 's/^pkgver=//p' PKGBUILD | head -n1; }

latest_version() {
  local tag
  tag="$(curl_api "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [ -n "$tag" ] || { log "could not determine latest tag"; return 1; }
  printf '%s\n' "${tag#v}"
}

# Emit .SRCINFO for the current PKGBUILD. Uses makepkg when present, otherwise
# sources the (repo-controlled) PKGBUILD and prints the fields we use.
gen_srcinfo() {
  if command -v makepkg >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
    makepkg --printsrcinfo > .SRCINFO
    return
  fi
  (
    set +u
    # shellcheck disable=SC1091
    . ./PKGBUILD
    set -u
    f() { local k="$1"; shift; local v; for v in "$@"; do printf '\t%s = %s\n' "$k" "$v"; done; }
    echo "pkgbase = ${pkgname}"
    f pkgdesc "${pkgdesc}"
    f pkgver "${pkgver}"
    f pkgrel "${pkgrel}"
    f url "${url}"
    f install "${install}"
    f arch "${arch[@]}"
    f license "${license[@]}"
    f depends "${depends[@]}"
    f optdepends "${optdepends[@]}"
    f provides "${provides[@]}"
    f conflicts "${conflicts[@]}"
    f options "${options[@]}"
    f noextract "${noextract[@]}"
    f source "${source[@]}"
    f sha256sums "${sha256sums[@]}"
    f source_x86_64 "${source_x86_64[@]}"
    f sha256sums_x86_64 "${sha256sums_x86_64[@]}"
    f source_aarch64 "${source_aarch64[@]}"
    f sha256sums_aarch64 "${sha256sums_aarch64[@]}"
    echo
    echo "pkgname = ${pkgname}"
  ) > .SRCINFO
}

if [ "$SRCINFO_ONLY" -eq 1 ]; then gen_srcinfo; log "regenerated .SRCINFO"; exit 0; fi

cur="$(current_pkgver)"
new="${WANT:-$(latest_version)}"
log "PKGBUILD pkgver: ${cur}; upstream: ${new}"

newest="$(printf '%s\n%s\n' "$cur" "$new" | sort -V | tail -n1)"
if [ "$FORCE" -eq 0 ] && { [ "$cur" = "$new" ] || [ "$newest" != "$new" ]; }; then
  log "already up to date (or upstream not newer); nothing to do"
  out updated false; out version "$cur"
  exit 0
fi
if [ "$CHECK" -eq 1 ]; then
  log "update available: ${cur} -> ${new}"
  out updated true; out version "$new"
  exit 0
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
base="https://github.com/${REPO}/releases/download/v${new}"

# asset name -> PKGBUILD arch suffix
declare -A ASSET=( [x86_64]=botmux-linux-x64 [aarch64]=botmux-linux-arm64 )
declare -A SUM

for a in x86_64 aarch64; do
  asset="${ASSET[$a]}"
  log "downloading ${asset} ..."
  curl -fsSL --retry 3 -o "$tmp/$asset" "${base}/${asset}"
  actual="$(sha256sum "$tmp/$asset" | cut -d' ' -f1)"
  # Cross-check with the checksum file published next to the asset (as install.sh does).
  if curl -fsSL --retry 3 -o "$tmp/$asset.sha256" "${base}/${asset}.sha256"; then
    expected="$(cut -d' ' -f1 < "$tmp/$asset.sha256")"
    if [ "$expected" != "$actual" ]; then
      log "checksum mismatch for ${asset}: published ${expected}, computed ${actual}"; exit 1
    fi
    log "  ${asset}: ${actual} (matches published .sha256)"
  else
    log "  ${asset}: ${actual} (no published .sha256 to cross-check)"
  fi
  SUM[$a]="$actual"
  rm -f "$tmp/$asset"
done

curl -fsSL --retry 3 -o "$tmp/LICENSE" "https://raw.githubusercontent.com/${REPO}/v${new}/LICENSE"
SUM[license]="$(sha256sum "$tmp/LICENSE" | cut -d' ' -f1)"

# Rewrite PKGBUILD in place.
if [ "$new" != "$cur" ]; then
  sed -i -e "s/^pkgver=.*/pkgver=${new}/" -e "s/^pkgrel=.*/pkgrel=1/" PKGBUILD
fi
sed -i \
  -e "s/^sha256sums=.*/sha256sums=('${SUM[license]}')/" \
  -e "s/^sha256sums_x86_64=.*/sha256sums_x86_64=('${SUM[x86_64]}')/" \
  -e "s/^sha256sums_aarch64=.*/sha256sums_aarch64=('${SUM[aarch64]}')/" \
  PKGBUILD

gen_srcinfo
log "updated to ${new}"
out updated true; out version "$new"
