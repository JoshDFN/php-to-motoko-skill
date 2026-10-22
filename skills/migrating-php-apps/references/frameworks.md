# Platform Notes

Where each platform keeps content, users, URLs, files and schedules, and the traps specific to it. Table and column names below are the platform defaults; confirm them against the actual install (prefixes, versions and plugins change them) before writing export queries.

## Contents

- [WordPress](#wordpress)
- [Drupal 8 and later](#drupal-8-and-later)
- [Joomla 4 and 5](#joomla-4-and-5)
- [Magento 2](#magento-2)
- [Laravel](#laravel)
- [Symfony](#symfony)
- [CodeIgniter 4](#codeigniter-4)
- [Plain PHP](#plain-php)

## WordPress

Checked on WordPress 7.1 with a full migration (see `SKILL.md`, Phase 4 and 6).

- **Prefix:** `$table_prefix` in `wp-config.php` (default `wp_`). Use the real prefix in every query.
- **Content:** `wp_posts`. Filter `post_type IN ('post', 'page')` (plus any custom types the site uses) and `post_status = 'publish'`; `post_name` is the slug, `post_date_gmt` / `post_modified_gmt` are UTC. Rows with `post_type = 'revision'`, `'attachment'` or `'nav_menu_item'` are not pages.
- **Rendered HTML:** `post_content` holds block comments (`<!-- wp:paragraph -->`) and shortcodes (`[gallery ids="1,2"]`) that only WordPress can expand. Export the rendered HTML with WordPress itself while the old site still runs. This script, run with `wp eval-file export.php` at the WordPress root, writes JSON lines ready for the converter in `data-import.md` (tested on WordPress 7.1):

  ```php
  <?php
  // Run at the WordPress root: wp eval-file export.php   (writes export/*.jsonl next to it)
  $opts = JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES;
  is_dir('export') || mkdir('export');
  $render = function ($p) {
    if (class_exists('\Elementor\Plugin') && get_post_meta($p->ID, '_elementor_edit_mode', true) === 'builder') {
      return \Elementor\Plugin::$instance->frontend->get_builder_content_for_display($p->ID, true);   // page builders bypass the_content
    }
    return apply_filters('the_content', $p->post_content);
  };
  $extras = function ($p) {   // plugin data that belongs to the page; each key is a decision in the feature map
    $x = [];
    if (function_exists('pll_get_post_language')) { $x['language'] = pll_get_post_language($p->ID); $x['translations'] = pll_get_post_translations($p->ID); }
    if (function_exists('get_fields')) { $x['fields'] = get_fields($p->ID) ?: null; }                 // Advanced Custom Fields, structured
    $x['seoTitle'] = get_post_meta($p->ID, '_yoast_wpseo_title', true) ?: null;                        // Yoast SEO
    $x['seoDescription'] = get_post_meta($p->ID, '_yoast_wpseo_metadesc', true) ?: null;
    return array_filter($x, fn($v) => $v !== null && $v !== '' && $v !== false && $v !== []);
  };
  $pages = fopen('export/pages.jsonl', 'w');
  foreach (get_posts(['post_type' => 'page', 'post_status' => 'publish', 'numberposts' => -1, 'orderby' => 'ID', 'order' => 'ASC']) as $p) {
    fwrite($pages, json_encode(['legacyId' => $p->ID, 'slug' => $p->post_name, 'title' => $p->post_title, 'bodyHtml' => $render($p),
      'published' => true, 'updatedAt' => strtotime($p->post_modified_gmt . ' UTC')] + $extras($p), $opts) . "\n");
  }
  $news = fopen('export/news.jsonl', 'w');
  foreach (get_posts(['post_type' => 'post', 'post_status' => 'publish', 'numberposts' => -1, 'orderby' => 'ID', 'order' => 'ASC']) as $p) {
    fwrite($news, json_encode(['legacyId' => $p->ID, 'slug' => $p->post_name, 'title' => $p->post_title,
      'summary' => $p->post_excerpt !== '' ? $p->post_excerpt : null, 'bodyHtml' => $render($p),
      'publishedAt' => strtotime($p->post_date_gmt . ' UTC'), 'authorLegacyId' => (int) $p->post_author] + $extras($p), $opts) . "\n");
  }
  $users = fopen('export/users.jsonl', 'w');   // identity data only: never user_pass
  foreach (get_users(['orderby' => 'ID']) as $u) {
    fwrite($users, json_encode(['legacyId' => $u->ID, 'email' => strtolower(trim($u->user_email)),
      'displayName' => $u->display_name, 'role' => $u->roles[0]], $opts) . "\n");
  }
  ```

  The converter ignores keys it is not given, so the extra keys (`language`, `translations`, `fields`, `seoTitle`, `seoDescription`) are available for the pages that need them without changing the backend types. After the export, check two things: shortcodes whose plugin is inactive stay as literal text (`grep -oh '\[[a-z0-9_-]*' export/*.jsonl | sort | uniq -c`), and rendered markup that still depends on PHP (`grep -o -E '<form|wpcf7|data-block-name|woocommerce|admin-ajax|wp-json' export/*.jsonl | sort | uniq -c`): a contact form renders as a `<form>` that posts to WordPress's own API, and shop pages render block markup that WordPress's JavaScript fills in. Each hit is a feature-map row, not content.
- **Metadata and options:** `wp_postmeta` and `wp_options` often hold serialized PHP (`a:2:{s:3:"foo";...}`). Inside WordPress, `get_post_meta()` already decodes it safely (the export script above can include it). From a raw database value, decode with the PHP CLI, refusing to instantiate objects: `php -r 'echo json_encode(unserialize(trim(stream_get_contents(STDIN)), ["allowed_classes" => false]));'` (the `trim` removes the newline the `mysql` client adds, which otherwise triggers a warning).
- **Taxonomies:** `wp_terms`, `wp_term_taxonomy`, `wp_term_relationships`.
- **Users:** `wp_users` (`user_email`, `display_name`; never `user_pass`) and roles in `wp_usermeta` under `<prefix>capabilities` (serialized); the export script above reads them through WordPress. The roles are `administrator`, `editor`, `author`, `contributor` and `subscriber`: make the backend's `role` variant match (see `backend-example.md`).
- **URLs:** the `permalink_structure` option (for example `/%postname%/` or `/%year%/%monthnum%/%postname%/`). Pretty permalinks end with a slash, so build each page as a directory index: `dist/afval/index.html` is served at `/afval/`, and the static-site canister redirects `/afval` to `/afval/` by itself (tested). Nest directories for date-based structures. Links in the form `/?p=123` and `/?page_id=5` keep working on sites with pretty permalinks too; they land on `/`, so the mapping script must run in the home page (`old-urls.md`).
- **Files:** `wp-content/uploads/YYYY/MM/`, including generated thumbnail sizes. Copy the ones still referenced into the static-site `dir` at the same paths so old image URLs keep working.
- **Schedules:** WP-Cron (`wp cron event list`), triggered by page visits rather than the system cron.
- **Plugins:** every active plugin (`wp plugin list --status=active`) is a feature-map row: rebuild, replace or drop with the owner's consent. Where the common ones keep their data (checked on WordPress 7.1):
  - *Contact Form 7:* forms are posts of type `wpcf7_contact_form` (fields in postmeta `_form`, recipients in `_mail`); the rendered `<form>` posts to `wp-json/contact-form-7`. Becomes a backend update method plus a page form; decide who receives the mail (`https-outcalls`).
  - *Yoast SEO:* per-page title and description in postmeta `_yoast_wpseo_title` and `_yoast_wpseo_metadesc` (exported above); canonical and social data in `wp_yoast_indexable`. Becomes `<title>` and `<meta>` tags in the built pages.
  - *Advanced Custom Fields:* values in postmeta under the field name (repeaters as `name_0_sub`, `name_1_sub`, ...) with a `_name` key reference beside each; `get_fields()` returns them structured (exported above) when the field groups are in the database or theme code. Each field becomes a record field.
  - *Elementor and other page builders:* `post_content` is empty and the page is JSON in `_elementor_data`; `apply_filters('the_content')` renders nothing from the command line. Render through the builder's API (the script does this for Elementor) or fetch the page over HTTP from the running site. The result carries inline styles and the builder's CSS classes; keep its stylesheet or restyle.
  - *WooCommerce:* products are posts of type `product` with postmeta `_price`, `_sku`, `_stock_status` and the `wc_product_meta_lookup` table; orders in the `wc_orders*` tables (or posts of type `shop_order` on older sites); customers are users. The shop, cart, checkout and account pages export empty or as JavaScript-dependent markup. Catalog and content can move; checkout, payments, tax and stock are the owner decision under Magento's heading below.
  - *Polylang and WPML:* one post per language, linked by the `post_translations` taxonomy (Polylang) or the `icl_translations` table (WPML). Export the language and the links (the script does this for Polylang) and build one page per language at its own path.
  - *Wordfence, Akismet, caching and backup plugins:* operational, with their own tables; nothing to migrate. The attack surface they guard is gone.

## Drupal 8 and later

- **Layout:** Composer sites keep the web root in `web/` (or `docroot/`); the project root holds `composer.json`, `vendor/` and `config/`. The inventory script reports the web root. Run `drush` from the project root.
- **Content:** `node_field_data` (`nid`, `type`, `langcode`, `title`, `status`, `created`, `changed` as Unix seconds); bodies in `node__body` (`entity_id`, `body_value`, `body_summary`, `body_format`); other fields in `node__field_<name>` tables. Multilingual sites have one row per `langcode`.
- **Text formats:** `body_format` (`basic_html`, `full_html`, ...) decides which filters run on output. Export the filtered HTML through Drupal instead of the raw `body_value`: `$node->body->processed` applies the format's filters without theme wrappers. This script writes JSON lines ready for the converter in `data-import.md`; run it from the project root with `drush php:script export.php` (tested on Drupal 11.4; Drush changes the working directory, so the script addresses its output through `__DIR__`):

  ```php
  <?php
  $opts = JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES;
  $storage = \Drupal::entityTypeManager()->getStorage('node'); $aliases = \Drupal::service('path_alias.manager');
  $slug = fn($node) => ltrim($aliases->getAliasByPath('/node/' . $node->id()), '/');   // the alias, or node/<nid>
  $pages = fopen(__DIR__ . '/export/pages.jsonl', 'w');
  foreach ($storage->loadByProperties(['type' => 'page', 'status' => 1]) as $n) {
    fwrite($pages, json_encode(['legacyId' => (int) $n->id(), 'slug' => $slug($n), 'title' => $n->getTitle(),
      'bodyHtml' => trim((string) $n->body->processed), 'published' => true, 'updatedAt' => (int) $n->getChangedTime()], $opts) . "\n");
  }
  $news = fopen(__DIR__ . '/export/news.jsonl', 'w');
  foreach ($storage->loadByProperties(['type' => 'article', 'status' => 1]) as $n) {
    fwrite($news, json_encode(['legacyId' => (int) $n->id(), 'slug' => $slug($n), 'title' => $n->getTitle(), 'summary' => $n->body->summary ?: null,
      'bodyHtml' => trim((string) $n->body->processed), 'publishedAt' => (int) $n->getCreatedTime(), 'authorLegacyId' => (int) $n->getOwnerId()], $opts) . "\n");
  }
  $roles = ['administrator' => 'administrator', 'content_editor' => 'editor'];   // map the site's roles to the backend variant
  $users = fopen(__DIR__ . '/export/users.jsonl', 'w');                           // identity data only: never pass
  foreach (\Drupal::entityTypeManager()->getStorage('user')->loadMultiple() as $u) {
    if ($u->id() == 0) continue;
    $r = array_values(array_diff($u->getRoles(), ['authenticated']))[0] ?? 'subscriber';
    fwrite($users, json_encode(['legacyId' => (int) $u->id(), 'email' => strtolower(trim((string) $u->getEmail())), 'displayName' => $u->getDisplayName(), 'role' => $roles[$r] ?? 'subscriber'], $opts) . "\n");
  }
  $map = fopen(__DIR__ . '/export/node-aliases.tsv', 'w');                        // for the /node/<nid> redirect rules
  foreach (\Drupal::database()->query('SELECT path, alias FROM {path_alias}') as $row) fwrite($map, "$row->path\t$row->alias\n");
  ```

- **Raw SQL exports:** `drush sql:query` runs the `mysql` client without a character set, which turns emoji and some punctuation into `?`. Pass the client flags: `drush sql:query --extra="--default-character-set=utf8mb4 --batch --raw" "SELECT ..."`, or run the client yourself with the credentials from `drush sql:connect`.
- **URLs:** `path_alias` (`path` such as `/node/123`, `alias` such as `/about-us`, `langcode`, often `und`). Drupal URLs have no trailing slash: build `dist/about-us.html`, served at `/about-us`. Generate exact `_redirects` rules for `/node/<nid>` from the alias table (tested: `/node/16  /afval  301`), because those links circulate in emails and documents.
- **Users:** `users_field_data` (`uid`, `name`, `mail`; never `pass`); roles in `user__roles` (`entity_id`, `roles_target_id`). Every account also has the implicit `authenticated` role.
- **Files:** `file_managed` (`uri` such as `public://2026-10/report.pdf`) maps to `<web root>/sites/default/files/2026-10/report.pdf`. Copy only the files `file_managed` lists, never the whole directory: it also holds `config_<hash>/sync` (the site's configuration, with any secrets in it), `php/` (compiled templates) and aggregated `css/` and `js/`.
- **Tools:** `drush php:script` for exports through Drupal, `drush sql:query` for raw SQL (with the flags above), `drush cron` for scheduled work.

## Joomla 4 to 6

Table and column names below were checked on Joomla 6.2.

- **Prefix:** `$dbprefix` in `configuration.php` (often random, such as `abc12_`); the queries below write it as `#__`. Always pass `--default-character-set=utf8mb4` to the `mysql` client: a table filled through a client with the wrong character set holds double-encoded text (`RÃ©sidents` for `Résidents`), which the repair expression in `data-import.md` restores (tested on such a row).
- **Content:** `#__content` (`id`, `title`, `alias`, `introtext`, `fulltext`, `state` where 1 is published, `catid`, `publish_up`, `modified`); categories in `#__categories` (`alias`, `path`).
- **URLs:** `$sef` and `$sef_rewrite` in `configuration.php`. Search-engine-friendly URLs come from `#__menu` (`path`, and `link` such as `index.php?option=com_content&view=article&id=5`) combined with article aliases. With `$sef_rewrite` off (the default), every public URL starts with `/index.php/`: keep those paths working with exact `_redirects` rules from `/index.php/<path>` to the new path. Non-SEF URLs are query strings on `/index.php` (mapping page). `#__redirect_links` (`old_url`, `new_url`, `header` with the status code) holds the site's existing redirects; carry them over as rules.
- **Users:** `#__users` (`name`, `username`, `email`; never `password`).
- **Files:** `images/` by default.

## Magento 2

Table and column names below were checked against Magento 2.4's schema definitions.

- **Products are EAV:** `catalog_product_entity` (`entity_id`, `sku`) with values spread over `catalog_product_entity_varchar`, `_int`, `_decimal`, `_text`, `_datetime`, keyed by `attribute_id` (names in `eav_attribute`) and `store_id`. Flatten per store view during export.
- **URLs:** `url_rewrite` (`request_path`, `target_path`, `redirect_type`, `entity_type`, `entity_id`, `store_id`) is the complete URL map: build pages at `request_path` and turn rows whose `redirect_type` is `301` or `302` into `_redirects` rules (`0` means a plain rewrite, a page to build).
- **Customers and orders:** `customer_entity` (never `password_hash`), `sales_order`, `sales_order_item`.
- **Commerce is the hard part:** checkout, payments, tax, stock reservations and card-data rules (PCI DSS) need a decision with the owner before any build. A common split is catalog and content on ICP with checkout through an external payment provider; record whichever is chosen in the feature map.
- **Files:** `pub/media/catalog/product/`.
- **Schedules:** `bin/magento cron:run`, with jobs declared in each module's `crontab.xml`.

## Laravel

Checked on Laravel 13.

- **Routes:** `routes/web.php`, `routes/api.php`; list them with `php artisan route:list --json`.
- **Schema:** `database/migrations/` is the most reliable description of the tables; models in `app/Models/`.
- **Views:** Blade templates in `resources/views/` become frontend components or pre-rendered pages.
- **Auth:** the `users` table holds bcrypt hashes (not imported); Sanctum or Passport tokens do not carry over.
- **Schedules and queues:** `php artisan schedule:list` (defined in `app/Console/Kernel.php` up to Laravel 10, `routes/console.php` from Laravel 11). The command needs the app's database connection, because the scheduler reads its cache store, so run it in the app's own environment. Queued jobs (`jobs` table or Redis) become timers or direct calls.
- **Files:** `storage/app/public/` (served through the `public/storage` link).
- **Secrets:** `.env` names only.

## Symfony

Checked on Symfony 7.4.

- **Routes:** `php bin/console debug:router --format=json`; definitions in `config/routes*` and `#[Route]` attributes on controllers.
- **Schema:** Doctrine entities in `src/Entity/`, migrations in `migrations/`.
- **Views:** Twig templates in `templates/`.
- **Background work:** Messenger handlers and the Scheduler component become timers or direct calls.

## CodeIgniter 4

Checked on CodeIgniter 4.7.

- **Routes:** `app/Config/Routes.php`; list them with `php spark routes`.
- **Schema:** `app/Database/Migrations/`; models in `app/Models/`; views in `app/Views/`; secrets in `.env` (the starter ships a template named `env`, without the dot; the site's real values are in `.env`).

## Plain PHP

- `.htaccess` (or the nginx `location` blocks) is the URL map; every rewrite rule is an old-URL test.
- Follow the `include`/`require` graph from each entry file: shared headers, database helpers and global state often hide there.
- SQL embedded in templates is common. Collect every query (`grep -rn -E "SELECT|INSERT|UPDATE|DELETE" --include=*.php`) and give each one a backend method or a reason to drop it.
