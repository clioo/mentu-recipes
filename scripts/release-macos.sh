#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-0.1.0}"
TEAM_ID="${TEAM_ID:-HR8X6TP7J6}"
APP_IDENTITY="${APP_IDENTITY:-Developer ID Application: Rashid Azarang (HR8X6TP7J6)}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-Developer ID Installer: Rashid Azarang (HR8X6TP7J6)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-mentu-notary}"
IDENTIFIER="${IDENTIFIER:-ai.mentu.recipes}"
PRODUCT="mentu-recipes"
DIST="$ROOT/dist"
STAGE="$DIST/stage"
PKG="$DIST/$PRODUCT-$VERSION-macos-arm64.pkg"
MANIFEST="$DIST/$PRODUCT-$VERSION-macos-arm64.json"

if [ "${SYNC_FROM_SOURCE:-0}" = "1" ]; then
  "$ROOT/scripts/sync-from-source.sh"
fi

rm -rf "$DIST"
mkdir -p "$STAGE/usr/local/bin"

swift test
swift build -c release
"$ROOT/scripts/release-validate.sh" --source

cp "$ROOT/.build/release/$PRODUCT" "$STAGE/usr/local/bin/$PRODUCT"
xattr -cr "$STAGE" 2>/dev/null || true
find "$STAGE" -name '._*' -delete
strip -x "$STAGE/usr/local/bin/$PRODUCT"

codesign --force \
  --timestamp \
  --options runtime \
  --sign "$APP_IDENTITY" \
  "$STAGE/usr/local/bin/$PRODUCT"

codesign --verify --strict --verbose=2 "$STAGE/usr/local/bin/$PRODUCT"
"$ROOT/scripts/release-validate.sh" --binary "$STAGE/usr/local/bin/$PRODUCT"

xattr -cr "$STAGE" 2>/dev/null || true
find "$STAGE" -name '._*' -delete

COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1 pkgbuild \
  --root "$STAGE" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location "/" \
  --sign "$INSTALLER_IDENTITY" \
  "$PKG"

"$ROOT/scripts/release-validate.sh" --package "$PKG"

xcrun notarytool submit "$PKG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --team-id "$TEAM_ID" \
  --wait

xcrun stapler staple "$PKG"
spctl -a -vv -t install "$PKG"
"$ROOT/scripts/release-validate.sh" --package "$PKG"

SHA256="$(shasum -a 256 "$PKG" | awk '{print $1}')"
SIZE_BYTES="$(wc -c < "$PKG" | tr -d ' ')"
cat > "$MANIFEST" <<EOF
{
  "name": "$PRODUCT",
  "version": "$VERSION",
  "platform": "macos-arm64",
  "identifier": "$IDENTIFIER",
  "sha256": "$SHA256",
  "size_bytes": $SIZE_BYTES,
  "package": "$(basename "$PKG")"
}
EOF

echo "package: $PKG"
echo "manifest: $MANIFEST"
