#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: notarize.sh <dmg-path>" >&2
    exit 2
fi

: "${NOTARY_KEY_PATH:?NOTARY_KEY_PATH is required}"
: "${NOTARY_KEY_ID:?NOTARY_KEY_ID is required}"
: "${NOTARY_ISSUER_ID:?NOTARY_ISSUER_ID is required}"

dmg_path="$1"
xcrun notarytool submit "$dmg_path" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
