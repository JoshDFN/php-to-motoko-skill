---
name: migrating-php-apps
description: "Move an existing PHP website or web app to the Internet Computer with a Motoko backend: WordPress and Drupal sites, Joomla and Magento stores, Laravel, Symfony or CodeIgniter apps, and plain PHP on MySQL or PostgreSQL. Covers the read-only inventory and the plan the user approves, rebuilding pages as a static-site frontend or keeping an existing frontend host, porting PHP logic to Motoko, exporting the database and batch-importing it into actor state, keeping old URLs working, moving sign-in to Internet Identity, and cutting over to the existing domain with evidence that it works. Use when the user wants to migrate, port or rebuild a PHP or LAMP site on ICP, move it to Motoko, or get off PHP. Do NOT use for a new Motoko app with no PHP predecessor (use writing-motoko) or for changing a deployed canister's state shape (use migrating-motoko-actors)."
license: Apache-2.0
metadata:
  compatibility: "icp-cli >= 1.0.0, mops >= 3.0.0, moc >= 1.12.0, core >= 2.6.0, Node.js >= 22, Python 3; read access to the PHP source, a database export and the upload directories"
  title: "Migrating PHP Apps to Motoko"
  category: Core
---

# Migrating PHP Apps to Motoko

## What This Is

A workflow for taking a running PHP site or application, with its data, users and URLs, to the Internet Computer. Examples and historical test reports cover specific scenarios; validate the actual application's features and integrations. The default architecture:

```text
Browser ── HTTPS ──> HTTP gateway ──> frontend canister (@dfinity/static-site, certified-assets)
   │                                   built HTML/CSS/JS, public media, _redirects, _headers
   └── signed canister calls (Candid) ──> backend canister (Motoko)
                                         data, business rules, import endpoints
Sign-in: Internet Identity    Scheduled jobs: timers    Outbound APIs: HTTPS outcalls
Domain: custom-domains        No PHP runtime, web server, database server or OS left to patch
```

Why this shape: the static-site canister certifies every response ahead of time, so it serves a **finite set of files**. This architecture builds pages ahead of time or renders them in the browser from backend data. ICP also supports request-time HTTP rendering, including in Motoko through query-to-update delivery; certification is not a Rust-only protocol. For custom HTTP routes, choose and test the certification or update path described in [`references/delivery.md`](references/delivery.md), and read its integrity constraints before considering certification opt-outs.

This skill orchestrates the migration. Load these skills for the details it delegates: `writing-motoko` (all Motoko code), `migrating-motoko-actors` (state changes after go-live), `mops-cli`, `icp-cli`, `static-site`, `internet-identity`, `canister-security`, `https-outcalls`, `custom-domains`, `cycles-management`; and when relevant `multi-canister` (data beyond one canister), `vetkeys` / `encrypted-maps` (data that must stay confidential), `deploy-to-cloud-engine` and `cloud-engine-canisters` (organization-owned capacity).

## Prerequisites

- The PHP source (repository or a copy of the web root), a **read-only** database account or a recent export, and a copy of the upload directories.
- `icp-cli`, `ic-wasm`, `mops` (see `icp-cli` and `mops-cli`), Node.js >= 22, Python 3, and the `mysql`/`mariadb` or `psql` client.
- Production database write access is never needed. Never copy secret values (database passwords, SMTP or API keys) into the new code, the canister, batch files, reports or chat.

## Ground Rules

1. **The old site keeps running, patched, until cutover.** Work from copies. Nothing in the old system changes before the write freeze in Phase 6.
2. **Track every feature in a feature map** and update it as you go. One row per route, form, job, integration, role and table:

    | Feature | Where in PHP | New home | Status | Evidence |
    |---------|--------------|----------|--------|----------|
    | News article page | `news.php`, `.htaccess` rule 1 | static page per item + `getNews` | tested | `/nieuws/12` → 200 locally |

    Status moves `found → built → tested → data moved → verified live`. A feature without evidence is not done; a feature you cannot rebuild is a **listed gap**, never silently dropped.

3. **Get the owner's sign-off on the plan (Phase 2)**, then work through reversible steps without asking again. Ask again before the write freeze, the DNS change and decommissioning; these are the irreversible ones.
4. **"It builds" is a checkpoint, not the finish.** Done means the agreed features work at the live URL with migrated data, and the hand-over evidence below exists.

## Phase 1: Inventory

Run the read-only inventory script from [`references/inventory.md`](references/inventory.md) at the PHP project root:

```bash
bash php-inventory.sh > inventory.md
```

It reports the platform (WordPress, Drupal, Joomla, Magento, Laravel, Symfony, CodeIgniter or plain PHP), entry points, `.htaccess` rewrite rules, which files use sessions, logins, forms, uploads, email, outbound HTTP, shell commands, image/PDF libraries and the database, plus SQL tables, scheduled jobs, upload directory sizes, and the **names** (never values) of configuration secrets.

Then collect what the script cannot see:

- **Row counts and sizes**, for reconciliation and capacity planning (MySQL/MariaDB):

    ```sql
    SELECT table_name, table_rows, ROUND((data_length + index_length) / 1048576, 1) AS mb
    FROM information_schema.tables WHERE table_schema = DATABASE() ORDER BY mb DESC;
    ```

    `table_rows` is an estimate for InnoDB; reconcile against `SELECT COUNT(*)`.

- **The URLs that matter**: `sitemap.xml`, the CMS's URL/alias table (see [`references/frameworks.md`](references/frameworks.md)), and the most-requested paths from the access log: `awk '{print $7}' access.log | sort | uniq -c | sort -rn | head -2000` (common/combined log format).
- **Logged-in and admin journeys**: a public URL never shows private logic, roles or data. Read the code for them.

For WordPress, Drupal, Joomla, Magento, Laravel and Symfony, read [`references/frameworks.md`](references/frameworks.md) now: where content, users, URLs and schedules live, and the platform-specific traps (serialized PHP values, EAV tables, shortcodes).

## Phase 2: Plan What Moves Where

| On the PHP site | On the Internet Computer | Watch out for |
|-----------------|--------------------------|---------------|
| Server-rendered pages and templates | Pages built ahead of time into the static-site `dir`, or a browser-rendered app that calls the backend | Content edited daily: render it in the browser from backend data, or rebuild and sync from CI with an `authorize`d syncer principal (`static-site`) |
| Controllers, includes, plugins | `public` functions on a Motoko actor, `query` for reads | SQL joins and transactions become explicit code; one update call is all-or-nothing unless it `await`s |
| Tables | For example, `Map`s keyed by legacy identifiers with extra indexes; adapt to the actual schema | Heap is 4 GiB (wasm32) / 6 GiB (wasm64) per canister; beyond a few GiB of data, split canisters (`multi-canister`) |
| Public media (images, PDFs) | Files in the static-site `dir`, uploaded on deploy | The static-site canister has no runtime upload API |
| Runtime uploads (`$_FILES`) | Chunks of at most 1 MB per call into the backend, with per-user quotas | 2 MB request/response limit; unbounded storage is a denial-of-service vector (`canister-security`) |
| `$_SESSION`, login forms, password hashes | Internet Identity and `caller` | Phase 5; never import password hashes |
| CSRF tokens | Remove them for canister calls | Each call is signed by the session key the app holds; no ambient cookies are sent |
| `cron` | Motoko timers (`mo:core/Timer`) armed by a controller-only method | Under the migration chain the actor body cannot have side effects; re-arm after each deploy |
| `mail()`, SMTP, PHPMailer | HTTPS outcall to a transactional email API, non-replicated or with an idempotency key | Replicated POSTs are sent once per replica (`https-outcalls`); where the API key lives is an owner decision (security acceptance) |
| `curl`, Guzzle | HTTPS outcalls | HTTPS and public endpoints only |
| Incoming webhooks, payments | Owner decision: certified custom `http_request` or an external receiver | Flag as a decision; never stub it |
| `exec`, GD/Imagick, PDF libraries | Build time, the browser, or an external service | No processes or native extensions in a canister |
| Composer packages | Mops packages, or reimplement | Most have no Motoko equivalent; list each in the feature map |
| Web server, PHP-FPM, OS | Nothing | |

**Choose the target with the owner:**

- **A. All on ICP (default):** frontend and backend canisters, the existing domain pointed at the frontend.
- **B. Keep the existing frontend host:** the rebuilt static frontend stays on the owner's host or CDN and calls the Motoko backend on ICP; verify cross-origin calls for the selected deployment. Without the `ic_env` cookie the canister id is page configuration; on mainnet pass no host or root key, locally take both from `icp network status --json`. The external host can change the JavaScript that talks to the backend, so it stays an integrity dependency, and it is the Internet Identity origin (Phase 5).

**Choose where it runs:** `icp deploy -e ic` picks an application subnet. For data-residency rules, create the canisters with `--subnet <subnet-id>` on a subnet whose node locations fit (ICP dashboard); the flag only affects creation. For an organization's own cloud engine, `--engine <engine-name>` with `deploy-to-cloud-engine` and `cloud-engine-canisters` loaded (engines charge no cycles; never attach cycles there).

Present the feature map, the target and the gaps; get sign-off.

## Phase 3: Build

Scaffold with `icp-cli` and `mops-cli`. Follow the file layout and rules of `writing-motoko` (`types.mo`, `lib/`, `mixins/`, `main.mo`, a `migrations/` chain). [`references/backend-example.md`](references/backend-example.md) demonstrates CMS-style content imports and public reads, with historical local test reports. Adapt it to the actual application; it does not implement a complete CMS or plugin system, and those reports are not evidence of a new migration passing. Its example `icp.yaml`:

```yaml
canisters:
  - name: backend
    recipe:
      type: "@dfinity/motoko@v5.1.0"
  - name: frontend
    recipe:
      type: "@dfinity/static-site@v0.4.0"
      configuration:
        dir: dist
```

Backend rules, each for a reason:

1. **Preserve legacy identifiers and relationships deliberately.** Use the source's numeric, text/UUID or composite keys; the example uses `Nat`. Old URLs, foreign keys and safe re-imports depend on a consistent mapping.
2. **Import methods are controller-only** (`caller.isController()`: the identity that deploys), **cap the batch size**, and **upsert**, so a failed run can simply be repeated.
3. **Read methods paginate.** A response over 2 MB traps; never return a whole table.
4. **Every public update method checks its caller** and rejects the anonymous principal where sign-in is required (`canister-security`).
5. **Map column types deliberately:** money as `Nat` in minor units, never `Float`; time as `Int` nanoseconds since 1970 UTC (the unit of `Time.now()`); nullable columns as `?T`; `ENUM` as a variant.
6. **Stable fields have no initializers**: the first migration file supplies them (`migrating-motoko-actors`). After go-live, every state change goes through that skill; keep import row types separate from stored types, or `icp deploy` refuses the changed method signature (see the example).
7. **Scheduled jobs:** a controller-only `startJobs()` cancels the previous timer, then arms `Timer.recurringTimer<system>`; call it after every deploy.

Frontend rules:

1. **Keep old URLs by building pages at their old paths.** The canister serves `dist/nieuws/12.html` at `/nieuws/12` and `dist/afval.html` at `/afval` (clean URLs), so old pretty links work with no redirect at all. A URL ending in a slash (WordPress) is a directory: `dist/afval/index.html` is served at `/afval/`, and `/afval` redirects to it.
2. **Renamed paths get exact `_redirects` rules generated from the export.** There are no `:splat` captures.
3. **Query-string URLs (`index.php?page=…`, `news.php?id=…`) cannot be matched by `_redirects`**, which ignores the query string. Rewrite the script path (`/index.php  /legacy.html  200`) to a small page whose script maps the parameters to new paths. Generator and page: [`references/old-urls.md`](references/old-urls.md).
4. **Add `_headers`.** The static-site canister sends no default security headers (`static-site`).
5. **Call the backend through generated bindings** (`@icp-sdk/bindgen`, see `icp-cli`): canister id and root key come from the `ic_env` cookie, never a hard-coded host; `opt T` arrives as `T | null`. Sign in with Internet Identity (`internet-identity`) where a method needs a caller.

## Phase 4: Move the Data

Full commands and the converter are in [`references/data-import.md`](references/data-import.md). The sequence:

1. **Back up** the old database (`mysqldump --single-transaction`); this copy is never modified.
2. **Export each table as JSON lines**, one object per row, with the columns already renamed to the Motoko field names:

    ```bash
    mysql --default-character-set=utf8mb4 --batch --raw --skip-column-names -e "
      SET time_zone = '+00:00';
      SELECT JSON_OBJECT('legacyId', id, 'slug', slug, 'title', title, 'bodyHtml', body,
                         'published', published, 'updatedAt', UNIX_TIMESTAMP(updated_at))
      FROM pages ORDER BY id;" > export/pages.jsonl
    ```

3. **Convert to Candid batch files** with the stdlib-only `jsonl_to_candid.py` (field types `nat`, `int`, `text`, `bool`, `time`, `variant`, `opt:<type>`):

    ```bash
    python3 jsonl_to_candid.py export/pages.jsonl batches/pages \
      legacyId:nat slug:text title:text bodyHtml:text published:bool updatedAt:time
    ```

4. **Import**, stopping at the first failure (re-running is safe because imports upsert):

    ```bash
    for f in batches/pages-*.did; do
      icp canister call backend importPages --args-file "$f" -e ic || { echo "failed at $f"; break; }
    done
    ```

5. **Reconcile:** counts from `importCounts` against `SELECT COUNT(*)` per table; spot-check records containing accents, emoji, quotes, tabs and backslashes; compare SHA-256 hashes of migrated files. Keep the results for the hand-over.
6. **Snapshot** the populated backend before anything risky: `icp canister stop backend -e ic && icp canister snapshot create backend -e ic && icp canister start backend -e ic`.

## Phase 5: Users and Sign-In

- **Do not import password hashes.** Internet Identity cannot use them, and canister memory on standard application subnets is readable by node operators. Import identity data only (legacy id, email, display name, role).
- **Decide the final domain before real users sign in.** Internet Identity derives a different principal per origin. It treats `ic0.app`, `icp0.io` and `icp.net` as one origin, but a custom domain is a different one, and so is the external host in target B. Moving origins later needs `derivationOrigin` (`internet-identity`, "Serving an app at more than one origin").
- **Link legacy accounts only with verified proof**, never an email the user merely typed: either the Internet Identity `verified_email` attribute matches the imported address (not `email`, which II does not verify; SSO emails only for domains you list), or a one-time code shown on the old site while both run. See `internet-identity` for attribute verification in the backend.
- **Staff and editors:** organization SSO through Internet Identity (`ssoDomain`), or an explicit principal allowlist that only controllers can change.

## Phase 6: Cut Over

1. Deploy to the chosen network, subnet or engine; fund it (`cycles-management`, `buy-cycles`). Commit `.icp/data/mappings/ic.ids.json`: it holds the canister IDs.
2. Run the new site side by side at `https://<frontend-id>.icp.net`. To keep a preview private, use the static-site access protection.
3. With the owner's go-ahead, **freeze writes** on the old site (maintenance or read-only mode), re-run the export and import (a full re-run is safe; or only rows changed since the last export), and reconcile again.
4. Snapshot the backend.
5. Add `.well-known/ic-domains` to the frontend `dir`, register the domain (`custom-domains`), then, with the owner's go-ahead, switch DNS.
6. **Verify live on the real domain:** every journey in the feature map, sign-in, forms, uploads, old URLs (pretty paths, renamed paths, query-string URLs), the 404 page, and an upgrade of the backend with production data in place.
7. Keep the old stack read-only and patched for the agreed rollback window, then decommission it and securely delete exports that contain personal data.

**Rollback is two different things.** Redeploying old code does not undo data changes. To return the backend to a known state, stop it and run `icp canister snapshot restore backend <snapshot-id> -e ic`, then start it.

## Security Acceptance

- Link only verifying hostnames (`<id>.icp.net` or the custom domain), never `<id>.raw.icp.net`, which skips certificate checks.
- Query calls are answered by a single replica. For integrity-sensitive reads use update calls or certified data (`certified-variables`).
- Consensus protects integrity, not confidentiality. Keep secrets out of canister state; treat personal data as readable by node operators on standard subnets, or encrypt it client-side (`vetkeys`, `encrypted-maps`).
- Controllers can replace the code. Record who they are, add a backup controller, and protect those keys (`canister-security`).
- For the frontend, the static-site state hash lets anyone check the deployed files against a rebuild from source (`static-site`).
- In target B, write down that the external frontend host remains a trust dependency. Do not call that setup tamperproof end to end.

## Hand-Over Evidence

Deliver: live URL(s); canister IDs, network and subnet or engine; source location and the exact build, deploy and import commands; the feature map with evidence per row; reconciliation results; test results, including the populated-state upgrade; controllers and backup controller; cycles balance and monitoring; snapshot IDs and the rollback procedure; and a list of every gap and intentional difference. If access, funding or an owner decision blocks deployment, finish all independent work and name the exact blocker; never report an undeployed build as done.

## Pitfalls

1. **Exporting without `--raw`.** In batch mode the `mysql`/`mariadb` client escapes backslashes, tabs and newlines in values again, so `JSON_OBJECT` output with `\n` or `\"` inside becomes unparseable or, worse, parses with corrupted text. Always pass `--batch --raw --skip-column-names`.
2. **`opt 5 : nat` in Candid text.** The annotation binds to the whole option and the call fails with `type mismatch: opt 5 cannot be of type nat`. Write `opt (5 : nat)`; the converter does this.
3. **Sending a whole table in one call.** Requests and responses are limited to 2 MB. Batch imports and paginate reads.
4. **Non-idempotent imports.** An import that appends instead of upserting creates duplicates when a failed run is repeated. Upsert by legacy id and keep secondary indexes in sync (remove the old index entry when a key such as a slug changes).
5. **Unguarded import methods.** Every update method is callable by anyone on the internet. Gate imports on `caller.isController()`.
6. **Expecting `_redirects` to match query strings or capture segments.** Neither is supported: certification needs every response enumerable ahead of time. Build pages at old paths, generate exact rules, and use the mapping page for query-string URLs.
7. **Treating dynamic HTTP as static-site delivery.** The static-site recipe serves finite files; custom Motoko HTTP rendering needs its own certified-query or query-to-update design. Verify the selected libraries and gateway behavior, including response integrity; see [`references/delivery.md`](references/delivery.md).
8. **Importing secrets or password hashes into canister state.** Node operators on standard application subnets can read canister memory.
9. **Changing the sign-in origin after launch.** Users get new principals on a new origin and lose access to their data unless `derivationOrigin` is configured.
10. **Wrong time zone on `DATETIME`.** `UNIX_TIMESTAMP()` reads a `DATETIME` in the session time zone. Set `SET time_zone` to the zone the PHP app wrote in (`date.timezone`, `date_default_timezone_set`); `TIMESTAMP` columns are stored in UTC and need no adjustment.
11. **Double-encoded text.** Older MySQL sites often hold UTF-8 bytes in `latin1` columns; exports then show `Ã©` for `é`. Detect it on spot-checks and fix it in the export query (see `references/data-import.md`), never in the canister afterwards.
12. **Serialized PHP in columns** (`a:2:{…}` in WordPress `wp_options` and `wp_postmeta`, many plugin tables). Decode during export with the PHP CLI; do not import the raw strings.
13. **Starting timers in the actor body.** The migration chain disallows side effects there. Arm them from a controller-only method and call it after every deploy.
14. **Leaving `--default-persistent-actors` in `[moc] args` on moc 2.x.** Actors are persistent by default from moc 2.0.0 and the flag was removed, so the build fails. Keep it only on moc 1.x, where the `icp new` template sets it.
15. **Replicated POST outcalls to email or payment APIs.** Every replica sends the request. Use an idempotency key or a non-replicated outcall (`https-outcalls`).
16. **Assuming default security headers.** The static-site canister adds none; declare them in `_headers`.
17. **Reporting success from exit codes.** An importer that exits 0 has not proven the data is right. Reconcile counts, spot-check records and verify journeys on the live origin.
18. **Local security tests can lie.** A fresh icp-cli deploys as `anonymous`, then the only controller, so anonymous calls pass `caller.isController()` locally. Hand the canister to a named identity first (`icp canister settings update backend --add-controller <dev> --remove-controller 2vxsx-fae -e local`).
