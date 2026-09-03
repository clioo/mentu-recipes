#!/bin/sh
# Mentu Recipes installer.
#
#   curl -fsSL https://get.mentu.ai | sh
#
# This exact script is in the public repository, so you can read it before you
# run it: https://github.com/mentu-ai/mentu-recipes/blob/main/scripts/install.sh
#
# It downloads the release binary for this Mac's CPU, checks it against the
# checksums published with the release, and puts it in ~/.local/bin. It does
# not use sudo and it does not edit your shell profile.
#
# Environment:
#   MENTU_VERSION       version to install, for example 0.3.0 (default: latest)
#   MENTU_INSTALL_DIR   where to put the binary (default: ~/.local/bin)
#   MENTU_WITH_SKILLS   1 to also register the Claude Code plugin
set -eu

REPO="mentu-ai/mentu-recipes"
INSTALL_DIR="${MENTU_INSTALL_DIR:-$HOME/.local/bin}"
WANTED="${MENTU_VERSION:-latest}"

say() { printf '%s\n' "$*"; }
die() { printf 'install: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Mentu Recipes runs on macOS. This machine reports $(uname -s)."
command -v curl >/dev/null 2>&1 || die "curl is required."
command -v shasum >/dev/null 2>&1 || die "shasum is required."

case "$(uname -m)" in
  arm64)  asset="mentu-recipes-macos-arm64" ;;
  x86_64) asset="mentu-recipes-macos-x86_64" ;;
  *)      die "unsupported CPU: $(uname -m). Apple Silicon and Intel are supported." ;;
esac

if [ "$WANTED" = "latest" ]; then
  # Follow the redirect on releases/latest. No API token, no rate limit.
  resolved="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null || true)"
  tag="${resolved##*/}"
  case "$tag" in v[0-9]*) ;; *) die "could not work out the latest version. Set MENTU_VERSION and try again." ;; esac
else
  case "$WANTED" in v*) tag="$WANTED" ;; *) tag="v$WANTED" ;; esac
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
base="https://github.com/$REPO/releases/download/$tag"

say "Downloading mentu-recipes $tag for $(uname -m)"
curl -fsSL "$base/$asset" -o "$tmp/$asset" || die "no $asset in release $tag"
curl -fsSL "$base/checksums.txt" -o "$tmp/checksums.txt" || die "no checksums.txt in release $tag"

expected="$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1 }' "$tmp/checksums.txt" | head -1)"
[ -n "$expected" ] || die "release $tag publishes no checksum for $asset"
actual="$(shasum -a 256 "$tmp/$asset" | awk '{ print $1 }')"
[ "$expected" = "$actual" ] || die "checksum mismatch for $asset
  expected $expected
  actual   $actual
Nothing was installed."

mkdir -p "$INSTALL_DIR" || die "cannot create $INSTALL_DIR"
chmod +x "$tmp/$asset"
mv -f "$tmp/$asset" "$INSTALL_DIR/mentu-recipes" || die "cannot write to $INSTALL_DIR"

installed="$("$INSTALL_DIR/mentu-recipes" --version 2>/dev/null || echo "mentu-recipes $tag")"
say "Installed  $INSTALL_DIR/mentu-recipes  ($installed)"

on_path=no
case ":$PATH:" in *":$INSTALL_DIR:"*) on_path=yes ;; esac
if [ "$on_path" = "no" ]; then
  say ""
  say "$INSTALL_DIR is not on your PATH yet. Add it with one of these:"
  case "${SHELL##*/}" in
    zsh)  say "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.zshrc && exec zsh" ;;
    bash) say "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.bash_profile && exec bash -l" ;;
    *)    say "  export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
  esac
fi

say ""
say "Next"
say "  mentu-recipes setup"
say "  Shows what is on this Mac, writes one example recipe here, runs it, prints the record."

if command -v claude >/dev/null 2>&1; then
  if [ "${MENTU_WITH_SKILLS:-0}" = "1" ]; then
    say ""
    say "Adding the Mentu skills to Claude Code"
    claude plugin marketplace add "$REPO" >/dev/null 2>&1 || say "  could not add the marketplace; run it yourself: claude plugin marketplace add $REPO"
    claude plugin install mentu-recipes@mentu >/dev/null 2>&1 || say "  could not install the plugin; run it yourself: claude plugin install mentu-recipes@mentu"
    say "  Done. Claude Code picks it up in your next session."
  else
    say ""
    say "Claude Code is installed here. To give it the Mentu skills:"
    say "  claude plugin marketplace add $REPO"
    say "  claude plugin install mentu-recipes@mentu"
  fi
fi

say ""
say "Docs  https://docs.mentu.ai/quick-start"
