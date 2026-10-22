#!/usr/bin/env bash
# A real Drupal site (Composer layout, web/ root) through the skill: inventory, export, convert, import, old URLs.
# Needs: php, composer, a MariaDB/MySQL server, icp, mops, python3.
source "$(dirname "$0")/lib.sh"
need php composer mysql mysqladmin icp mops python3 curl
D="$WORK/drupal"; DR="$D/vendor/bin/drush"

section "install Drupal and seed it"
db_start && db_create drupal && ok "database ready" || fail "database"
rm -rf "$D" && timeout 900 composer create-project drupal/recommended-project "$D" --quiet 2> "$WORK/composer-drupal.log" && (cd "$D" && timeout 600 composer require drush/drush --quiet 2>> "$WORK/composer-drupal.log") && ok "Drupal project created" || { fail "composer (see $WORK/composer-drupal.log)"; exit 1; }
(cd "$D" && timeout 600 $DR site:install standard --db-url="mysql://drupal:drupal-pass@127.0.0.1/drupal" --site-name="Test" --account-name=admin --account-pass=admin-pass-123 -y > "$WORK/drush-install.log" 2>&1) && ok "Drupal $(cd "$D" && $DR status --field=drupal-version) installed" || { fail "site:install"; tail -5 "$WORK/drush-install.log"; }
# Drupal 11.4 sets up content types through recipes, which Drush's installer skips
for r in page_content_type article_content_type; do (cd "$D" && $DR recipe:apply "$D/web/core/recipes/$r" -y > "$WORK/recipe-$r.log" 2>&1) || true; done
(cd "$D" && $DR cache:rebuild -q && $DR php:eval '
use Drupal\node\Entity\Node; use Drupal\path_alias\Entity\PathAlias; use Drupal\user\Entity\User; use Drupal\file\Entity\File;
$n1 = Node::create(["type"=>"page","title"=>"Afval en recycling","body"=>["value"=>"<h2>Ophaaldagen</h2><p>Restafval elke dinsdag.</p>","format"=>"basic_html"],"status"=>1]); $n1->save();
$n2 = Node::create(["type"=>"page","title"=>"Résidents & visitors – Ünïcode ✓ 🚲","body"=>["value"=>"<p>It\x27s easy: “quotes”, tabs\tand backslashes \\ here.</p>","format"=>"full_html"],"status"=>1]); $n2->save();
$n3 = Node::create(["type"=>"page","title"=>"Concept beleid","body"=>["value"=>"<p>Nog niet openbaar.</p>","format"=>"basic_html"],"status"=>0]); $n3->save();
$a1 = Node::create(["type"=>"article","title"=>"Wegwerkzaamheden Stationsweg","body"=>["value"=>"<p>Omleiding via de Parklaan.</p>","summary"=>"Afgesloten tot 30 oktober.","format"=>"basic_html"],"status"=>1]); $a1->save();
PathAlias::create(["path"=>"/node/".$n1->id(),"alias"=>"/afval"])->save(); PathAlias::create(["path"=>"/node/".$n2->id(),"alias"=>"/english"])->save();
PathAlias::create(["path"=>"/node/".$a1->id(),"alias"=>"/nieuws/wegwerkzaamheden-stationsweg"])->save();
$dir = "public://2026-10"; \Drupal::service("file_system")->prepareDirectory($dir, \Drupal\Core\File\FileSystemInterface::CREATE_DIRECTORY);
file_put_contents("sites/default/files/2026-10/kaart.pdf", "%PDF-1.4 test"); File::create(["uri"=>"public://2026-10/kaart.pdf","filename"=>"kaart.pdf","status"=>1])->save();
$u = User::create(["name"=>"redacteur","mail"=>"editor@example.org","status"=>1]); $u->addRole("content_editor"); $u->save();
echo "NIDS ", $n1->id(), " ", $n2->id(), " ", $n3->id(), " ", $a1->id(), "\n";' > "$WORK/drupal-seed.log" 2>&1) && ok "content, aliases, a managed file and users seeded" || { fail "seed"; cat "$WORK/drupal-seed.log"; }
read -r _ N1 N2 N3 _ < <(grep NIDS "$WORK/drupal-seed.log")

section "Phase 1: the inventory script, from the project root"
inv=$(inventory_script); out=$(cd "$D" && bash "$inv" 2>/dev/null)
assert_contains "detects Drupal from the Composer root" "$out" "Detected: \*\*Drupal\*\*"
assert_contains "reports the web root" "$out" "Web root: \`web/\`"
assert_contains "lists contrib or custom module directories or says where they go" "$out" "modules/custom"

section "the tables and columns the notes name"
assert_eq "node__body has body_format and body_summary" "$(rosql drupal "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='drupal' AND table_name='node__body' AND column_name IN ('entity_id','body_value','body_format','body_summary')")" "4"
assert_eq "path_alias has path, alias, langcode" "$(rosql drupal "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='drupal' AND table_name='path_alias' AND column_name IN ('path','alias','langcode')")" "3"
assert_eq "user__roles has roles_target_id" "$(rosql drupal "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='drupal' AND table_name='user__roles' AND column_name='roles_target_id'")" "1"
assert_eq "file_managed uri uses public://" "$(rosql drupal "SELECT uri FROM file_managed LIMIT 1")" "public://2026-10/kaart.pdf"
assert_contains "drush sql:query with the documented flags keeps Unicode" "$(cd "$D" && $DR sql:query --extra="--default-character-set=utf8mb4 --batch --raw" "SELECT title FROM node_field_data WHERE nid=$N2" 2>/dev/null)" "Ünïcode ✓ 🚲"

section "export with the skill's Drupal script (drush php:script)"
mkdir -p "$D/dr-export/export"; section_block "$SKILL/references/frameworks.md" "## Drupal 8 and later" php "$D/dr-export/export.php"
(cd "$D/dr-export" && ../vendor/bin/drush php:script export.php > "$WORK/dr-export.log" 2>&1) && ok "export script ran" || { fail "export script"; tail -5 "$WORK/dr-export.log"; }
python3 - "$D/dr-export/export" <<'PY' > "$WORK/dr-export-check.txt"
import json, sys
ex = sys.argv[1]; pages = {r["slug"]: r for r in map(json.loads, open(f"{ex}/pages.jsonl"))}
print("unpublished node excluded:", "concept-beleid" not in pages and len(pages) == 2)
print("alias used as slug:", "afval" in pages and "english" in pages)
print("unicode intact:", pages["english"]["title"] == "Résidents & visitors – Ünïcode ✓ 🚲")
print("body processed without theme wrappers:", pages["afval"]["bodyHtml"].startswith("<h2>") and "field--name-body" not in pages["afval"]["bodyHtml"])
users = [json.loads(l) for l in open(f"{ex}/users.jsonl")]
print("roles mapped to the backend variant:", {u["role"] for u in users} <= {"administrator", "editor", "author", "contributor", "subscriber"})
print("alias map written:", open(f"{ex}/node-aliases.tsv").read().count("\n") == 3)
PY
while IFS=: read -r name val; do assert_eq "$name" "$(printf '%s' "$val" | tr -d ' ')" "True"; done < "$WORK/dr-export-check.txt"

section "convert, deploy the documented backend, import, reconcile"
P="$WORK/drupal-backend"; project_from_docs "$P"; mkdir -p "$P/export"; cp "$D"/dr-export/export/*.jsonl "$P/export/"; convert_exports "$P"
(cd "$P" && timeout 600 mops install >/dev/null 2>&1); net_start "$P" && deploy "$P" backend && ok "backend deployed" || fail "deploy"
import_all "$P" "$P/batches" > "$WORK/dr-import.log"; assert_missing "every batch imported" "$(cat "$WORK/dr-import.log")" "err"
c=$(counts "$P")
assert_eq "pages reconcile" "$(count_of "$c" pages)" "$(rosql drupal "SELECT COUNT(*) FROM node_field_data WHERE type='page' AND status=1")"
assert_eq "articles reconcile" "$(count_of "$c" news)" "$(rosql drupal "SELECT COUNT(*) FROM node_field_data WHERE type='article' AND status=1")"
assert_eq "users reconcile" "$(count_of "$c" legacyUsers)" "$(rosql drupal "SELECT COUNT(*) FROM users_field_data WHERE uid>0")"

section "frontend: alias paths, /node/<nid> redirects, managed files"
rm -rf "$P/dist"; build_pages "$P/dist" "$P/export" file >/dev/null
python3 - "$P/dist" "$D/dr-export/export" <<'PY'
import json, sys, pathlib
d, ex = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
published = {json.loads(l)["legacyId"] for f in ("pages.jsonl", "news.jsonl") for l in open(ex / f)}
rules = [f"{p}  {a}  301" for p, a in (l.rstrip("\n").split("\t") for l in open(ex / "node-aliases.tsv")) if int(p.rsplit("/", 1)[1]) in published]
(d / "_redirects").write_text("\n".join(rules) + "\n")
PY
mkdir -p "$P/dist/sites/default/files/2026-10" && cp "$D/web/sites/default/files/2026-10/kaart.pdf" "$P/dist/sites/default/files/2026-10/"
deploy "$P" frontend && ok "frontend deployed" || fail "frontend deploy"
G=$(cd "$P" && icp network status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('gateway_url') or d.get('api_url'))" | sed 's#/$##'); F="http://frontend.local.localhost:${G##*:}"
assert_http "/afval serves" "$F/afval" 200
assert_eq "/node/$N1 redirects to its alias" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$F/node/$N1")" "301 $F/afval"
assert_http "nested alias serves" "$F/nieuws/wegwerkzaamheden-stationsweg" 200
assert_http "unpublished node is a 404" "$F/node/$N3" 404
assert_http "managed file at its old path" "$F/sites/default/files/2026-10/kaart.pdf" 200
assert_http "user/login is gone" "$F/user/login" 404
net_stop "$P"; summary
