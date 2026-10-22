#!/usr/bin/env bash
# The platform notes in references/frameworks.md, checked against fresh installs: Joomla (CLI install on a database),
# Laravel, Symfony and CodeIgniter (composer), and Magento 2.4's own db_schema.xml files (Magento cannot be installed here).
# Needs: php (with sqlite3, mysql, xml, mbstring, curl, zip, gd, intl), composer, a MariaDB/MySQL server, python3, curl.
source "$(dirname "$0")/lib.sh"
need php composer mysql mysqladmin python3 curl
inv=$(inventory_script)
cols() { rosql "$1" "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='$1' AND table_name='$2' AND column_name IN ($3)"; }

section "Joomla (latest release, CLI installer)"
db_start && db_create joomla >/dev/null
J="$WORK/joomla"; rm -rf "$J" && mkdir -p "$J" && cd "$J" || exit 1
TAG=$(curl -sI https://github.com/joomla/joomla-cms/releases/latest | grep -i '^location:' | sed 's#.*/tag/##' | tr -d '\r\n')
curl -sfL "https://github.com/joomla/joomla-cms/releases/download/$TAG/Joomla_$TAG-Stable-Full_Package.zip" -o joomla.zip && unzip -q joomla.zip && rm joomla.zip && ok "Joomla $TAG unpacked" || fail "Joomla download"
timeout 300 php installation/joomla.php install --site-name="Test" --admin-user="Admin" --admin-username=admin --admin-password="admin-pass-1234" --admin-email=admin@example.org --db-type=mysqli --db-host=127.0.0.1 --db-user=joomla --db-pass=joomla-pass --db-name=joomla --db-prefix=j5_ --db-encryption=0 --no-interaction > "$WORK/joomla-install.log" 2>&1 && ok "Joomla installed" || { fail "Joomla install"; tail -3 "$WORK/joomla-install.log"; }
assert_contains "inventory detects Joomla" "$(bash "$inv" 2>/dev/null)" "Detected: \*\*Joomla\*\*"
assert_eq "#__content columns" "$(cols joomla j5_content "'id','title','alias','introtext','fulltext','state','catid','publish_up','modified'")" "9"
assert_eq "#__categories alias and path" "$(cols joomla j5_categories "'alias','path'")" "2"
assert_eq "#__menu path and link" "$(cols joomla j5_menu "'path','link'")" "2"
assert_eq "#__redirect_links old_url, new_url, header" "$(cols joomla j5_redirect_links "'old_url','new_url','header'")" "3"
assert_eq "#__users name, username, email, password" "$(cols joomla j5_users "'name','username','email','password'")" "4"
[ -d images ] && ok "images/ exists" || fail "images/ missing"
assert_contains "configuration.php has \$sef and \$sef_rewrite" "$(grep -c -E '\$(sef|sef_rewrite) ' configuration.php)" "2"
mysql -u joomla -pjoomla-pass --default-character-set=latin1 joomla -e "INSERT INTO j5_content (asset_id,title,alias,introtext,\`fulltext\`,state,catid,created,created_by,modified,modified_by,publish_up,images,urls,attribs,version,ordering,metakey,metadesc,access,hits,metadata,featured,language,note) VALUES (0,'Résidents – Ünïcode ✓','enc',' ','',1,2,NOW(),42,NOW(),42,NOW(),'{}','{}','{}',1,1,'','',1,0,'{}',0,'*','')" 2>/dev/null   # deliberately misinterpret the UTF-8 fixture bytes as latin1, independently of client defaults
assert_contains "fixture really contains double-encoded text before repair" "$(rosql joomla "SELECT title FROM j5_content WHERE alias='enc'")" "RÃ©sidents"
assert_contains "the documented repair restores double-encoded text" "$(rosql joomla "SELECT CONVERT(CAST(CONVERT(title USING latin1) AS BINARY) USING utf8mb4) FROM j5_content WHERE alias='enc'")" "Résidents – Ünïcode ✓"

section "Laravel, Symfony, CodeIgniter (composer create-project)"
cd "$WORK" && rm -rf laravel symfony ci4
timeout 900 composer create-project laravel/laravel laravel --quiet 2>"$WORK/c-laravel.log" && ok "Laravel $(cd laravel && php artisan --version | grep -o '[0-9.]*$')" || fail "Laravel install"
(cd laravel && echo "Route::get('/nieuws/{slug}', fn (string \$slug) => \$slug);" >> routes/web.php && printf "\nuse Illuminate\\\\Support\\\\Facades\\\\Schedule;\nSchedule::command('inspire')->daily();\n" >> routes/console.php && touch database/database.sqlite && php artisan migrate --force --quiet >/dev/null 2>&1 || true)
assert_contains "artisan route:list --json lists routes" "$(cd laravel && php artisan route:list --json 2>/dev/null)" "{slug}"
assert_contains "artisan schedule:list works with a database" "$(cd laravel && php artisan schedule:list 2>/dev/null)" "inspire"
assert_contains "users migration has a password column" "$(cat laravel/database/migrations/*users*)" "password"
[ -d laravel/storage/app/public ] && ok "storage/app/public exists" || fail "laravel storage path"
assert_contains "inventory detects Laravel" "$(cd laravel && bash "$inv" 2>/dev/null)" "Detected: \*\*Laravel\*\*"
timeout 900 composer create-project symfony/skeleton symfony --quiet 2>"$WORK/c-symfony.log" && (cd symfony && timeout 600 composer require symfony/twig-bundle symfony/orm-pack --quiet 2>>"$WORK/c-symfony.log") && ok "Symfony $(cd symfony && php bin/console --version | grep -o 'v[0-9.]*' | head -1)" || fail "Symfony install"
mkdir -p symfony/src/Controller && cat > symfony/src/Controller/NewsController.php <<'EOF'
<?php
namespace App\Controller;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;
class NewsController extends AbstractController { #[Route('/nieuws/{slug}', name: 'news_show')] public function show(string $slug): Response { return new Response($slug); } }
EOF
assert_contains "console debug:router --format=json lists routes" "$(cd symfony && php bin/console debug:router --format=json 2>/dev/null)" "news_show"
for d in config/routes.yaml src/Entity migrations templates; do [ -e "symfony/$d" ] && ok "symfony: $d exists" || fail "symfony: $d missing"; done
assert_contains "inventory detects Symfony" "$(cd symfony && bash "$inv" 2>/dev/null)" "Detected: \*\*Symfony\*\*"
timeout 900 composer create-project codeigniter4/appstarter ci4 --quiet 2>"$WORK/c-ci4.log" && ok "CodeIgniter $(cd ci4 && php spark --version 2>/dev/null | grep -o 'v[0-9.]*' | head -1)" || fail "CodeIgniter install"
assert_contains "spark routes lists routes" "$(cd ci4 && php spark routes 2>/dev/null)" "GET"
for d in app/Config/Routes.php app/Database/Migrations app/Models app/Views env; do [ -e "ci4/$d" ] && ok "ci4: $d exists" || fail "ci4: $d missing"; done
assert_contains "inventory detects CodeIgniter" "$(cd ci4 && bash "$inv" 2>/dev/null)" "Detected: \*\*CodeIgniter\*\*"

section "Magento 2.4 (table and column names against its db_schema.xml)"
M="$WORK/magento-schema"; mkdir -p "$M"
for mod in Catalog UrlRewrite Customer Sales Eav Cron; do curl -sfL "https://raw.githubusercontent.com/magento/magento2/2.4-develop/app/code/Magento/$mod/etc/db_schema.xml" -o "$M/$mod.xml" || fail "fetch $mod schema"; done
python3 - "$M" <<'PY' > "$WORK/magento-check.txt"
import re, glob, sys
schema = "".join(open(f).read() for f in glob.glob(sys.argv[1] + "/*.xml"))
tables = {m.group(1): set(re.findall(r'<column[^>]*name="([^"]+)"', m.group(2))) for m in re.finditer(r'<table name="([^"]+)"[^>]*>(.*?)</table>', schema, re.S)}
claims = {"catalog_product_entity": ["entity_id", "sku"], "catalog_product_entity_varchar": ["attribute_id", "store_id", "value"], "eav_attribute": ["attribute_id", "attribute_code"],
          "url_rewrite": ["request_path", "target_path", "redirect_type", "entity_type", "entity_id", "store_id"], "customer_entity": ["password_hash", "email"],
          "sales_order": ["entity_id"], "sales_order_item": ["order_id", "sku"], "cron_schedule": ["job_code"]}
for t, cols in claims.items(): print(f"{t}:{'True' if t in tables and all(c in tables[t] for c in cols) else 'False'}")
PY
while IFS=: read -r name val; do assert_eq "magento $name" "$val" "True"; done < "$WORK/magento-check.txt"
summary
