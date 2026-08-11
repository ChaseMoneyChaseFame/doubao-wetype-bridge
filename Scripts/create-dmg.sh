#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
version="${VERSION:-0.1.3}"
app_path="${1:-$project_root/.build/product/豆微输入法.app}"
release_dir="$project_root/.build/release"
dmg_path="$release_dir/DoubaoWeTypeBridge-$version-universal.dmg"
staging_dir="$(mktemp -d)"

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT

mkdir -p "$release_dir"
cp -R "$app_path" "$staging_dir/"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
    -volname "豆微输入法" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$dmg_path" >/dev/null

(
    cd "$release_dir"
    shasum -a 256 "${dmg_path:t}" > "${dmg_path:t}.sha256"
)
echo "$dmg_path"
