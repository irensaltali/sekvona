#!/usr/bin/env bash
set -euo pipefail
umask 022

cd "$(git rev-parse --show-toplevel)"
app_id=6838639211
bundle_id=com.irensaltali.seknova
team_id=R69D8UY83Z
asc_profile=irensaltali_key
signing_dir="$HOME/.asc/sekvona-testflight"
build_number="${GITHUB_RUN_NUMBER:?GitHub run number is required}"
version="$(node -p "require('./apps/desktop/package.json').version")"
report="$PWD/deployment-report"
mkdir -p "$report"

asc_mac() {
  asc --profile "$asc_profile" "$@"
}

case "${1:-}" in
  package)
    test "$(uname -m)" = arm64
    export CSC_KEYCHAIN="$signing_dir/Seknova.keychain-db"
    security unlock-keychain -p "$(cat "$signing_dir/keychain-password")" "$CSC_KEYCHAIN"
    security cms -D -i "$signing_dir/Seknova.provisionprofile" > "$report/profile.plist"
    profile_bundle="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$report/profile.plist")"
    if [[ "$profile_bundle" != "$team_id.$bundle_id" ]]; then
      echo "Provisioning profile does not match $team_id.$bundle_id" >&2
      exit 1
    fi
    unlink "$report/profile.plist"
    # electron-builder preserves this file's mode when embedding it in the app.
    install -m 0644 "$signing_dir/Seknova.provisionprofile" "$report/Seknova.provisionprofile"

    yarn install --immutable
    yarn workspace @multizen/desktop prepare:kopia --arch=arm64
    yarn workspace @multizen/desktop exec electron-vite build
    node apps/desktop/scripts/strip-workspace-symlinks.cjs
    yarn workspace @multizen/desktop exec electron-builder --mac mas --arm64 --publish never \
      --config.appId="$bundle_id" --config.buildVersion="$build_number" \
      --config.mas.identity="$team_id" \
      --config.mac.minimumSystemVersion=12.0 \
      --config.mas.provisioningProfile="$report/Seknova.provisionprofile"

    app="apps/desktop/release/mas-arm64/Sekvona.app"
    pkg="apps/desktop/release/mas-arm64/Seknova-TestFlight-$version-arm64.pkg"
    codesign --verify --deep --strict "$app"
    pkgutil --check-signature "$pkg" | tee "$report/package-signature.txt"
    grep -F "($team_id)" "$report/package-signature.txt" >/dev/null
    test "$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" = "$bundle_id"
    test "$(plutil -extract CFBundleVersion raw -o - "$app/Contents/Info.plist")" = "$build_number"
    test "$(plutil -extract LSMinimumSystemVersion raw -o - "$app/Contents/Info.plist")" = 12.0
    unreadable="$(find "$app" -type f ! -perm -004 -print)"
    if [[ -n "$unreadable" ]]; then
      printf 'Packaged files not readable by all users:\n%s\n' "$unreadable" >&2
      exit 1
    fi
    unlink "$report/Seknova.provisionprofile"
    ditto "$pkg" "$report/Seknova-TestFlight.pkg"
    ;;
  upload)
    # Reconcile with Apple before retrying. A run number is stable across reruns.
    asc_mac builds list --app "$app_id" --platform MAC_OS --version "$version" \
      --build-number "$build_number" > "$report/build.json"
    if jq -e '.data | length > 0' "$report/build.json" >/dev/null; then
      jq -e '.data | any(.attributes.processingState == "VALID")' "$report/build.json" >/dev/null
      exit
    fi
    asc_mac builds uploads list --app "$app_id" --platform MAC_OS \
      --cf-bundle-short-version "$version" --cf-bundle-version "$build_number" > "$report/existing-upload.json"
    if jq -e '.data | length > 0' "$report/existing-upload.json" >/dev/null; then
      echo "Apple already has an upload for this build. Inspect existing-upload.json before retrying." >&2
      exit 1
    fi
    asc_mac builds upload --app "$app_id" --pkg "$report/Seknova-TestFlight.pkg" \
      --version "$version" --build-number "$build_number" --wait | tee "$report/upload.json"
    ;;
  *)
    echo "Usage: $0 package|upload" >&2
    exit 2
    ;;
esac
