#!/usr/bin/env bash
# A real WordPress site (with the plugins people run) through the skill: inventory, export, convert, import, old URLs.
# Needs: php (with mysql, xml, mbstring, curl, zip, gd, intl), a MariaDB/MySQL server, wp-cli, icp, mops, python3.
source "$(dirname "$0")/lib.sh"
need php mysql mysqladmin icp mops python3 curl
command -v wp >/dev/null 2>&1 || { mkdir -p "$WORK/bin"; curl -sL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o "$WORK/bin/wp"; chmod +x "$WORK/bin/wp"; export PATH="$WORK/bin:$PATH"; }
PLUGINS="${PLUGINS:-contact-form-7 wordpress-seo woocommerce advanced-custom-fields elementor polylang}"
WPDIR="$WORK/wordpress"; W="wp --allow-root --path=$WPDIR"

section "install WordPress and seed it"
db_start && db_create wp && ok "database ready" || fail "database"
rm -rf "$WPDIR" && mkdir -p "$WORK" && (cd "$WORK" && curl -sL https://wordpress.org/latest.tar.gz | tar xz)
$W core config --dbname=wp --dbuser=wp --dbpass=wp-pass --dbhost=127.0.0.1 --skip-check >/dev/null
$W core install --url=https://www.example.test --title="Test site" --admin_user=admin --admin_password=admin-pass-123 --admin_email=admin@example.org --skip-email >/dev/null
$W rewrite structure '/%postname%/' >/dev/null; ok "WordPress $($W core version) installed"
if [ -n "$PLUGINS" ]; then $W plugin install $PLUGINS --activate > "$WORK/plugins.log" 2>&1 && ok "plugins active: $PLUGINS" || fail "plugin install (see $WORK/plugins.log)"; fi
$W user create redacteur editor@example.org --role=editor --display_name="Fatima El Amrani" --user_pass=x1 >/dev/null
$W term create category Nieuws --slug=nieuws >/dev/null
P1=$(wp_id post create --post_type=page --post_status=publish --post_title="Afval en recycling" --post_name=afval --post_content="<h2>Ophaaldagen</h2><p>Restafval elke dinsdag.</p>" --porcelain)
# shellcheck disable=SC1111
$W post create --post_type=page --post_status=publish --post_title="Résidents & visitors – Ünïcode ✓ 🚲" --post_name=english --post_content="<p>It's easy: “quotes”, tabs	and backslashes \\ here.</p>" --porcelain >/dev/null
$W post create --post_type=page --post_status=draft --post_title="Concept beleid" --post_name=concept-beleid --post_content="<p>Nog niet openbaar.</p>" --porcelain >/dev/null
N1=$(wp_id post create --post_status=publish --post_title="Wegwerkzaamheden Stationsweg" --post_name=wegwerkzaamheden-stationsweg --post_excerpt="Afgesloten tot 30 oktober." --post_content="<p>Omleiding via de Parklaan.</p>" --post_category=nieuws --post_author=2 --porcelain)
python3 - "$WORK/kaart.png" <<'PY'
import struct, zlib, sys   # a valid 400x300 PNG with only the standard library
w, h = 400, 300; raw = b"".join(b"\x00" + bytes([255, 225, 90]) * w for _ in range(h))
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
PY
$W media import "$WORK/kaart.png" --title="Kaart" --post_id="$P1" --porcelain >/dev/null
if $W plugin is-active contact-form-7 2>/dev/null; then F=$(wp_id post list --post_type=wpcf7_contact_form --field=ID); $W post create --post_type=page --post_status=publish --post_title="Contact" --post_name=contact --post_content="[contact-form-7 id=\"$F\"]" --porcelain >/dev/null; fi
if $W plugin is-active elementor 2>/dev/null; then
  P3=$(wp_id post create --post_type=page --post_status=publish --post_title="Over ons" --post_name=over-ons --post_content="" --porcelain)
  $W post meta update "$P3" _elementor_edit_mode builder >/dev/null; $W post meta update "$P3" _elementor_template_type wp-page >/dev/null
  $W post meta update "$P3" _elementor_data '[{"id":"a1b2c3","elType":"container","settings":[],"elements":[{"id":"d4e5f6","elType":"widget","widgetType":"heading","settings":{"title":"Welkom bij de gemeente","header_size":"h2"},"elements":[]}],"isInner":false}]' >/dev/null
fi
if $W plugin is-active polylang 2>/dev/null; then
  $W eval 'PLL()->model->add_language(["name"=>"Nederlands","slug"=>"nl","locale"=>"nl_NL","rtl"=>0,"term_group"=>0]); PLL()->model->add_language(["name"=>"English","slug"=>"en","locale"=>"en_US","rtl"=>0,"term_group"=>1]); pll_set_post_language('"$P1"', "nl");' >/dev/null 2>&1 || true
fi

section "Phase 1: the inventory script"
inv=$(inventory_script); out=$(cd "$WPDIR" && bash "$inv" 2>/dev/null)
assert_contains "detects WordPress" "$out" "Detected: \*\*WordPress\*\*"
assert_contains "names the custom-code directories" "$out" "wp-content/plugins"
[ -n "$PLUGINS" ] && assert_contains "lists installed plugins" "$out" "Installed plugins:"
assert_contains "finds WP-Cron" "$out" "wp-cron.php"
lines=$(printf '%s' "$out" | grep -c '^- ' || true); [ "$lines" -lt 60 ] && ok "inventory is focused ($lines list lines)" || fail "inventory too noisy ($lines list lines)"

section "export with the skill's WordPress script"
WPSCRIPTS="$WORK/wp-private-scripts"; WPEXPORT="$WORK/wp-private-export"
(umask 077; mkdir -p "$WPSCRIPTS"); rm -rf "$WPEXPORT"
section_block "$SKILL/references/frameworks.md" "## Scoped export helpers" php "$WPSCRIPTS/export-support.php"
section_block "$SKILL/references/frameworks.md" "## WordPress" php "$WPSCRIPTS/wp-export.php"
# Fixture-only approval: these IDs were created by this test; published status alone is not production approval.
POST_IDS=$(wp_ids post list --post_type=page,post --post_status=publish --field=ID)
USER_IDS=$(wp_ids user list --field=ID)
(cd "$WPDIR" && MIGRATION_WEB_ROOTS="$WPDIR" MIGRATION_EXPORT_DIR="$WPEXPORT" \
  MIGRATION_PUBLIC_POST_IDS="$POST_IDS" MIGRATION_USER_IDS="$USER_IDS" \
  $W eval-file "$WPSCRIPTS/wp-export.php" > "$WORK/wp-export.log" 2>&1) && ok "export script ran" || { fail "export script"; cat "$WORK/wp-export.log"; }
python3 - "$WPEXPORT" "$PLUGINS" <<'PY' > "$WORK/wp-export-check.txt"
import json, sys, re
ex, plugins = sys.argv[1], sys.argv[2]
# Explicit fixture adapter: retain raw metadata and map only this fixture's routes and roles to the example DTOs.
rows = list(map(json.loads, open(f"{ex}/content.jsonl")))
for r in rows:
    if "?" in r["route"]: raise ValueError("fixture route needs an explicit query mapping")
    r["slug"] = r["route"].strip("/")
for kind, filename in (("page", "pages"), ("post", "news")):
    with open(f"{ex}/{filename}.jsonl", "w") as f:
        for r in rows:
            if r["postType"] == kind: f.write(json.dumps(r, ensure_ascii=False) + "\n")
users = list(map(json.loads, open(f"{ex}/users.jsonl")))
roles = {frozenset(["administrator"]): "administrator", frozenset(["editor"]): "editor"}
for u in users: u["role"] = roles[frozenset(u["sourceRoles"])]  # unknown/multiple fixture roles fail closed
with open(f"{ex}/users.jsonl", "w") as f:
    for u in users: f.write(json.dumps(u, ensure_ascii=False) + "\n")
pages = {r["slug"]: r for r in rows if r["postType"] == "page"}
print("drafts excluded:", "concept-beleid" not in pages)
print("unicode intact:", pages["english"]["title"] == "Résidents & visitors – Ünïcode ✓ 🚲")
print("tabs and backslashes intact:", "tabs\tand backslashes \\ here" in pages["english"]["bodyHtml"].replace("&#8217;", "'"))
if "elementor" in plugins: print("page-builder page rendered:", len(pages["over-ons"]["bodyHtml"]) > 100)
if "polylang" in plugins: print("language exported:", pages["afval"].get("language") == "nl")
if "contact-form-7" in plugins: print("contact form rendered (a feature, not content):", "<form" in pages["contact"]["bodyHtml"])
print("no leftover shortcode syntax in fixture HTML:", not any(re.search(r'\[[A-Za-z][A-Za-z0-9_-]*(?:\s[^]]*)?/?\]', r["bodyHtml"]) for r in rows))
users = [json.loads(l) for l in open(f"{ex}/users.jsonl")]
print("no password hashes:", all("pass" not in json.dumps(u).lower() for u in users))
print("roles are WordPress roles:", {u["role"] for u in users} <= {"administrator", "editor", "author", "contributor", "subscriber"})
PY
while IFS=: read -r name val; do assert_eq "$name" "$(printf '%s' "$val" | tr -d ' ')" "True"; done < "$WORK/wp-export-check.txt"

section "Phase 3 and 4: convert, deploy the documented backend, import, reconcile"
P="$WORK/wp-backend"; project_from_docs "$P"; mkdir -p "$P/export"; cp "$WPEXPORT"/*.jsonl "$P/export/"; convert_exports "$P"
(cd "$P" && timeout 600 mops install >/dev/null 2>&1); net_start "$P" && deploy "$P" backend && ok "backend deployed" || fail "deploy"
import_all "$P" "$P/batches" > "$WORK/wp-import.log"; assert_missing "every batch imported" "$(cat "$WORK/wp-import.log")" "err"
c=$(counts "$P"); db_pages=$(rosql wp "SELECT COUNT(*) FROM wp_posts WHERE post_type='page' AND post_status='publish'"); db_posts=$(rosql wp "SELECT COUNT(*) FROM wp_posts WHERE post_type='post' AND post_status='publish'"); db_users=$(rosql wp "SELECT COUNT(*) FROM wp_users")
assert_eq "pages reconcile with the database" "$(count_of "$c" pages)" "$db_pages"; assert_eq "posts reconcile" "$(count_of "$c" news)" "$db_posts"; assert_eq "users reconcile" "$(count_of "$c" legacyUsers)" "$db_users"
assert_eq "draft hidden on ICP" "$(call "$P" backend getPage '("concept-beleid")' --query | tr -d '\n ')" "(null)"

section "frontend: WordPress permalinks on the static-site canister"
rm -rf "$P/dist"; build_pages "$P/dist" "$P/export" dir >/dev/null
mkdir -p "$P/dist/wp-content" && cp -r "$WPDIR/wp-content/uploads" "$P/dist/wp-content/uploads"
deploy "$P" frontend && ok "frontend deployed" || fail "frontend deploy"
G=$(cd "$P" && icp network status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('gateway_url') or d.get('api_url'))" | sed 's#/$##'); F="http://frontend.local.localhost:${G##*:}"
assert_http "/afval/ serves" "$F/afval/" 200
assert_eq "/afval redirects to /afval/" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$F/afval")" "307 $F/afval/"
assert_http "post permalink serves" "$F/wegwerkzaamheden-stationsweg/" 200
img=$(find "$WPDIR/wp-content/uploads" -name 'kaart*.png' | head -1); assert_http "uploaded image at its old path" "$F/wp-content/uploads/${img#"$WPDIR/wp-content/uploads/"}" 200
assert_http "draft is a 404" "$F/concept-beleid/" 404
assert_http "wp-admin is gone" "$F/wp-admin/" 404
assert_contains "home page carries the ?p= mapping" "$(curl -s "$F/")" "\"$N1\":\"/wegwerkzaamheden-stationsweg/\""
net_stop "$P"; summary
