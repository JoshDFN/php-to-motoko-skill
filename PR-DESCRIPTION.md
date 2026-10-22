## Add `migrating-php-apps`: move a PHP site or app to Motoko on ICP

**What it covers.** Moving an existing PHP website or application (WordPress, Drupal, Joomla, Magento, Laravel, Symfony, CodeIgniter or plain PHP on MySQL or PostgreSQL) to the Internet Computer with a Motoko backend, in six phases with explicit user approval before anything irreversible: read-only inventory, plan, build (static-site frontend or an existing frontend host, plus a Motoko backend), database export and batch import into actor state, users and sign-in (Internet Identity, accounts linked only with verified proof), and cut-over (old URLs kept working, custom domain, evidence that it works). It delegates to existing skills (writing-motoko, migrating-motoko-actors, mops-cli, icp-cli, static-site, internet-identity, canister-security, https-outcalls, custom-domains, cycles-management) instead of restating them.

**Why it's needed.** PHP2Shell (CVE-2026-109618 and CVE-2026-109619, patched 21 October 2026) pushed government, university and company PHP sites offline. Agents asked to "move this PHP site to ICP" currently improvise the data import, URL preservation and sign-in migration. This skill encodes a tested path and 17 pitfalls that break such migrations.

**How it was tested.** End to end on a realistic PHP fixture (a municipal site with pages, news, users and a contact form; accented text, emoji, quotes, tabs, NULLs, password hashes and secrets in config.php) on a local ICP network with icp-cli 1.7.0, moc 1.14.0 (also compiles with 2.0.0) and core 2.6.2: the inventory script, MySQL export (including the corruption that `--raw` prevents), JSONL to Candid conversion, batch import with idempotent re-runs, the controller-only import guard, Unicode round-trips, pagination, an upgrade with data in place, unpublished rows staying hidden, and `_redirects` plus legacy `.php?` URL mapping on the static-site recipe.

**Re-run from the documentation.** A fresh project built only from `references/backend-example.md` type-checks with the pinned toolchain (moc 1.14.0) and compiles with moc 2.0.0; following the documented inventory, conversion, import, reconcile and upgrade commands on a local network reproduces every result above. Every shell block passes ShellCheck.

**Also tested on real WordPress.** A WordPress 7.1.3 install (pages, posts, a draft, categories, an uploaded image with generated thumbnails, serialized post meta, three users with different roles, a menu, pretty permalinks, a WP-Cron job) was migrated with the skill's own instructions: the inventory script (now skipping platform core directories), the WordPress export script in `frameworks.md` (rendered HTML via `apply_filters('the_content')`, no password hashes), the converter, the controller-only batch import into the example backend, and a frontend rebuilt at the old permalinks. Verified on a local network: counts match the WordPress database, the draft is hidden, Unicode survives, `/afval/` serves and `/afval` redirects to it, `/?p=8` and `/?page_id=4` land on the right pages, `/wp-content/uploads/...` images and thumbnails load at their old paths, and `/wp-admin/` is gone.

**Also tested on Drupal, Joomla, Laravel, Symfony, CodeIgniter and Magento.** Drupal 11.4 (Composer layout) was migrated end to end the same way: inventory from the project root, the Drupal export script in `frameworks.md` (`drush php:script`, bodies via `$node->body->processed`, aliases, roles), import, and a frontend at the alias paths with generated `/node/<nid>` redirects and only `file_managed` files copied; verified on a local network. Joomla 6.2, Laravel 13, Symfony 7.4 and CodeIgniter 4.7 were installed and every table, column, command and path the notes name was checked against them (including the double-encoding repair expression on a corrupted row). Magento 2 could not be installed here; its table and column names were checked against Magento 2.4's `db_schema.xml` files. Fixes that came out of this: web-root detection for Composer layouts, `drush sql:query` needing `--default-character-set=utf8mb4`, the `user__roles` and `body_summary` columns, the Drupal files-directory warning, Joomla's `/index.php/` prefix, and Laravel's `schedule:list` needing a database connection.

**ICP-specific behaviour verified on a local network.** The timer in the example runs on schedule, re-arming never stacks timers, non-controllers cannot start it, its stable counter survives upgrades while the timer itself stops until `startJobs` is called again. A post-go-live migration (adding `views : Nat` to every page through a new migration file) kept all data; it also surfaced that a changed record in a public method's signature trips icp-cli's Candid compatibility check, so the example now gives the import methods their own row types. A Vite frontend built with `@icp-sdk/bindgen` fetched pages from the backend in a browser through the `ic_env` cookie, as the icp-cli skill prescribes.

**Both targets tested.** Target A (everything on ICP) is the WordPress and Drupal run above. Target B (backend on ICP, frontend elsewhere) was tested with the frontend served from a separate origin: it read pages from the backend through the generated bindings across origins, and its anonymous write attempt was refused. That test also surfaced a pitfall now in the skill: a fresh icp-cli deploys as `anonymous`, which makes the anonymous principal the local canister's controller, so local access-control tests pass vacuously until the canister is handed to a named identity.

**Test suite.** The skill's repository carries `tests/` and a GitHub Actions workflow that re-run all of the above on every change: 24 backend checks, 32 WordPress checks (with Contact Form 7, Yoast, WooCommerce, ACF, Elementor and Polylang active), 31 Drupal checks and 40 platform-note checks, all taken from the skill's own documentation.

**Checks.**
- `skill-validator check skills/migrating-php-apps --skip links` (v1.5.1, as in CI): passed, no warnings
- `node scripts/check-project.js migrating-php-apps`: passed, no warnings
- `npm run build`: passes; the skill page, JSON entry and llms.txt listing are generated
- `node scripts/evaluate-skills.js migrating-php-apps`: not run yet (needs the `claude` CLI); please run before merge. `evaluations/migrating-php-apps.json` has 7 output evals, 10 should-trigger and 9 should-not-trigger queries.

**Category.** Set to `Core`. `Motoko` would also fit; happy to change it.

<details><summary>skill-validator report</summary>

## Validating skill: /tmp/icskills-latest/skills/migrating-php-apps

### Structure

- **Pass:** SKILL.md found
- **Pass:** internal link: references/inventory.md (exists)
- **Pass:** internal link: references/frameworks.md (exists)
- **Pass:** internal link: references/backend-example.md (exists)
- **Pass:** internal link: references/old-urls.md (exists)
- **Pass:** internal link: references/data-import.md (exists)
- **Pass:** all files in references/ are referenced

### Frontmatter

- **Pass:** name: "migrating-php-apps" (valid)
- **Pass:** description: (859 chars)
- **Pass:** license: "Apache-2.0"
- **Pass:** compatibility: (163 chars)
- **Pass:** metadata: (2 entries)

### Markdown

- **Pass:** no unclosed code fences found

### Tokens

| File | Tokens |
| --- | ---: |
| SKILL.md body | 4,996 |
| references/backend-example.md | 2,703 |
| references/data-import.md | 2,878 |
| references/frameworks.md | 3,852 |
| references/inventory.md | 2,475 |
| references/old-urls.md | 1,032 |
| **Total** | **17,936** |

### Content Analysis

| Metric | Value |
| --- | ---: |
| Word count | 3,231 |
| Code block ratio | 0.05 |
| Imperative ratio | 0.20 |
| Information density | 0.12 |
| Instruction specificity | 1.00 |
| Sections | 12 |
| List items | 67 |
| Code blocks | 7 |

### References Content Analysis

| Metric | Value |
| --- | ---: |
| Word count | 6,299 |
| Code block ratio | 0.52 |
| Imperative ratio | 0.09 |
| Information density | 0.31 |
| Instruction specificity | 0.91 |
| Sections | 30 |
| List items | 67 |
| Code blocks | 26 |

### Contamination Analysis

| Metric | Value |
| --- | --- |
| Contamination level | high |
| Contamination score | 0.55 |
| Primary language category | shell |
| Scope breadth | 5 |

- **Warning: Language mismatch:** config, query (2 categories differ from primary)
- **Multi-interface tool detected:** mysql, postgresql

### References Contamination Analysis

| Metric | Value |
| --- | --- |
| Contamination level | high |
| Contamination score | 0.69 |
| Primary language category | shell |
| Scope breadth | 6 |

- **Warning: Language mismatch:** config, javascript, markup, python (4 categories differ from primary)
- **Multi-interface tool detected:** mysql, postgresql, redis

**Result: passed**

</details>
