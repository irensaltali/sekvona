#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == --signed && $# == 1 ]]; then
  export SEKVONA_MAC_RELEASE=1
  export CSC_IDENTITY_AUTO_DISCOVERY=false
  arches=(arm64 x64)
elif [[ $# == 0 ]]; then
  unset SEKVONA_MAC_RELEASE
  unset CSC_NAME
  arch="$(uname -m)"
  arches=("${arch/x86_64/x64}")
else
  echo "Usage: bash scripts/ci-mac.sh [--signed]" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel)"
commit="$(git -C "$root" rev-parse HEAD)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/sekvona-mac.XXXXXX")"
checkout="$scratch/src"
cleanup() {
  if [[ -d "$checkout" ]]; then
    git -C "$root" worktree remove --force "$checkout"
  fi
  rmdir "$scratch"
}
trap cleanup EXIT

git -C "$root" worktree add --detach "$checkout" "$commit"
cd "$checkout"
for arch in "${arches[@]}"; do
  if [[ "${SEKVONA_MAC_RELEASE:-0}" == 1 ]]; then
    # Keep the host tools and include the target's optional native prebuilds.
    # The config change is scoped to this disposable worktree.
    yarn config set supportedArchitectures.cpu --json "[\"current\",\"$arch\"]"
    bash scripts/build-mac-distributable.sh "$arch"
  else
    yarn install --immutable
    CSC_IDENTITY_AUTO_DISCOVERY=false yarn dist:mac "$arch"
  fi
done

mkdir -p "$root/dist/ci"
if [[ "${SEKVONA_MAC_RELEASE:-0}" == 1 ]]; then
  target="$(mktemp -d "$root/dist/ci/${commit:0:12}-signed.XXXXXX")"
else
  target="$(mktemp -d "$root/dist/ci/${commit:0:12}-$(uname -m).XXXXXX")"
fi
for arch in "${arches[@]}"; do
  (
    cd "$checkout/dist/macos-$arch"
    shasum -a 256 -c SHA256SUMS
    destination="$target"
    if [[ "${SEKVONA_MAC_RELEASE:-0}" == 1 ]]; then
      destination="$target/$arch"
      mkdir "$destination"
      cp latest-mac.yml "$destination/"
      for blockmap in ./*.zip.blockmap; do
        [[ ! -f "$blockmap" ]] || cp "$blockmap" "$destination/"
      done
    fi
    cp ./*.dmg ./*.zip SHA256SUMS INSTALL.txt "$destination/"
    cd "$destination"
    shasum -a 256 -c SHA256SUMS
  )
done
echo "Verified installers in $target"
