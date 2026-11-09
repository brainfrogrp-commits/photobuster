#!/bin/bash
# Builds PhotoSwipeCleaner.ipa for installing with SideStore.
# The app is left unsigned here; SideStore signs it with your Apple ID when it installs it.
# Run from Terminal on your Mac:  ./scripts/make-ipa.sh
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="build"
rm -rf "$OUT"

xcodebuild \
  -project PhotoSwipeCleaner.xcodeproj \
  -target PhotoSwipeCleaner \
  -configuration Release \
  -sdk iphoneos \
  SYMROOT="$PWD/$OUT/products" \
  OBJROOT="$PWD/$OUT/intermediates" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

mkdir -p "$OUT/Payload"
cp -R "$OUT/products/Release-iphoneos/PhotoSwipeCleaner.app" "$OUT/Payload/"
(cd "$OUT" && zip -qry PhotoSwipeCleaner.ipa Payload)

echo
echo "Done. Your app file is: $PWD/$OUT/PhotoSwipeCleaner.ipa"
open -R "$OUT/PhotoSwipeCleaner.ipa" 2>/dev/null || true
