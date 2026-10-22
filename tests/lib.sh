#!/usr/bin/env bash
# Shared helpers for the migrating-php-apps test suite. Source this file; do not run it.
# Every test takes its scripts and code from the skill's own documentation, so the docs are what gets tested.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/skills/migrating-php-apps"
# shellcheck disable=SC2034  # used by the test scripts that source this file
# shellcheck disable=SC2034  # used by the scripts that source this file
FIXTURES="$ROOT/tests/fixtures"
WORK="${WORK:-/tmp/mpa-tests}"
mkdir -p "$WORK"
export USER="${USER:-tester}"          # icp-cli needs a user name
export DEBIAN_FRONTEND=noninteractive COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_NO_INTERACTION=1 COMPOSER_PROCESS_TIMEOUT=900

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
assert_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$3', got '$2')"; fi; }
assert_contains() { if printf '%s' "$2" | grep -q -- "$3"; then ok "$1"; else fail "$1 (missing '$3')"; fi; }
assert_missing()  { if printf '%s' "$2" | grep -q -- "$3"; then fail "$1 (unexpected '$3')"; else ok "$1"; fi; }
assert_http()     { local code; code=$(curl -s -o /dev/null -w '%{http_code}' "$2"); assert_eq "$1" "$code" "$3"; }
summary()         { echo; echo "== $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; }
section()         { echo; echo "== $1"; }

need() { for t in "$@"; do command -v "$t" >/dev/null 2>&1 || { echo "missing tool: $t (see tests/README.md)"; exit 2; }; done; }

# wp-cli output can include plugin notices even with --field=ID or --porcelain.
# Keep diagnostics visible and command failures intact; return only positive,
# distinct IDs for the synthetic fixture's explicitly approved export scope.
wp_ids() {
  local output ids expected
  output=$($W "$@") || return "$?"
  ids=$(printf '%s\n' "$output" | awk '/^[1-9][0-9]*$/ {
      if (seen[$0]++) duplicate=1
      ids=ids (n++ ? "," : "") $0
    } END { if (n && !duplicate) print ids; else exit 1 }') || {
    printf 'Expected distinct positive WordPress IDs, got:\n%s\n' "$output" >&2
    return 1
  }
  expected=$(printf '%s' "$ids" | tr ',' '\n')
  [ "$output" = "$expected" ] || printf 'WordPress output accompanying IDs:\n%s\n' "$output" >&2
  printf '%s\n' "$ids"
}
wp_id() {
  local id
  id=$(wp_ids "$@") || return "$?"
  case "$id" in *,*) printf 'Expected one WordPress ID, got: %s\n' "$id" >&2; return 1;; esac
  printf '%s\n' "$id"
}

# --- scripts and code blocks taken from the docs --------------------------------------------------
# extract_block FILE LANG NTH OUT   (NTH counts from 0 among blocks of that language; "longest" picks the longest)
extract_block() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import re, sys
f, lang, nth, out = sys.argv[1:]
blocks = re.findall(r"```%s\n(.*?)```" % re.escape(lang), open(f).read(), re.S)
b = max(blocks, key=len) if nth == "longest" else blocks[int(nth)]
# doc blocks nested in list items are indented by two spaces
lines = b.splitlines()
if lines and all(l.startswith("  ") or l == "" for l in lines): lines = [l[2:] for l in lines]
open(out, "w").write("\n".join(lines) + "\n")
PY
}
# section_block FILE "## Heading" LANG OUT   (first block of LANG under that heading)
section_block() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import re, sys
f, heading, lang, out = sys.argv[1:]
s = open(f).read(); i = s.index(heading); j = s.find("\n## ", i + 1); sec = s[i:j if j > 0 else len(s)]
b = re.search(r"```%s\n(.*?)```" % re.escape(lang), sec, re.S).group(1)
lines = b.splitlines()
if lines and all(l.startswith("  ") or l == "" for l in lines): lines = [l[2:] for l in lines]
open(out, "w").write("\n".join(lines) + "\n")
PY
}
inventory_script() { extract_block "$SKILL/references/inventory.md" bash longest "$WORK/php-inventory.sh"; echo "$WORK/php-inventory.sh"; }
converter_script() { extract_block "$SKILL/references/data-import.md" python 0 "$WORK/jsonl_to_candid.py"; echo "$WORK/jsonl_to_candid.py"; }

# project_from_docs DIR: the backend example exactly as documented (icp.yaml, mops.toml, src/backend/**)
project_from_docs() {
  local dir=$1; rm -rf "$dir"; mkdir -p "$dir"
  python3 - "$SKILL/references/backend-example.md" "$dir" <<'PY'
import re, sys, pathlib
text = open(sys.argv[1]).read(); root = pathlib.Path(sys.argv[2])
for m in re.finditer(r"^## ((?:src/[\w/.-]+)|icp\.yaml|mops\.toml)[ \t]*$", text, re.M):
    rest = text[m.end():]; c = re.search(r"```[\w-]*\n(.*?)```", rest, re.S); nxt = re.search(r"^## ", rest, re.M)
    if c and (not nxt or c.start() < nxt.start()):
        p = root / m.group(1); p.parent.mkdir(parents=True, exist_ok=True); p.write_text(c.group(1))
PY
}

# convert DIR_WITH_export/ : the documented converter with the documented field types
convert_exports() {
  local dir=$1 conv; conv=$(converter_script); mkdir -p "$dir/batches"; rm -f "$dir"/batches/*.did
  (cd "$dir" && python3 "$conv" export/pages.jsonl batches/pages legacyId:nat slug:text title:text bodyHtml:text published:bool updatedAt:time >/dev/null \
    && python3 "$conv" export/news.jsonl batches/news legacyId:nat slug:text title:text summary:opt:text bodyHtml:text publishedAt:opt:time authorLegacyId:opt:nat >/dev/null \
    && python3 "$conv" export/users.jsonl batches/users legacyId:nat email:text displayName:text role:variant >/dev/null)
}

# --- local ICP network (project-local) -------------------------------------------------------------
net_start() { (cd "$1" && icp network stop >/dev/null 2>&1 || true; timeout 240 icp network start -d > "$WORK/net.log" 2>&1) || { cat "$WORK/net.log"; return 1; }; }
net_stop()  { (cd "$1" && icp network stop >/dev/null 2>&1 || true); }
deploy()    { (cd "$1" && shift && timeout 600 icp deploy "$@" > "$WORK/deploy.log" 2>&1) || { tail -20 "$WORK/deploy.log"; return 1; }; }
call()      { local dir=$1; shift; (cd "$dir" && icp canister call "$@" -e local 2>&1); }
import_all() { # import_all PROJECT_DIR BATCH_DIR [extra icp args]
  local dir=$1 b=$2; shift 2; local f m
  for f in "$b"/pages-*.did "$b"/news-*.did "$b"/users-*.did; do
    [ -f "$f" ] || continue; m=importPages; case $f in *news*) m=importNews;; *users*) m=importLegacyUsers;; esac
    call "$dir" backend "$m" --args-file "$f" "$@" | tr -d '\n'; echo
  done
}
counts() { call "$1" backend importCounts '()' --query | tr -d '\n '; }   # e.g. (record{news=3:nat;legacyUsers=2:nat;pages=4:nat})
count_of() { printf '%s' "$1" | grep -o "$2=[0-9_]*" | cut -d= -f2 | tr -d '_'; }

# --- database (MariaDB or MySQL on 127.0.0.1) ------------------------------------------------------
DB_ROOT="${DB_ROOT:-root}"; DB_ROOT_PASS="${DB_ROOT_PASS:-}"
rootsql() { if [ -n "$DB_ROOT_PASS" ]; then mysql -u"$DB_ROOT" -p"$DB_ROOT_PASS" -h 127.0.0.1 -e "$1"; else mysql -u"$DB_ROOT" -e "$1"; fi; }
db_alive() { mysqladmin ping >/dev/null 2>&1 || mysqladmin -h 127.0.0.1 ${DB_ROOT_PASS:+-u"$DB_ROOT" -p"$DB_ROOT_PASS"} ping >/dev/null 2>&1; }
db_start() {
  db_alive && return 0
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q -E '^(mysql|mariadb)\.service'; then
    for svc in mysql mariadb; do
      if command -v sudo >/dev/null 2>&1; then sudo -n systemctl start "$svc" >/dev/null 2>&1 || true; else systemctl start "$svc" >/dev/null 2>&1 || true; fi
    done
    sleep 2; db_alive && return 0
  fi
  command -v mariadbd >/dev/null 2>&1 || { echo "no database server running and mariadbd is not installed"; return 1; }
  local d="$WORK/mysql"; mkdir -p "$d/data" /run/mysqld; chown -R mysql:mysql "$d" /run/mysqld 2>/dev/null || true
  [ -d "$d/data/mysql" ] || mysql_install_db --user=mysql --datadir="$d/data" >/dev/null 2>&1
  setsid nohup mariadbd --user=mysql --datadir="$d/data" --socket=/run/mysqld/mysqld.sock --port=3306 --bind-address=127.0.0.1 > "$d/mariadbd.log" 2>&1 < /dev/null &
  for _ in $(seq 1 30); do sleep 1; db_alive && return 0; done
  cat "$d/mariadbd.log"; return 1
}
db_create() { # db_create NAME: a fresh database (any previous one is dropped), a full user NAME / "NAME-pass", and a read-only user "ro" / "ro-pass" (the skill wants one)
  rootsql "DROP DATABASE IF EXISTS \`$1\`; CREATE DATABASE \`$1\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER IF NOT EXISTS '$1'@'localhost' IDENTIFIED BY '$1-pass'; CREATE USER IF NOT EXISTS '$1'@'127.0.0.1' IDENTIFIED BY '$1-pass';
    GRANT ALL ON \`$1\`.* TO '$1'@'localhost'; GRANT ALL ON \`$1\`.* TO '$1'@'127.0.0.1';
    CREATE USER IF NOT EXISTS 'ro'@'localhost' IDENTIFIED BY 'ro-pass'; GRANT SELECT ON \`$1\`.* TO 'ro'@'localhost'; FLUSH PRIVILEGES;"
}
rosql() { mysql -N -u ro -pro-pass --default-character-set=utf8mb4 "$1" -e "$2"; }   # rosql DB "SQL"

# --- static frontends for the migrated content --------------------------------------------------------
# build_pages DIST EXPORT_DIR MODE(dir|file)   : one HTML file per exported page/news item at its old path
build_pages() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, pathlib, html, sys
d, ex, mode = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
d.mkdir(parents=True, exist_ok=True)
rows = [json.loads(l) for f in ("pages.jsonl", "news.jsonl") for l in open(ex / f)]
tpl = lambda t, b: f'<!doctype html><html lang="nl"><head><meta charset="utf-8"><title>{html.escape(t)}</title></head><body><main><h1>{html.escape(t)}</h1>{b}</main></body></html>'
mapping = {}
for r in rows:
    p = (d / r["slug"] / "index.html") if mode == "dir" else (d / (r["slug"] + ".html"))
    p.parent.mkdir(parents=True, exist_ok=True); p.write_text(tpl(r["title"], r["bodyHtml"]))
    mapping[str(r["legacyId"])] = f"/{r['slug']}/" if mode == "dir" else f"/{r['slug']}"
script = "<script>(function(){var q=new URLSearchParams(location.search),m=" + json.dumps(mapping, separators=(",", ":")) + ";var id=q.get('p')||q.get('page_id');if(id&&m[id]){location.replace(m[id]);}})();</script>"
(d / "index.html").write_text(tpl("Home", "<ul>" + "".join(f'<li><a href="{v}">{k}</a></li>' for k, v in mapping.items()) + "</ul>").replace("<head>", "<head>" + script, 1))
(d / "404.html").write_text(tpl("Not found", "<p>Gone.</p>"))
(d / "_headers").write_text("/*\n  X-Content-Type-Options: nosniff\n")
print("pages built:", len(rows))
PY
}
