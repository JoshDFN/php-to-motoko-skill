---
name: migrating-php-apps
description: Rebuild an existing PHP, WordPress, Drupal or other PHP application with a Motoko backend on the Internet Computer. Assess the actual application, preserve agreed behavior and data, and validate the migration. Use for a PHP predecessor, not a new Motoko application.
license: Apache-2.0
metadata:
  title: Migrating PHP Apps to Motoko
  category: Core
  compatibility: icp-cli >= 1.7.0, mops >= 3.0.0, moc >= 1.12.0, core >= 2.6.0, Node.js >= 22, Python 3; access to the source and representative application data
---

# Migrating PHP Apps to Motoko

Rebuild the agreed behavior of an existing PHP service in Motoko. Preserve its required data, URLs and user journeys. A successful migration includes working operations after import: editing, publishing, forms, calculations, permissions, jobs and integrations where the application uses them.

PHP plugins and Drupal modules do not run unchanged in Motoko. For each required capability, choose a rebuild, replacement, retained integration or owner-approved retirement. A database import or static export alone does not establish compatibility.

## Use references selectively

Use the application's source, configuration, schema and observed behavior as the evidence. Existing tooling or an equivalent read-only inventory is sufficient; do not run an additional script solely because this skill includes one. Confirm version-sensitive commands against the installed tools.

Read only the relevant references:

| When needed | Reference |
|-------------|-----------|
| Discovering an unfamiliar codebase | [Optional inventory helper](references/inventory.md) |
| Platform-specific structures or extension behavior | [Platform notes](references/frameworks.md); read the relevant platform section |
| Choosing HTTP delivery or certification for dynamic pages | [Dynamic delivery](references/delivery.md) |
| Designing an idempotent content import | [Import/read backend example](references/backend-example.md); adapt its schema and authorization |
| Exporting SQL data and converting import batches | [Data import](references/data-import.md) |
| Preserving renamed, PHP or query-string URLs | [Old URLs](references/old-urls.md) |

Load current ICP guidance from https://skills.internetcomputer.org/llms.txt when its topic becomes relevant: Motoko and persistence, CLI/deployment, static-site delivery, identity, canister security, external calls, domains, funding or cloud engines. These references provide specific examples and operational constraints; they are not a requirement to load every document before starting.

## Working constraints

- Begin with a read-only inventory and an owner-approved plan. Keep the existing service patched and available while building from copies.
- Honor the owner's existing authorization. Treat a production write freeze, traffic/DNS cutover and decommissioning as separate decisions when they are outside that authorization.
- Keep secret values and private exports out of code, reports and chat. Assess personal data and operator confidentiality before importing it.
- Track required features, gaps, the proposed destination and observable acceptance evidence. Do not silently replace working behavior with a screenshot, mock or stub.
- A working build or a successful example does not prove a particular site's plugins or workflows migrated correctly.

## 1. Inventory the actual application

Identify the platform/version, routes, data model, files, users/roles, active extensions, custom code, scheduled work and external dependencies. Check deployment configuration and schema instead of assuming default table names.

For WordPress, include network-active and must-use plugins, drop-ins, theme functions, shortcodes, dynamic blocks and custom endpoints. For Drupal, include enabled/custom modules, Views, forms, access rules, configuration and editorial workflows. Use [platform notes](references/frameworks.md) where relevant.

Observe representative journeys and record their inputs, outputs and side effects. Include anonymous and authenticated users, privileged roles, validation failures, content changes and relevant language/site variants. Trace request-time calculations and extension hooks through the code; their results are not necessarily stored in the database.

For each required capability record: source implementation and data, proposed new implementation, dependencies, current status and an acceptance check. Flag unavailable source, credentials, services or test data as evidence gaps rather than guessing.

## 2. Agree the target and evidence

Choose the frontend host and rendering model to fit the application:

- A certified static frontend can call a dynamic Motoko backend. Forms, calculations, search, editing and permissions can run through backend methods without rebuilding or upgrading the canister for each content change.
- Pre-render content only when it meets freshness, personalization and indexing requirements. Rebuild/sync published assets when that is the chosen content workflow.
- Use custom HTTP rendering when server-rendered responses or ordinary HTTP integrations require it. ICP supports dynamic HTTP and query-to-update delivery; see [dynamic delivery](references/delivery.md). A static-site recipe's file/routing limitations are not ICP-wide restrictions.
- The frontend may remain on an existing host. Record the retained host, PHP components and external services as ongoing dependencies.

Decide which extension capabilities will be rebuilt, replaced, retained or retired. Define editor/admin operations as well as public pages. Agree identity/account linking, data handling, operators/location, funding, continuity, reconciliation and rollback requirements.

Approve scope, gaps and measurable acceptance criteria before implementation. A pilot with selected plugins demonstrates those scenarios, not universal WordPress or Drupal compatibility.

## 3. Build the agreed behavior

Use the installed Motoko toolchain and current ICP guidance. The [backend example](references/backend-example.md) demonstrates content import and public reads; it is a starting point, not a full CMS or plugin system.

- Keep import-interface row types independent from stored record types so a storage migration does not accidentally change the public Candid interface. Check both populated-state compatibility and interface compatibility; do not bypass a failing check to force an upgrade.
- Preserve legacy identifiers and relationships deliberately. Use the actual key types: numeric, text/UUID or composite. The example's `Nat` keys are one schema choice.
- Apply authorization to backend operations. In local tests, confirm the anonymous principal is not a canister controller before treating an anonymous rejection test as meaningful; use an explicitly chosen development identity. Never change existing controllers without authorization. Gate migration/import endpoints, cap batches and upsert idempotently. Paginate reads and respect request/response limits.
- Reimplement calculations, form validation and state transitions with the intended transaction semantics. Account for partial failure across `await` boundaries, retries and external side effects.
- Implement the actual editing/publishing and user workflows. Imported rendered HTML is a content snapshot; it does not recreate a plugin's behavior.
- Map money, time, nulls, enums and indexes explicitly. Adapt the example rather than assuming every SQL table should become an identical map.
- Use persistence/migration checks for the installed compiler. Preserve populated state across upgrades. Re-arm scheduled work as required and test duplicate execution.
- Keep authentication and authorization distinct. Internet Identity is an available choice; retain or integrate required organizational sign-in when appropriate. Verified proof is required to link legacy accounts; persist the verified principal-to-legacy-account mapping and test access through it. Importing user records alone does not establish that mapping. Do not import password hashes for Internet Identity or embed authentication secrets in standard canister state.
- Preserve important routes and response semantics. Read [old URLs](references/old-urls.md) only where the selected static-site recipe and legacy routes require it.

## 4. Move data where required

Use an owner-approved copy/export, explicit schema mapping and bounded, repeatable imports. See [data import](references/data-import.md) for SQL/JSONL/Candid mechanics and escaping traps. Keep exports outside all served document roots. Preserve language, SEO and custom-field data through explicit schema/import/frontend mappings; collecting extra JSON keys does not migrate them.

Reconcile authoritative row counts, identifiers, relationships and file hashes. Include Unicode, nulls and other values the source actually contains. Record excluded or transformed data. Render through the original CMS when needed for a snapshot, while separately implementing its live behavior.

## 5. Validate ongoing operations

Test the agreed journeys against the old and new implementations with representative data and roles. Include the actual installed extensions, not only a clean CMS installation.

| Capability present on the source site | Observable check |
|--------------------------------------|------------------|
| Dynamic block, shortcode or Drupal View | Change underlying content and verify fresh output, filters and permissions without a code upgrade |
| Editorial workflow | Create/edit, preview, publish/unpublish and verify public visibility and denied roles |
| Form or calculated result | Valid/invalid input, expected calculation, saved state and delivery/retry outcome |
| Membership or private content | Correct account linking and access for allowed/denied users; no public cache leak |
| Commerce or external webhook | Required pricing/state transitions, authentic requests, idempotency and failure handling |
| Scheduled work | Due/not-due behavior, retries and no duplicate side effects after upgrade |

Use integrity-appropriate reads. Ordinary queries are served by a replica; use certified data or updates where a modified response would matter. Exercise the selected HTTP certification/update path through the intended gateway. Keep client HTML/scripts and signing/authorization flows protected; see [dynamic delivery](references/delivery.md).

Test a populated-state upgrade and the recovery procedure. Record failures and intentional differences. Do not claim a new end-to-end migration test from source inspection or compilation alone.

## 6. Cut over and hand over

Deploy to the agreed network/subnet/engine and establish the correct funding model. Keep a preview alongside the old service, with appropriate access protection for private data.

With the required authorization, perform any write freeze and final export/import, reconcile, switch traffic/domain routing and verify the real origin. Check account linking, forms, editor/admin work, old URLs, headers, 404 behavior and external integrations. A code rollback and a data restore solve different problems; define how writes made during transition will be reconciled.

Retain the old service for the agreed rollback window. Deliver source and exact operating commands, canister IDs/controllers, feature-map evidence, reconciliation/test results, funding/monitoring ownership, recovery steps and remaining gaps. Decommission and dispose of exports only within the owner's authorization. If deployment is blocked, complete independent work and report the blocker accurately.
