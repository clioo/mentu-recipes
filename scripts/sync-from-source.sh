#!/bin/sh
set -eu

SHIP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_SOURCE_ROOT="$(cd "$SHIP_ROOT/../mentu-recipes" && pwd)"
SOURCE_ROOT="${MENTU_RECIPES_SOURCE_ROOT:-$DEFAULT_SOURCE_ROOT}"

if [ ! -f "$SOURCE_ROOT/Package.swift" ] || [ ! -d "$SOURCE_ROOT/Sources/MentuRecipesCore" ]; then
  echo "refusing sync: source root is not mentu-recipes: $SOURCE_ROOT" >&2
  exit 2
fi

for item in Package.swift Sources Tests; do
  /bin/rm -rf "$SHIP_ROOT/$item"
  /bin/cp -R "$SOURCE_ROOT/$item" "$SHIP_ROOT/$item"
done

/bin/rm -rf \
  "$SHIP_ROOT/.build" \
  "$SHIP_ROOT/dist"

echo "synced public runtime files into ship gate"
