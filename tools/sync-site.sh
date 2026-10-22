#!/usr/bin/env bash
# Copies the skill from this repository into a website folder: the raw files agents read, the download zip,
# and the readable pages. Run it before every site deploy. Never edit skill files inside a site folder.
# Usage: tools/sync-site.sh <site dist folder>      e.g.  tools/sync-site.sh ~/sites/phptomotoko/dist
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${1:?usage: tools/sync-site.sh <site dist folder>}"
[ -d "$DIST" ] || { echo "not a folder: $DIST"; exit 1; }
SKILL="$ROOT/skills/migrating-php-apps"; OUT="$DIST/skills/migrating-php-apps"
rm -rf "$OUT"; mkdir -p "$DIST/skills"; cp -r "$SKILL" "$OUT"
(cd "$ROOT/skills" && rm -f "$DIST/skills/migrating-php-apps.zip" && zip -qr "$DIST/skills/migrating-php-apps.zip" migrating-php-apps)
python3 -c "import markdown, pymdownx" 2>/dev/null || pip install -q markdown pymdown-extensions 2>/dev/null || pip install -q --break-system-packages markdown pymdown-extensions
python3 "$ROOT/tools/render-skill-pages.py" "$SKILL" "$OUT"
echo "synced $(find "$OUT" -type f | wc -l) files into $OUT, plus skills/migrating-php-apps.zip"
echo "skill version: $(cd "$ROOT" && git log -1 --format='%h (%cs)' 2>/dev/null || echo 'unknown: not a git checkout')"
echo "next: run the site's own build step if it has one (for example python3 stamp.py dist), then deploy."
