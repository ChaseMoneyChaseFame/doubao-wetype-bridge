#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
version="${VERSION:-0.1.0}"
build_number="${BUILD_NUMBER:-1}"
identity="${CODE_SIGN_IDENTITY:--}"
build_root="$project_root/.build/product"
app_path="$build_root/豆微输入法.app"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
resources_path="$contents_path/Resources"
icon_work="$build_root/AppIcon.iconset"

rm -rf "$build_root"
mkdir -p "$macos_path" "$resources_path" "$icon_work"

for architecture in arm64 x86_64; do
    scratch_path="$build_root/spm-$architecture"
    swift build \
        --package-path "$project_root" \
        --scratch-path "$scratch_path" \
        --configuration release \
        --arch "$architecture" \
        --product DoubaoWeTypeBridge
    binary_path="$(swift build \
        --package-path "$project_root" \
        --scratch-path "$scratch_path" \
        --configuration release \
        --arch "$architecture" \
        --show-bin-path)/DoubaoWeTypeBridge"
    cp "$binary_path" "$build_root/DoubaoWeTypeBridge-$architecture"
done

lipo -create \
    "$build_root/DoubaoWeTypeBridge-arm64" \
    "$build_root/DoubaoWeTypeBridge-x86_64" \
    -output "$macos_path/DoubaoWeTypeBridge"

cp "$project_root/Config/Info.plist" "$contents_path/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$contents_path/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$contents_path/Info.plist"

xcrun swift "$project_root/Scripts/generate-icon.swift" "$build_root/AppIcon-1024.png"
for spec in \
    "icon_16x16.png:16" \
    "icon_16x16@2x.png:32" \
    "icon_32x32.png:32" \
    "icon_32x32@2x.png:64" \
    "icon_128x128.png:128" \
    "icon_128x128@2x.png:256" \
    "icon_256x256.png:256" \
    "icon_256x256@2x.png:512" \
    "icon_512x512.png:512" \
    "icon_512x512@2x.png:1024"; do
    name="${spec%%:*}"
    pixels="${spec##*:}"
    sips -z "$pixels" "$pixels" "$build_root/AppIcon-1024.png" --out "$icon_work/$name" >/dev/null
done
iconutil -c icns "$icon_work" -o "$resources_path/AppIcon.icns"

if [[ "$identity" == "-" ]]; then
    codesign --force --deep --sign - --entitlements "$project_root/Config/Entitlements.plist" "$app_path"
else
    codesign --force --deep --options runtime --timestamp \
        --sign "$identity" \
        --entitlements "$project_root/Config/Entitlements.plist" \
        "$app_path"
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
echo "$app_path"
