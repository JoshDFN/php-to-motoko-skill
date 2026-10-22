# Platform Notes

Where each platform keeps content, users, URLs, files and schedules, and the traps specific to it. Table and column names below are the platform defaults; confirm them against the actual install (prefixes, versions and plugins change them) before writing export queries.

Platform versions and historical checks in these notes are reported by the supplied source author. The scoped exporters below have been revised; component checks do not establish a new end-to-end CMS or plugin migration test. Confirm behavior against the actual installed versions and configuration.

## Contents

- [Scoped export helpers](#scoped-export-helpers)
- [WordPress](#wordpress)
- [Drupal 8 and later](#drupal-8-and-later)
- [Joomla 4 to 6](#joomla-4-to-6)
- [Magento 2](#magento-2)
- [Laravel](#laravel)
- [Symfony](#symfony)
- [CodeIgniter 4](#codeigniter-4)
- [Plain PHP](#plain-php)

## Scoped export helpers

The examples below capture selected content and identity data for review. They are not universal CMS exporters or evidence that plugins, permissions or live workflows have migrated. Run them on an owner-approved copy using the relevant CMS CLI. Rendering invokes installed plugin/module code; inspect that code and its side effects first.

Save this helper as `export-support.php` beside the selected exporter in a private working directory outside the web root. Set `MIGRATION_EXPORT_DIR` to an absolute, **new** directory whose parent already exists on private storage. Set `MIGRATION_WEB_ROOTS` to the absolute roots of every directory published by the web server, separated by `PATH_SEPARATOR` (`:` on Linux/macOS), including upload aliases. At least one root must contain the CMS root. The helper rejects output beneath those roots, creates a fresh directory with mode 0700, and writes files with mode 0600. It cannot discover web-server aliases: confirm the chosen storage is not served by any host. Never deploy this directory as frontend assets.

```php
<?php
function migration_inside(string $path, string $root): bool {
  return $path === $root || str_starts_with($path, rtrim($root, '/') . '/');
}
function migration_export_dir(string $cmsRoot): string {
  $cms = realpath($cmsRoot); $roots = [];
  foreach (explode(PATH_SEPARATOR, getenv('MIGRATION_WEB_ROOTS') ?: '') as $root) {
    $resolved = $root !== '' && $root[0] === '/' ? realpath($root) : false;
    if ($resolved === false || !is_dir($resolved)) throw new RuntimeException('Declare every public root.');
    $roots[] = $resolved;
  }
  if ($cms === false || !array_filter($roots, fn($root) => migration_inside($cms, $root))) {
    throw new RuntimeException('Declared public roots must include the CMS root.');
  }
  $requested = getenv('MIGRATION_EXPORT_DIR') ?: '';
  $parent = $requested !== '' && $requested[0] === '/' ? realpath(dirname($requested)) : false;
  $leaf = basename($requested);
  if ($parent === false || !is_dir($parent) || in_array($leaf, ['', '.', '..'], true)) {
    throw new RuntimeException('Choose a new absolute private output directory with an existing parent.');
  }
  $dir = rtrim($parent, '/') . '/' . $leaf;
  foreach ($roots as $root) if (migration_inside($dir, $root)) throw new RuntimeException('Output is public.');
  umask(0077);
  if (file_exists($dir) || is_link($dir) || !mkdir($dir, 0700)) throw new RuntimeException('Use a fresh private directory.');
  return $dir;
}
function migration_ids(string $name, bool $required = true): array {
  $raw = getenv($name) ?: '';
  if ($raw === '' && !$required) return [];
  if (!preg_match('/^[1-9][0-9]*(,[1-9][0-9]*)*$/D', $raw)) throw new RuntimeException("Set $name to approved numeric IDs.");
  return array_values(array_unique(array_map('intval', explode(',', $raw))));
}
function migration_route(string $url): string {
  $parts = parse_url($url);
  if (!is_array($parts) || empty($parts['host'])) throw new RuntimeException('Missing absolute source URL.');
  return ($parts['path'] ?? '/') . (isset($parts['query']) ? '?' . $parts['query'] : '');
}
function migration_jsonl(string $path, iterable $rows): void {
  $partial = $path . '.partial'; $handle = fopen($partial, 'xb');
  if ($handle === false) throw new RuntimeException('Cannot create private export.');
  try {
    foreach ($rows as $row) {
      $line = json_encode($row, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
      for ($offset = 0; $offset < strlen($line); $offset += $written) {
        $written = fwrite($handle, substr($line, $offset));
        if ($written === false || $written === 0) throw new RuntimeException('Export write failed.');
      }
    }
    if (!fflush($handle) || !fclose($handle)) throw new RuntimeException('Export close failed.');
    if (!rename($partial, $path)) throw new RuntimeException('Export finalization failed.');
  } finally { if (is_resource($handle)) fclose($handle); }
}
```

Requires PHP 8 or later. Treat a run as failed if it raises an error or leaves `.partial` files. Review all completed files, counts and approved IDs before importing; a completed JSONL file alone is not migration acceptance. The rows include extra metadata and arrays: adapt the converter field mapping, import DTOs, stored schema and frontend consumers before claiming those values are preserved.

## WordPress

The supplied notes report checks on WordPress 7.1. The scoped exporter below has been revised; its PHP syntax check is not a new CMS or plugin compatibility test.

- **Prefix:** `$table_prefix` in `wp-config.php` (default `wp_`). Use the real prefix in every query.
- **Content:** `wp_posts`. Filter `post_type IN ('post', 'page')` (plus any custom types the site uses) and `post_status = 'publish'`; `post_name` is the slug, `post_date_gmt` / `post_modified_gmt` are UTC. Rows with `post_type = 'revision'`, `'attachment'` or `'nav_menu_item'` are not pages.
- **Rendered HTML:** render approved public content through WordPress while the old site still runs. Save the example as `wp-export.php` beside the helper and run it with `wp --path=/path/to/site eval-file /private/work/wp-export.php`. Supply `MIGRATION_PUBLIC_POST_IDS` as an explicit comma-separated list of approved page/post IDs; optional `MIGRATION_USER_IDS` selects identity records separately. Set the private-output variables above. Approval must include reviewing password, membership and plugin access rules: the script rejects password-protected and unpublished posts, but cannot infer every plugin's privacy policy.

  ```php
  <?php
  require __DIR__ . '/export-support.php';
  $ids = migration_ids('MIGRATION_PUBLIC_POST_IDS'); $userIds = migration_ids('MIGRATION_USER_IDS', false);
  if (get_current_user_id() !== 0) throw new RuntimeException('Render public snapshots without a privileged --user.');
  $dir = migration_export_dir(ABSPATH);
  $content = function () use ($ids) {
    foreach ($ids as $id) {
      $p = get_post($id);
      if (!$p || !in_array($p->post_type, ['page', 'post'], true) || $p->post_status !== 'publish' || $p->post_password !== '') {
        throw new RuntimeException("Post $id is not eligible for this public snapshot.");
      }
      $previous = $GLOBALS['post'] ?? null; $GLOBALS['post'] = $p;
      try {
        if (!setup_postdata($p)) throw new RuntimeException('Cannot establish post context.');
        $url = get_permalink($p);
        if (!is_string($url)) throw new RuntimeException('Cannot resolve source permalink.');
        $isBuilder = class_exists('\Elementor\Plugin') && get_post_meta($id, '_elementor_edit_mode', true) === 'builder';
        // The source post is current; the template-display wrapper would reject it as recursive.
        $html = $isBuilder
          ? \Elementor\Plugin::$instance->frontend->get_builder_content($id, true)
          : apply_filters('the_content', $p->post_content);
        if (!is_string($html) || ($isBuilder && trim($html) === '')) {
          throw new RuntimeException("Builder snapshot for post $id is empty; inspect it before export.");
        }
        yield ['legacyId' => $id, 'siteId' => get_current_blog_id(), 'siteUrl' => home_url('/'),
          'postType' => $p->post_type, 'url' => $url, 'route' => migration_route($url),
          'language' => function_exists('pll_get_post_language') ? pll_get_post_language($id) : null,
          'translations' => function_exists('pll_get_post_translations') ? pll_get_post_translations($id) : [],
          'title' => $p->post_title, 'bodyHtml' => $html, 'published' => true,
          'updatedAt' => strtotime($p->post_modified_gmt . ' UTC'), 'authorLegacyId' => (int) $p->post_author,
          'summary' => ($p->post_excerpt ?? '') !== '' ? $p->post_excerpt : null,
          'publishedAt' => strtotime(($p->post_date_gmt ?? $p->post_modified_gmt) . ' UTC'),
          'fields' => function_exists('get_fields') ? get_fields($id) : null,
          'seoRawTitle' => get_post_meta($id, '_yoast_wpseo_title', true),
          'seoRawDescription' => get_post_meta($id, '_yoast_wpseo_metadesc', true)];
      } finally { wp_reset_postdata(); $GLOBALS['post'] = $previous; }
    }
  };
  migration_jsonl($dir . '/content.jsonl', $content());
  $users = function () use ($userIds) {
    foreach ($userIds as $id) {
      $u = get_userdata($id);
      if (!$u) throw new RuntimeException("Missing approved user $id.");
      yield ['legacyId' => $id, 'siteId' => get_current_blog_id(), 'email' => strtolower(trim($u->user_email)),
        'displayName' => $u->display_name, 'sourceRoles' => array_values($u->roles)];
    }
  };
  migration_jsonl($dir . '/users.jsonl', $users()); // No passwords, tokens or inferred authorization.
  ```

  This captures selected `page`/`post` snapshots, optional approved users, Polylang language/translation IDs, raw Yoast overrides and ACF values. Add a reviewed adapter for WPML or another language provider; do not infer language from the slug. Identify records by site plus post ID, and preserve the full source URL/route, including query strings and trailing-slash behavior. Split/map `content.jsonl` into the chosen import DTOs; extra fields are **discarded** by the existing converter unless explicitly mapped, and arrays/ACF structures require an adapted schema/importer and frontend use. Raw Yoast templates are not final rendered SEO tags.

  Post context is established, but CLI rendering does not recreate every URL, session, language, membership or request context or collect all enqueued styles/scripts. Compare anonymous and authenticated browser journeys. Searches for literal shortcodes or `<form|wpcf7|woocommerce|admin-ajax|wp-json` are only heuristics: hits require investigation, and no hits do not establish independence from PHP. Rebuild or retain live behavior separately; never publish private or personalized snapshots as public assets.
- **Metadata and options:** `wp_postmeta` and `wp_options` often hold serialized PHP (`a:2:{s:3:"foo";...}`). WordPress metadata APIs decode serialized values; this is not a guarantee that arbitrary metadata or plugin code is safe. Inspect and process an owner-approved copy in an isolated environment. Do not pass untrusted serialized input to PHP's `unserialize()`. Preserve exact bytes and validate decoded types before converting to JSON.
- **Taxonomies:** `wp_terms`, `wp_term_taxonomy`, `wp_term_relationships`.
- **Users:** `wp_users` (`user_email`, `display_name`; never `user_pass`) and all roles/capabilities in `wp_usermeta`. The example preserves every assigned role as source data, not target authorization. Review custom roles, direct capabilities, multisite membership and super-admin status separately, then define explicit target permissions and verified account linking.
- **URLs:** inspect `permalink_structure` and export `get_permalink()` for each selected record. Preserve parent/date/category/language paths and the actual slash behavior. For a slash-ending route, `dist/afval/index.html` serves `/afval/`; for a slashless route, `dist/afval.html` serves `/afval`. Query-string links such as `/?p=123` can circulate even with pretty permalinks; map them explicitly (`old-urls.md`).
- **Files:** `wp-content/uploads/YYYY/MM/`, including generated thumbnail sizes. Copy the ones still referenced into the static-site `dir` at the same paths so old image URLs keep working.
- **Schedules:** WP-Cron (`wp cron event list`), triggered by page visits rather than the system cron.
- **Plugins:** run `wp plugin list --status=active --skip-update-check --format=json`, then repeat for `active-network`, `must-use` and `dropin`; repeat per in-scope multisite site with `--url=<site-url>`. Inspect custom theme functions too. Decide per capability whether to rebuild, replace, retain as an integration or retire with the owner's consent. Record remaining PHP dependencies and owner-agreed live workflow tests. These platform-specific starting points require verification against installed versions and configuration:
  - *Contact Form 7:* forms are posts of type `wpcf7_contact_form` (fields in postmeta `_form`, recipients in `_mail`); the rendered `<form>` posts to `wp-json/contact-form-7`. Becomes a backend update method plus a page form; decide who receives the mail (`https-outcalls`).
  - *Yoast SEO:* raw per-page overrides in `_yoast_wpseo_title` and `_yoast_wpseo_metadesc` are exported above; canonical and social data may also use `wp_yoast_indexable`. Resolve templates/defaults and map required output into `<title>`, canonical, social and metadata tags; compare the original page head.
  - *Advanced Custom Fields:* values in postmeta under the field name (repeaters as `name_0_sub`, `name_1_sub`, ...) with a `_name` key reference beside each; `get_fields()` returns them structured (exported above) when the field groups are in the database or theme code. Each field becomes a record field.
  - *Elementor and other page builders:* builder structure may live in metadata such as `_elementor_data`; `post_content` alone need not reproduce the page. With the source post established as current, the example calls Elementor's direct `get_builder_content` API; its `get_builder_content_for_display` template wrapper deliberately returns empty for the current post. An empty builder snapshot stops the export for review. Compare full pages, assets, templates, conditions and live controls in the actual request context; preserve required styles or restyle deliberately.
  - *WooCommerce:* products are posts of type `product` with postmeta `_price`, `_sku`, `_stock_status` and the `wc_product_meta_lookup` table; orders in the `wc_orders*` tables (or posts of type `shop_order` on older sites); customers are users. The shop, cart, checkout and account pages export empty or as JavaScript-dependent markup. Catalog and content can move; checkout, payments, tax and stock are the owner decision under Magento's heading below.
  - *Polylang and WPML:* one post per language, linked by the `post_translations` taxonomy (Polylang) or the `icl_translations` table (WPML). Export the language and the links (the script does this for Polylang) and build one page per language at its own path.
  - *Wordfence, Akismet, caching and backup plugins:* identify the protections and operating duties they supply. Spam prevention, authorization, abuse handling, recovery and freshness may still be required. Replace, retain or retire each capability explicitly; removing PHP does not remove those responsibilities.

## Drupal 8 and later

- **Layout:** Composer sites keep the web root in `web/` (or `docroot/`); the project root holds `composer.json`, `vendor/` and `config/`. The inventory script reports the web root. Run `drush` from the project root.
- **Content:** `node_field_data` (`nid`, `type`, `langcode`, `title`, `status`, `created`, `changed` as Unix seconds); bodies in `node__body` (`entity_id`, `body_value`, `body_summary`, `body_format`); other fields in `node__field_<name>` tables. Multilingual sites have one row per `langcode`.
- **Text formats:** `body_format` (`basic_html`, `full_html`, ...) determines output filters. `$node->body->processed` applies those filters, but does not recreate a full page, Views, layout, access or editorial behavior. The supplied notes report Drupal 11.4 checks; the revised example below has only a PHP syntax check. Save it as `drupal-export.php` beside the [shared helper](#scoped-export-helpers), outside the web root. Run from the project with `drush php:script /private/work/drupal-export.php`. Set the private-output variables above and `MIGRATION_PUBLIC_NODE_TRANSLATIONS` to approved `node-id:langcode` pairs such as `16:en,16:fr`. Optional `MIGRATION_USER_IDS` selects identity records separately. Approval must consider module access rules and each translation; an export is not a new access policy.

  ```php
  <?php
  require __DIR__ . '/export-support.php';
  $raw = getenv('MIGRATION_PUBLIC_NODE_TRANSLATIONS') ?: '';
  if (!preg_match('/^[1-9][0-9]*:[A-Za-z0-9_-]+(,[1-9][0-9]*:[A-Za-z0-9_-]+)*$/D', $raw)) {
    throw new RuntimeException('Specify approved node-id:langcode pairs.');
  }
  $approved = array_fill_keys(explode(',', $raw), true);
  $nodeIds = array_unique(array_map(fn($key) => (int) explode(':', $key, 2)[0], array_keys($approved)));
  $userIds = migration_ids('MIGRATION_USER_IDS', false); $dir = migration_export_dir(DRUPAL_ROOT);
  $content = function () use ($approved, $nodeIds) {
    $seen = []; $anonymous = new \Drupal\Core\Session\AnonymousUserSession();
    $switcher = \Drupal::service('account_switcher'); $switcher->switchTo($anonymous);
    try {
      $storage = \Drupal::entityTypeManager()->getStorage('node');
      $aliases = \Drupal::service('path_alias.manager');
      foreach ($storage->loadMultiple($nodeIds) as $node) {
        foreach ($node->getTranslationLanguages() as $langcode => $language) {
          $key = $node->id() . ':' . $langcode;
          if (!isset($approved[$key])) continue;
          $translation = $node->getTranslation($langcode);
          if (!in_array($translation->bundle(), ['page', 'article'], true) || !$translation->isPublished()
              || !$translation->access('view', $anonymous)) throw new RuntimeException("Translation $key is not public.");
          $url = $translation->toUrl('canonical', ['absolute' => true, 'language' => $language])->toString();
          $body = $translation->hasField('body') && !$translation->get('body')->isEmpty() ? $translation->get('body') : null;
          yield ['legacyId' => (int) $node->id(), 'sourceUuid' => $node->uuid(), 'language' => $langcode,
            'contentType' => $translation->bundle(), 'url' => $url, 'route' => migration_route($url),
            'alias' => $aliases->getAliasByPath('/node/' . $node->id(), $langcode),
            'title' => $translation->getTitle(), 'bodyHtml' => $body ? trim((string) $body->processed) : '',
            'summary' => $body ? $body->summary : null, 'published' => true,
            'updatedAt' => (int) $translation->getChangedTime(), 'publishedAt' => (int) $translation->getCreatedTime(),
            'authorLegacyId' => (int) $translation->getOwnerId()];
          $seen[$key] = true;
        }
      }
      if (array_diff_key($approved, $seen)) throw new RuntimeException('Some approved translations were not found.');
    } finally { $switcher->switchBack(); }
  };
  migration_jsonl($dir . '/content.jsonl', $content());
  $users = function () use ($userIds) {
    $storage = \Drupal::entityTypeManager()->getStorage('user');
    foreach ($userIds as $id) {
      $u = $storage->load($id);
      if (!$u) throw new RuntimeException("Missing approved user $id.");
      yield ['legacyId' => $id, 'sourceUuid' => $u->uuid(), 'email' => strtolower(trim((string) $u->getEmail())),
        'displayName' => $u->getDisplayName(), 'sourceRoles' => array_values($u->getRoles())];
    }
  };
  migration_jsonl($dir . '/users.jsonl', $users()); // Preserve source roles as data, not target authorization.
  ```

  Identify translated records by node ID/UUID **and language**, so imports do not overwrite translations sharing the same node ID. Preserve both aliases and language-aware canonical URLs; domain/prefix negotiation can make them differ. Adapt the converter, import schema and frontend to these rows, including custom fields where required. Anonymous rendering and entity access checks do not establish every module's output policy; test relevant contexts and exclude personalized output from public snapshots.

- **Modules and custom code:** inventory enabled modules with `drush pm:list --type=module --status=enabled --format=json`; inspect contributed/custom modules, themes, controllers, services, hooks and event subscribers. Record each capability and its dependencies, then choose a rebuild, replacement, retained integration or approved retirement.
- **Dynamic workflows:** inventory Views displays, filters and contextual arguments; form validation/submission, calculated fields, roles/permissions/access checks, revisions, moderation, translations and editorial publishing. Define owner-agreed live tests for allowed and denied actions and relevant user/route/language/filter contexts. Filtered body HTML alone does not preserve these behaviors.
- **Raw SQL exports:** confirm the MySQL/MariaDB client's connection encoding before export; a wrong setting can corrupt Unicode. Where supported, pass explicit flags such as `drush sql:query --extra="--default-character-set=utf8mb4 --batch --raw" "SELECT ..."` and reconcile representative Unicode values. Consult the installed Drush version rather than assuming its defaults.
- **URLs:** `path_alias` includes the internal path, alias and language. Preserve the observed route and actual slash behavior; generate reviewed language-aware redirects for circulating `/node/<nid>` links. Do not collapse different language aliases to one path.
- **Users:** `users_field_data` (`uid`, `name`, `mail`; never `pass`); roles in `user__roles` (`entity_id`, `roles_target_id`), plus implicit roles. Preserve all assigned roles, then review permissions, user 1's special status, access modules and verified account linking explicitly. Do not infer target permissions from the first role.
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
