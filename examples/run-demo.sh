#!/bin/sh
# Run one of the bundled demo recipes in a throwaway git workspace.
#
#   examples/run-demo.sh hello-justifiable
#   examples/run-demo.sh demo-compound
#   examples/run-demo.sh demo-parallel
#
# The demos declare `expected_changes`, so the runner commits the artifacts it
# was told to expect. Running them here keeps those commits inside a scratch
# repository under $TMPDIR instead of your clone of this one.
set -eu

RECIPE="${1:-hello-justifiable}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${MENTU_RECIPES_BIN:-$REPO_ROOT/.build/debug/mentu-recipes}"

if [ ! -x "$BIN" ]; then
  echo "build the runner first: swift build" >&2
  exit 2
fi

WORK="${2:-$(mktemp -d "${TMPDIR:-/tmp}/mentu-demo.XXXXXX")}"
mkdir -p "$WORK/.mentu/recipes" "$WORK/.mentu/prompts"
cp "$REPO_ROOT"/.mentu/recipes/*.json "$WORK/.mentu/recipes/"
[ -d "$REPO_ROOT/.mentu/prompts" ] && cp -R "$REPO_ROOT"/.mentu/prompts/. "$WORK/.mentu/prompts/" 2>/dev/null || true

cd "$WORK"
if [ ! -d .git ]; then
  git init --quiet .
  git config user.name "mentu demo"
  git config user.email "demo@example.invalid"
  printf '.mentu/runs/\n.mentu/cache/\n' > .gitignore
  git add -A
  git commit --quiet -m "demo baseline"
fi

echo "workspace: $WORK"
echo
"$BIN" run "$RECIPE" --workspace "$WORK"
STATUS=$?

echo
echo "artifacts:"
find "$WORK/examples" -type f 2>/dev/null | sed "s|$WORK/||" || echo "  none"
echo
echo "commits the runner made for declared artifacts:"
git --no-pager log --oneline | head -20

exit $STATUS
