# Import and Public-Read Backend Example

A CMS-style backend for a migrated site: pages, news and legacy user records, with controller-only batch imports and paginated public reads. It follows `writing-motoko` (types, mixins, composition root, migration chain).

This example covers imports and public reads. It does not provide a complete editor/admin interface or replace platform plugins. Implement or retain the owner-agreed live workflows separately, then test their behavior: editing and publishing, form submissions, calculations, permissions and integrations where required. Successful imports and public reads alone do not establish that those workflows have migrated.

Source-author validation report: `mops check --fix` with moc 1.14.0 and core 2.6.2; deployed with icp-cli 1.7.0 to a local network; batch imports, a repeated import (counts unchanged), a non-controller import (rejected), unpublished rows (hidden), pagination, a Unicode round-trip and an upgrade with data in place (counts unchanged). The author also reports compilation with moc 2.0.0 (`--enhanced-migration src/backend/migrations`). The merged example has a fresh local moc 1.14.0/core 2.6.2 compilation check; those runtime tests were not rerun for this revision.

## Layout

```text
icp.yaml
mops.toml
src/backend/types.mo
src/backend/mixins/Import.mo
src/backend/mixins/Content.mo
src/backend/main.mo
src/backend/migrations/20261021_000000.mo
dist/                      # static frontend (see old-urls.md)
```

## icp.yaml

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

## mops.toml

```toml
[toolchain]
moc = "1.14.0"

[moc]
args = [ "--default-persistent-actors" ]

[canisters.backend]
main = "src/backend/main.mo"

[canisters.backend.migrations]
chain = "src/backend/migrations"

[dependencies]
core = "2.6.2"
```

`core` was added with `mops add core`, which also writes `mops.lock`; commit both. This file targets moc 1.x, where `--default-persistent-actors` lets a plain `actor` be persistent. On moc 2.x actors are persistent by default and that flag no longer exists: remove the `[moc]` args line when you move the toolchain to 2.x (`mops toolchain use moc <version>`).

## src/backend/types.mo

```motoko
module {
  /// One row of the legacy `pages` table, exactly as the importer sends it.
  public type Page = {
    legacyId : Nat;
    slug : Text;
    title : Text;
    bodyHtml : Text;
    published : Bool;
    updatedAt : Int; // nanoseconds since 1970-01-01 UTC, the same unit as Time.now()
  };

  public type NewsItem = {
    legacyId : Nat;
    slug : Text;
    title : Text;
    summary : ?Text;
    bodyHtml : Text;
    publishedAt : ?Int;
    authorLegacyId : ?Nat;
  };

  /// Identity data only. Password hashes are never imported.
  public type LegacyUser = {
    legacyId : Nat;
    email : Text; // lower-cased at export
    displayName : Text;
    role : { #admin; #editor };
  };

  /// The import interface is independent of the stored types above. After go-live, keep these
  /// records compatible with existing batch files and map new stored fields in the import methods.
  public type PageRow = {
    legacyId : Nat;
    slug : Text;
    title : Text;
    bodyHtml : Text;
    published : Bool;
    updatedAt : Int;
  };

  public type NewsRow = {
    legacyId : Nat;
    slug : Text;
    title : Text;
    summary : ?Text;
    bodyHtml : Text;
    publishedAt : ?Int;
    authorLegacyId : ?Nat;
  };

  public type LegacyUserRow = {
    legacyId : Nat;
    email : Text;
    displayName : Text;
    role : { #admin; #editor };
  };
  public type PageSummary = { slug : Text; title : Text; updatedAt : Int };

  public type ImportError = {
    #notController;
    #batchTooLarge : { max : Nat; got : Nat };
  };

  public type Counts = { pages : Nat; news : Nat; legacyUsers : Nat };

  /// Row-count cap. Callers must also bound the encoded message size.
  public let maxImportBatch = 500;
};
```

**Adapting the types.** Change `role` to the platform's own roles (WordPress: `administrator`, `editor`, `author`, `contributor`, `subscriber`) and add the columns your site needs. Before the first deploy, keep the copy of each record type in `migrations/20261021_000000.mo` identical to `types.mo`; if they differ, the compiler reports `M0170` (stable variable not compatible). After go-live, change state only through a new migration (`migrating-motoko-actors`). A type that appears in a public method's signature is part of the canister's interface: `icp deploy` runs a Candid compatibility check and refuses a breaking change unless you pass `--yes`. That is why the import methods take their own row types (`PageRow`, `NewsRow`, `LegacyUserRow`): when `Page` gains a field, leave `PageRow` as the batch files are and fill the new field in `importPages` (tested: adding `views : Nat` to `Page` through a migration kept all data, and the old batch files kept loading once the row type stayed unchanged).

## src/backend/mixins/Import.mo

```motoko
import Map "mo:core/Map";
import Nat "mo:core/Nat";
import Text "mo:core/Text";
import Principal "mo:core/Principal";
import Result "mo:core/Result";
import Types "../types";

mixin (
  pages : Map.Map<Nat, Types.Page>,
  pageSlugs : Map.Map<Text, Nat>,
  news : Map.Map<Nat, Types.NewsItem>,
  legacyUsers : Map.Map<Nat, Types.LegacyUser>,
) {
  // Only canister controllers (the identity that deploys) may import.
  func rejectImport(caller : Principal, size : Nat) : ?Types.ImportError {
    if (not caller.isController()) return ?#notController;
    if (size > Types.maxImportBatch) return ?#batchTooLarge({ max = Types.maxImportBatch; got = size });
    null
  };

  // Every import upserts by legacyId, so re-sending a batch after a failure is harmless.
  public shared ({ caller }) func importPages(rows : [Types.PageRow]) : async Result.Result<Nat, Types.ImportError> {
    switch (rejectImport(caller, rows.size())) { case (?e) { return #err(e) }; case null {} };
    for (row in rows.values()) {
      switch (pages.get(row.legacyId)) {
        case (?old) { if (old.slug != row.slug) { pageSlugs.remove(old.slug) } };
        case null {};
      };
      pages.add(row.legacyId, row);
      pageSlugs.add(row.slug, row.legacyId);
    };
    #ok(rows.size())
  };

  public shared ({ caller }) func importNews(rows : [Types.NewsRow]) : async Result.Result<Nat, Types.ImportError> {
    switch (rejectImport(caller, rows.size())) { case (?e) { return #err(e) }; case null {} };
    for (row in rows.values()) { news.add(row.legacyId, row) };
    #ok(rows.size())
  };

  public shared ({ caller }) func importLegacyUsers(rows : [Types.LegacyUserRow]) : async Result.Result<Nat, Types.ImportError> {
    switch (rejectImport(caller, rows.size())) { case (?e) { return #err(e) }; case null {} };
    for (row in rows.values()) { legacyUsers.add(row.legacyId, row) };
    #ok(rows.size())
  };

  /// Compare these with SELECT COUNT(*) on the old database after every import run.
  public query func importCounts() : async Types.Counts {
    { pages = pages.size(); news = news.size(); legacyUsers = legacyUsers.size() }
  };
};
```

## src/backend/mixins/Content.mo

```motoko
import Map "mo:core/Map";
import Nat "mo:core/Nat";
import Text "mo:core/Text";
import Iter "mo:core/Iter";
import Types "../types";

mixin (
  pages : Map.Map<Nat, Types.Page>,
  pageSlugs : Map.Map<Text, Nat>,
  news : Map.Map<Nat, Types.NewsItem>,
) {
  public query func getPage(slug : Text) : async ?Types.Page {
    let ?id = pageSlugs.get(slug) else return null;
    let ?page = pages.get(id) else return null;
    if (page.published) ?page else null
  };

  /// Published pages in legacy-id order. Paginated: one response must stay under 2 MB.
  public query func listPages(offset : Nat, limit : Nat) : async [Types.PageSummary] {
    pages.values()
      .filter(func p = p.published)
      .drop(offset)
      .take(Nat.min(limit, 100))
      .map(func p = { slug = p.slug; title = p.title; updatedAt = p.updatedAt })
      .toArray()
  };

  public query func getNews(legacyId : Nat) : async ?Types.NewsItem {
    let ?item = news.get(legacyId) else return null;
    if (item.publishedAt == null) null else ?item
  };
};
```

## src/backend/main.mo

```motoko
import Map "mo:core/Map";
import Types "types";
import ImportMixin "mixins/Import";
import ContentMixin "mixins/Content";

actor {
  // Stable state. Initial values come from the migration chain in migrations/.
  let pages : Map.Map<Nat, Types.Page>;
  let pageSlugs : Map.Map<Text, Nat>;
  let news : Map.Map<Nat, Types.NewsItem>;
  let legacyUsers : Map.Map<Nat, Types.LegacyUser>;

  include ImportMixin(pages, pageSlugs, news, legacyUsers);
  include ContentMixin(pages, pageSlugs, news);
};
```

## src/backend/migrations/20261021_000000.mo

The first migration gives every stable field its initial value. Later changes to stable state follow `migrating-motoko-actors` (new timestamped file; never edit an applied one).

```motoko
import Map "mo:core/Map";

module {
  type Page = { legacyId : Nat; slug : Text; title : Text; bodyHtml : Text; published : Bool; updatedAt : Int };
  type NewsItem = {
    legacyId : Nat;
    slug : Text;
    title : Text;
    summary : ?Text;
    bodyHtml : Text;
    publishedAt : ?Int;
    authorLegacyId : ?Nat;
  };
  type LegacyUser = { legacyId : Nat; email : Text; displayName : Text; role : { #admin; #editor } };
  type OldActor = {};
  type NewActor = {
    pages : Map.Map<Nat, Page>;
    pageSlugs : Map.Map<Text, Nat>;
    news : Map.Map<Nat, NewsItem>;
    legacyUsers : Map.Map<Nat, LegacyUser>;
  };

  public func migration(_ : OldActor) : NewActor {
    { pages = Map.empty(); pageSlugs = Map.empty(); news = Map.empty(); legacyUsers = Map.empty() };
  };
};
```

## Scheduled jobs (replacing cron)

The source author reports compiling this timer example with moc 2.0.0 and testing it on a local network; those timer tests were not rerun for this revision. The `jobs` record is a stable field, so introducing it needs a migration that supplies `{ var timerId = 0; var runs = 0 }`. Call `startJobs` after every deploy: timers never survive an upgrade (the run counter does, because it is stable), and `startJobs` cancels the previous timer first, so repeated calls never stack timers. Keep the `Principal` import: `caller.isController()` needs it.

```motoko
import Timer "mo:core/Timer";
import Principal "mo:core/Principal";

actor {
  let jobs : { var timerId : Nat; var runs : Nat };

  func nightly() : async () { jobs.runs += 1 };

  /// Controller-only. Safe to call again after every deploy: it cancels the old timer first.
  public shared ({ caller }) func startJobs() : async () {
    if (not caller.isController()) return;
    Timer.cancelTimer(jobs.timerId);
    jobs.timerId := Timer.recurringTimer<system>(#seconds(86_400), nightly);
  };
};
```

## Deploy and smoke-test locally

```bash
mops install
icp network start -d
icp deploy
icp canister call backend importCounts '()' --query
```

For the non-controller import check, use a caller that is not listed as a canister controller. Some local setups include the anonymous principal as a controller; an anonymous call then legitimately passes the controller check and does not test rejection. Use a separate non-controller test identity instead.
