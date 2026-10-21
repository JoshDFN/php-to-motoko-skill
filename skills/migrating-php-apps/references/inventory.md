# PHP Inventory Script

Read-only. Run it at the root of the PHP project (or pass the path) and keep the output with the migration notes. It never prints secret values: for configuration files it lists constant and key **names** only.

```bash
bash php-inventory.sh /path/to/php-site > inventory.md
```

Requires `bash`, `find`, `grep`, `du`, `awk`; `python3` for the Composer summary. The helper scans PHP source extensions, including Drupal `.module`, `.theme`, `.install`, `.profile` and `.engine` files. It lists installed extensions without executing CMS code; the CLI commands it prints are follow-up suggestions only. Tested on synthetic plain-PHP, Composer Drupal and WordPress fixtures, including paths containing spaces and dummy configuration secrets.

```bash
#!/usr/bin/env bash
# Inventory a PHP codebase before moving it to the Internet Computer.
# Read-only. Prints Markdown. Never prints secret values, only file and key names.
# Usage: bash php-inventory.sh [path-to-php-repo] > inventory.md
set -u
ROOT="${1:-.}"
cd "$ROOT" || exit 1
PRUNE=(-path ./vendor -prune -o -path ./node_modules -prune -o -path ./.git -prune -o)

# NUL-delimited paths keep spaces and shell metacharacters intact; do not eval paths.
files() { find . "${PRUNE[@]}" -type f \( "$@" \) -print0 2>/dev/null; }
php_files() { files -name '*.php' -o -name '*.phtml' -o -name '*.inc' -o -name '*.module' -o -name '*.theme' -o -name '*.install' -o -name '*.profile' -o -name '*.engine'; }
hits() { # $1 = label, $2 = extended regex
  local n f
  n=$(php_files | while IFS= read -r -d '' f; do
    grep -q -E "$2" "$f" 2>/dev/null && printf '1\n'
  done | wc -l | tr -d ' ')
  printf '| %s | %s |\n' "$1" "$n"
}
installed_names() { # $1 = directory; remaining arguments = find predicates
  local dir="$1"
  shift
  find "$dir" -mindepth 1 -maxdepth 1 "$@" -exec basename {} \; 2>/dev/null
}

echo "# PHP inventory: $(basename "$(pwd)")"
echo
echo "## Platform"
fw="plain PHP"; DOCROOT="."
# Composer layouts keep the web root in a subdirectory (Drupal's web/ or docroot/, Bedrock's web/)
for d in . web docroot public_html htdocs; do
  { [ -f "$d/wp-config.php" ] || [ -f "$d/wp-includes/version.php" ]; } && { fw="WordPress"; DOCROOT="$d"; }
  [ -f "$d/core/lib/Drupal.php" ] && { fw="Drupal"; DOCROOT="$d"; }
done
[ -f libraries/src/Version.php ] || [ -f administrator/manifests/files/joomla.xml ] && fw="Joomla"
[ -f bin/magento ] && [ -f app/etc/env.php ] && fw="Magento 2"
[ -f artisan ] && grep -q '"laravel/framework"' composer.json 2>/dev/null && fw="Laravel"
[ -f bin/console ] && grep -q '"symfony/framework-bundle"' composer.json 2>/dev/null && fw="Symfony"
[ -f spark ] || [ -f system/CodeIgniter.php ] && fw="CodeIgniter"
echo "- Detected: **$fw**"
[ "$DOCROOT" != "." ] && echo "- Web root: \`$DOCROOT/\` (Composer layout: the project root holds composer.json, vendor/ and config outside the web root)"
R="."; [ "$DOCROOT" != "." ] && R="./$DOCROOT"
# Skip the platform's own code: it is replaced, not migrated. Your code lives in the custom directories.
CORE=(); CUSTOM=''; ROOTSKIP='^$'
case "$fw" in
  WordPress) CORE=(-path "$R/wp-admin" -prune -o -path "$R/wp-includes" -prune -o); CUSTOM="$DOCROOT/wp-content/themes, $DOCROOT/wp-content/plugins, $DOCROOT/wp-content/mu-plugins"; ROOTSKIP="^$R/(wp-[a-z-]+|xmlrpc|index)\\.php\$" ;;
  Drupal) CORE=(-path "$R/core" -prune -o); CUSTOM="$DOCROOT/modules/custom, $DOCROOT/themes/custom, $DOCROOT/sites/*/modules; files under $DOCROOT/sites/default/files" ;;
  Joomla) CORE=(-path ./libraries -prune -o -path ./installation -prune -o); CUSTOM='templates, plugins, components and administrator/components (your own extensions)' ;;
  "Magento 2") CORE=(-path ./lib -prune -o -path ./setup -prune -o -path ./generated -prune -o -path ./dev -prune -o); CUSTOM='app/code, app/design' ;;
esac
# Bash 3.2 with nounset rejects expansion of an empty array.
if [ -n "${CORE[0]-}" ]; then PRUNE+=("${CORE[@]}"); fi
[ -n "$CUSTOM" ] && echo "- Platform core directories are skipped below. Custom code to inventory: $CUSTOM"
# Extensions: every one is a feature-map row (rebuild, replace or drop with consent). Active state needs the platform's CLI.
case "$fw" in
  WordPress)
    for d in plugins mu-plugins themes; do
      [ -d "$DOCROOT/wp-content/$d" ] && echo "- Installed $d: $(installed_names "$DOCROOT/wp-content/$d" \( -type d -o -name '*.php' \) ! -name index.php)"
    done
    echo "  Inspect separately: \`wp plugin list --status=active\`, then repeat with \`active-network\`, \`must-use\` and \`dropin\`; \`wp theme list --status=active\`. For multisite, repeat for each in-scope site with \`--url=<site-url>\`." ;;
  Drupal)
    for d in modules/contrib modules/custom themes/contrib themes/custom; do
      [ -d "$DOCROOT/$d" ] && echo "- Installed $d: $(installed_names "$DOCROOT/$d" -type d)"
    done
    echo "  Enabled ones: \`drush pm:list --status=enabled --type=module\`" ;;
  Joomla)
    echo "- Installed extensions: \`php cli/joomla.php extension:list\` (components in components/ and administrator/components/, plugins in plugins/)" ;;
esac
echo "- PHP source files (excluding vendor/ and platform core): $(php_files | while IFS= read -r -d '' f; do printf '1\n'; done | wc -l | tr -d ' '), lines: $(php_files | while IFS= read -r -d '' f; do cat "$f" 2>/dev/null; done | wc -l | tr -d ' ')"
if [ -f composer.json ] && command -v python3 >/dev/null; then
  python3 - <<'PY'
import json
c = json.load(open("composer.json"))
req = c.get("require", {})
print("- PHP constraint: " + req.get("php", "(none)"))
deps = [k for k in req if k != "php" and not k.startswith("ext-")]
exts = [k for k in req if k.startswith("ext-")]
print("- Composer packages: " + (", ".join(deps) if deps else "(none)"))
if exts: print("- Required PHP extensions: " + ", ".join(exts))
PY
fi

echo
echo "## Entry points and URLs"
echo "PHP files in the top two levels (likely entry points):"
find . -maxdepth 2 "${PRUNE[@]}" -type f -name '*.php' -print 2>/dev/null | grep -v -E "$ROOTSKIP" | sort | sed 's/^/- /'
files -name .htaccess | while IFS= read -r -d '' f; do
  case "$f" in */wp-content/plugins/*|*/wp-content/themes/*|*/modules/contrib/*|*/vendor/*) continue ;; esac
  echo; echo "Rewrite rules in \`$f\`:"; grep -E '^[[:space:]]*(RewriteRule|Redirect|RedirectMatch)' "$f" | sed 's/^/    /'
done
[ -d routes ] && { echo; echo "Laravel route files:"; ls routes | sed 's/^/- routes\//'; }
[ -d config ] && ls config/routes* >/dev/null 2>&1 && { echo; echo "Symfony route config:"; ls -d config/routes* | sed 's/^/- /'; }

echo
echo "## Features that need a decision"
echo "| Feature (files using it) | Files |"
echo "|---|---|"
hits 'Sessions ($_SESSION, session_start)' '\$_SESSION|session_start\('
hits 'Password logins (password_verify, crypt, md5/sha1 on passwords)' 'password_verify|password_hash|crypt\(|md5\(|sha1\('
hits 'Form posts ($_POST)' '\$_POST'
hits 'Query parameters ($_GET, $_REQUEST)' '\$_GET|\$_REQUEST'
hits 'File uploads ($_FILES, move_uploaded_file)' '\$_FILES|move_uploaded_file'
hits 'Cookies (setcookie, $_COOKIE)' 'setcookie\(|\$_COOKIE'
hits 'Email (mail(), PHPMailer, Swift, Symfony Mailer)' '(^|[^[:alnum:]_])mail\(|PHPMailer|Swift_|Mailer'
hits 'Outbound HTTP (curl, Guzzle, file_get_contents http)' 'curl_init|GuzzleHttp|file_get_contents\(.https?:|fsockopen'
hits 'Shell commands (exec, shell_exec, system, proc_open)' '(^|[^>:a-zA-Z0-9_$])(exec|shell_exec|system|passthru|proc_open|popen)\('
hits 'Image processing (GD, Imagick)' 'imagecreate|Imagick|getimagesize'
hits 'PDF / spreadsheet generation' 'TCPDF|FPDF|Dompdf|Mpdf|PhpSpreadsheet'
hits 'Database access (PDO, mysqli)' 'new PDO|mysqli_|->query\(|->prepare\('
hits 'Redirect headers (header Location)' "header\\(['\"]Location"

echo
echo "## Database"
files -name '*.sql' | while IFS= read -r -d '' f; do
  echo "Tables in \`$f\`:"
  grep -i -o -E 'CREATE TABLE (IF NOT EXISTS )?`?[A-Za-z0-9_]+`?' "$f" | awk '{print $NF}' | tr -d '`' | sed 's/^/- /'
done
[ -d database/migrations ] && echo "- Laravel migrations: $(ls database/migrations | wc -l | tr -d ' ') files in database/migrations"
[ -d src/Entity ] && echo "- Doctrine entities: $(ls src/Entity | wc -l | tr -d ' ') files in src/Entity"
echo "(Get row counts and sizes from the live database: see the skill's export step.)"

echo
echo "## Scheduled jobs"
files -iname '*cron*' -o -name '*.crontab' | while IFS= read -r -d '' f; do echo "- \`$f\`"; done
php_files | while IFS= read -r -d '' f; do
  grep -q -E 'wp_schedule_event|->(daily|hourly|everyMinute|cron)\(|AsCronTask' "$f" 2>/dev/null && printf '%s\n' "- scheduler code: $f"
done

echo
echo "## Files on disk"
for d in uploads wp-content/uploads sites/default/files public/storage storage/app/public pub/media images media files; do
  [ -d "$d" ] && echo "- \`$d\`: $(du -sh "$d" | cut -f1), $(find "$d" -type f | wc -l | tr -d ' ') files"
done

echo
echo "## Configuration and secrets (names only, never values)"
for f in config.php wp-config.php .env .env.local app/etc/env.php sites/default/settings.php configuration.php config/parameters.yml; do
  [ -f "$f" ] || continue
  echo "- \`$f\`:"
  { grep -o -E "define\\(['\"][A-Za-z0-9_]+['\"]" "$f" | sed -E "s/define\\(['\"]//; s/['\"]$//"
    grep -o -E '^[A-Z][A-Z0-9_]*=' "$f" | tr -d '='
    grep -o -E "public \\\$[a-z_]+" "$f" | sed 's/public \$//'
  } 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/^/    /'; echo
done
```

## Reading the output

- **Platform** decides which section of `frameworks.md` to read next.
- **Rewrite rules** are the old URL map. Every rule becomes a row in the feature map and, later, an old-URL test (`old-urls.md`).
- **Features that need a decision** are file counts from text search. They are leads, not proof: open each file. A count of 0 is not a guarantee either (code can be generated, included dynamically or live in `vendor/`).
- **Database**: table names only. Get row counts and sizes from the live database (SKILL.md, Phase 1).
- **Configuration and secrets**: these names tell you which integrations exist (SMTP, payment, API keys). Do not open the values in chat or copy them anywhere.
