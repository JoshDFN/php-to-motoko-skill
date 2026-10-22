# New skill: migrating-php-apps

Adds `skills/migrating-php-apps/` and `evaluations/migrating-php-apps.json`.

## What it covers

Moving an existing PHP site or app (plain PHP, WordPress, Drupal, Joomla, Magento, Laravel, Symfony, CodeIgniter; MySQL, MariaDB or PostgreSQL) to ICP with a Motoko backend: inventory, a what-moves-where plan, target choice (all on ICP, or an existing frontend host plus a Motoko backend, with subnet or cloud-engine placement), a static-site frontend that keeps old URLs, batch data import into actor state, Internet Identity in place of password logins, cutover, security acceptance and hand-over evidence. It delegates language, CLI, hosting, auth and security details to the existing skills by name.

## Why it is needed

No current skill covers bringing an existing web application, its data, users and URLs onto ICP. Agents asked to "move our PHP site to ICP" otherwise guess at exports, redirects and imports, and the guesses fail in the ways listed under Pitfalls.

## How it was tested

On a fixture PHP site (municipal style, with accents, emoji, quotes, tabs, backslashes, newlines and NULLs in the data):

- Inventory script run against the fixture; one false positive found and fixed.
- MariaDB 10.11 export: without `--raw`, one row was unparseable and one silently corrupted; with `--raw`, all rows exact.
- Converter output imported with `icp canister call --args-file` (icp-cli 1.7.0, local network). Found and fixed `opt 5 : nat` (must be `opt (5 : nat)`).
- Backend (`mops check --fix`, moc 1.14.0, core 2.6.2, migration chain) deployed; verified imports, repeated import (counts unchanged), non-controller import rejected, unpublished rows hidden, pagination, Unicode round-trip, upgrade with data in place. The same sources compile with moc 2.0.0; the timer pattern compiles with moc 2.0.0.
- `@dfinity/static-site@v0.4.0`: old pretty paths served with 200, exact rule 301, `/index.php?page=…` and `/news.php?id=…` rewritten to the mapping page (query strings ignored), 404 page.
- `node scripts/check-project.js migrating-php-apps`: passed, 0 warnings.

## Still to run before merge

- `npm run validate` (needs the `skill-validator` binary).
- `node scripts/evaluate-skills.js migrating-php-apps` (needs the `claude` CLI); paste the results here in a `<details>` block.
- Not exercised: PostgreSQL export, mainnet deployment, custom domain, Internet Identity account linking, the mapping page's script in a real browser.
