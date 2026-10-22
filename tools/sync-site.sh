#!/usr/bin/env bash
# Copies the skill from this repository into a website folder: the raw files agents read, the download zip,
# and the readable pages. Run it before every site deploy. Never edit skill files inside a site folder.
# Usage: tools/sync-site.sh <site dist folder>      e.g.  tools/sync-site.sh ~/sites/phptomotoko/dist
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DIST="${1:?usage: tools/sync-site.sh <site dist folder>}"
[ -d "$DIST" ] || { echo "not a folder: $DIST"; exit 1; }
DIST="$(cd "$DIST" && pwd -P)" # zip runs from the source folder, so relative paths must be resolved now.
SKILL="$ROOT/skills/migrating-php-apps"
[ -f "$SKILL/SKILL.md" ] || { echo "missing source: $SKILL/SKILL.md"; exit 1; }
command -v zip >/dev/null || { echo "zip is required"; exit 1; }

# Keep the renderer's dependencies local to this checkout; never change system Python.
PYTHON="$ROOT/.venv-site/bin/python"
if [ ! -x "$PYTHON" ]; then
  python3 -m venv "$ROOT/.venv-site"
fi
if ! "$PYTHON" -c 'import markdown, pymdownx' 2>/dev/null; then
  "$PYTHON" -m pip install --disable-pip-version-check --no-cache-dir --index-url https://pypi.org/simple markdown pymdown-extensions
fi

mkdir -p "$DIST/skills"
SKILLS_OUT="$(cd "$DIST/skills" && pwd -P)"
OUT="$SKILLS_OUT/migrating-php-apps"
case "$OUT/" in
  "$SKILL/"|"$SKILL/"*) echo "destination overlaps the skill source: $OUT"; exit 1 ;;
esac

# Prepare every artifact before replacing the current copy. Copying the complete
# skill folder also preserves its bundled LICENSE and the Markdown agents read.
STAGE="$(mktemp -d "$SKILLS_OUT/.sync-migrating-php-apps.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$SKILL" "$STAGE/migrating-php-apps"
(cd "$ROOT/skills" && zip -qr "$STAGE/migrating-php-apps.zip" migrating-php-apps)
PYTHONDONTWRITEBYTECODE=1 "$PYTHON" "$ROOT/tools/render-skill-pages.py" "$SKILL" "$STAGE/migrating-php-apps" --site-dist "$DIST"
rm -rf "$OUT"
mv "$STAGE/migrating-php-apps" "$OUT"
mv -f "$STAGE/migrating-php-apps.zip" "$SKILLS_OUT/migrating-php-apps.zip"
echo "synced $(find "$OUT" -type f | wc -l) files into $OUT, plus skills/migrating-php-apps.zip"
echo "skill version: $(cd "$ROOT" && git describe --always --dirty 2>/dev/null || echo 'unknown: not a git checkout')"
echo "next: run the site's own build step if it has one (for example python3 stamp.py dist), then deploy."
