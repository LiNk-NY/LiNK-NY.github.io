#!/usr/bin/env bash
# Preview the site locally with the Hugo version CI uses (0.119.0).
# Extra arguments are passed to `hugo server`, e.g. ./preview.sh --buildDrafts
set -euo pipefail

HUGO="${HUGO:-$HOME/.local/bin/hugo-0.119}"

if [[ ! -x "$HUGO" ]]; then
  echo "Hugo 0.119 not found at $HUGO (set HUGO=/path/to/hugo to override)" >&2
  exit 1
fi
if ! command -v go >/dev/null; then
  echo "Go is required for Hugo modules; install it with: sudo apt install golang-go" >&2
  exit 1
fi

cd "$(dirname "$0")"
exec "$HUGO" server --disableFastRender "$@"
