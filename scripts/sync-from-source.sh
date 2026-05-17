#!/bin/sh
set -eu

SHIP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_SOURCE_ROOT="$(cd "$SHIP_ROOT/../mentu-recipes" && pwd)"
SOURCE_ROOT="${MENTU_RECIPES_SOURCE_ROOT:-$DEFAULT_SOURCE_ROOT}"

if [ ! -f "$SOURCE_ROOT/Package.swift" ] || [ ! -d "$SOURCE_ROOT/Sources/MentuRecipesCore" ]; then
  echo "refusing sync: source root is not mentu-recipes: $SOURCE_ROOT" >&2
  exit 2
fi

for item in Package.swift LICENSE README.md .gitignore Sources Tests .mentu; do
  /bin/rm -rf "$SHIP_ROOT/$item"
  /bin/cp -R "$SOURCE_ROOT/$item" "$SHIP_ROOT/$item"
done

/bin/rm -rf \
  "$SHIP_ROOT/.build" \
  "$SHIP_ROOT/dist" \
  "$SHIP_ROOT/.mentu/runs" \
  "$SHIP_ROOT/.mentu/cache" \
  "$SHIP_ROOT/.mentu/state" \
  "$SHIP_ROOT/.mentu/logs" \
  "$SHIP_ROOT/.mentu/tmp" \
  "$SHIP_ROOT/.mentu/training"

echo "synced mentu-recipes source into ship gate"
