#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT="mentu-recipes"
FORBIDDEN_RE="$(
  {
    printf '%s%s\n' Trust Computer
    printf '%s%s\n' Completion Detector
    printf '%s%s\n' Contradiction Detector
    printf '%s%s\n' Epistemic Kernel
    printf '%s%s\n' Health Computer
    printf '%s%s\n' Entropy Measure
    printf '%s%s\n' Embedding Index
    printf '%s%s\n' MIL Generator
    printf '%s%s\n' LLM GraphLoader
    printf '%s%s%s%s\n' A NE C IRGenerator
    printf '%s\n' SDPA
    printf '%s %s\n' padding strategy
    printf '%s %s\n' weight blob
    printf '%s%s\n' Mentu MCP
    printf '%s%s\n' Spec tre
    printf '%s%s\n' Craw lio
    printf '%s%s\n' Ghi dra
    printf '%s%s\n' Sub trace
    printf '%s %s%s\n' STRICTLY CONFI DENTIAL
    printf '/%s/%s\n' Users rashid
    printf '%s%s\n' mentu -complete
    printf '%s%s\n' api -server
    printf '%s%s%s\n' mentu -artifacts -private
  } |
  sed 's/.*/(&)/' |
  paste -sd'|' -
)"
SECRET_RE='s[k]-proj-[A-Za-z0-9_-]{20,}|s[k]-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}'

usage() {
  cat <<EOF
usage: $0 [--source] [--binary PATH] [--package PATH]

Validates the mentu-recipes ship surface:
  --source       run the source release scanner
  --binary PATH  scan a built Mach-O for forbidden strings/symbols and local symbols
  --package PATH scan a pkg payload and expanded package strings
EOF
}

fail_matches() {
  title="$1"
  file="$2"
  if [ -s "$file" ]; then
    echo "refusing release: $title" >&2
    sed -n '1,40p' "$file" >&2
    exit 10
  fi
}

scan_stream() {
  title="$1"
  findings="$(mktemp)"
  if grep -Ei "$FORBIDDEN_RE|$SECRET_RE" > "$findings"; then
    fail_matches "$title" "$findings"
  fi
  rm -f "$findings"
}

validate_source() {
  (cd "$ROOT" && swift run "$PRODUCT" scan "$ROOT")
}

validate_binary() {
  binary="$1"
  [ -f "$binary" ] || { echo "binary not found: $binary" >&2; exit 11; }

  strings "$binary" | scan_stream "forbidden string found in binary"

  findings="$(mktemp)"
  if nm "$binary" 2>/dev/null | grep -Ei "$FORBIDDEN_RE" > "$findings"; then
    fail_matches "forbidden symbol found in binary" "$findings"
  fi
  rm -f "$findings"

  local_symbols="$(mktemp)"
  nm "$binary" 2>/dev/null | awk '$2 ~ /^[a-z]$/ { print }' > "$local_symbols" || true
  if [ -s "$local_symbols" ]; then
    echo "refusing release: binary still has local symbols; run strip -x before signing" >&2
    sed -n '1,40p' "$local_symbols" >&2
    exit 12
  fi
  rm -f "$local_symbols"
}

validate_payload() {
  package="$1"
  payload="$(pkgutil --payload-files "$package")"
  unexpected="$(
    printf '%s\n' "$payload" | grep -E -v '^\.?$|^\./usr$|^\./usr/local$|^\./usr/local/bin$|^\./usr/local/bin/mentu-recipes$|(^|/)\._' || true
  )"
  if [ -n "$unexpected" ]; then
    echo "refusing release: package contains unexpected payload files" >&2
    printf '%s\n' "$unexpected" >&2
    exit 13
  fi
}

validate_package() {
  package="$1"
  [ -f "$package" ] || { echo "package not found: $package" >&2; exit 14; }
  validate_payload "$package"

  expanded="$(mktemp -d)"
  pkgutil --expand-full "$package" "$expanded/pkg"
  find "$expanded/pkg" -type f -print0 | xargs -0 strings 2>/dev/null | scan_stream "forbidden string found in package"
  rm -rf "$expanded"
}

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source)
      validate_source
      shift
      ;;
    --binary)
      validate_binary "$2"
      shift 2
      ;;
    --package)
      validate_package "$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

echo "ship validation passed"
