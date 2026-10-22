# Import and Public-Read Backend Example

A CMS-style backend for a migrated site: pages, news and legacy user records, with controller-only batch imports and paginated public reads. It follows `writing-motoko` (types, mixins, composition root, migration chain).

This example covers imports and public reads. It does not provide a complete editor/admin interface or replace platform plugins. Implement or retain the owner-agreed live workflows separately, then test their behavior: editing and publishing, form submissions, calculations, permissions and integrations where required. Successful imports and public reads alone do not establish that those workflows have migrated.

Tested end to end by `tests/test-backend.sh` (moc 1.14.0, core 2.6.2, icp-cli 1.7.0): imports and re-imports, refused non-controller imports, hidden unpublished rows, pagination, Unicode, an upgrade with data in place, forms, search, timers and read-back.

## Layout

```text
icp.yaml
mops.toml
src/backend/types.mo
src/backend/mixins/Import.mo
src/backend/mixins/Content.mo
src/backend/mixins/Export.mo
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

`core` was added with `mops add core`, which also writes `mops.lock`; commit both. This targets moc 1.x, where `--default-persistent-actors` makes a plain `actor` persistent; moc 2.x does so by default and drops the flag, so remove the `[moc]` args line when moving to 2.x (`mops toolchain use moc <version>`).

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
    role : { #administrator; #editor; #author; #contributor; #subscriber };
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
    role : { #administrator; #editor; #author; #contributor; #subscriber };
  };
  public type PageSummary = { slug : Text; title : Text; updatedAt : Int };

  public type ImportError = {
    #notController;
    #batchTooLarge : { max : Nat; got : Nat };
  };

  public type Counts = { pages : Nat; news : Nat; legacyUsers : Nat };

  /// Row-count cap. Callers must also bound the encoded message size.
  public type Submission = {
    id : Nat;
    kind : { #contact; #report };
    name : Text;
    email : Text;
    subject : Text; // a report's issue type
    location : ?Text; // reports only
    message : Text;
    createdAt : Int; // nanoseconds
    handled : Bool;
    legacyId : ?Nat;
  };
  public type SubmissionRow = Submission;
  public type ContactInput = { name : Text; email : Text; subject : Text; message : Text };
  public type ReportInput = { name : Text; email : Text; issueType : Text; location : Text; message : Text };
  public type FormError = { #invalid : Text; #busy };
  public type AdminError = { #notAuthorized };
  public type SearchHit = { slug : Text; title : Text; kind : { #page; #news }; snippet : Text };
  public let issueTypes : [Text] = ["Street light", "Paving", "Litter", "Nuisance", "Other"];
  /// New submissions start here; imported WordPress ones keep their post IDs.
  public let firstSubmissionId = 1_000_000;
  public let maxSubmissionsPerMinute = 60;

  /// Rows per import call. Keeps each call far below the 2 MB message limit.
  public let maxImportBatch = 500;
};
```

**Adapting the types.** `Nat` legacy keys and one WordPress `role` variant are example shapes. Keep the source's real key types and relationships (UUIDs need `Text` keys throughout rows, state, migration and method signatures) and its custom or multiple roles and capabilities; never force other platforms onto WordPress roles. Add the columns your site needs. Before the first deploy, keep each record type in `migrations/20261021_000000.mo` identical to `types.mo` (otherwise `M0170`). After go-live, change state only through a new migration (`migrating-motoko-actors`). Public method types are the canister's interface and `icp deploy` refuses a breaking change without `--yes`, so imports take their own row types (`PageRow`, `NewsRow`, `LegacyUserRow`): when `Page` gains a field, leave `PageRow` as the batch files are and fill the field in `importPages` (tested: adding `views : Nat` through a migration kept all data, and old batch files still loaded).

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
import Set "mo:core/Set";
import Principal "mo:core/Principal";
import FormsMixin "mixins/Forms";
import SearchMixin "mixins/Search";
import Types "types";
import ImportMixin "mixins/Import";
import ContentMixin "mixins/Content";
import ExportMixin "mixins/Export";

actor {
  // Stable state. Initial values come from the migration chain in migrations/.
  let pages : Map.Map<Nat, Types.Page>;
  let pageSlugs : Map.Map<Text, Nat>;
  let news : Map.Map<Nat, Types.NewsItem>;
  let legacyUsers : Map.Map<Nat, Types.LegacyUser>;
  let submissions : Map.Map<Nat, Types.Submission>;
  let formState : { var nextId : Nat; var windowStart : Int; var windowCount : Nat };
  let admins : Set.Set<Principal>;

  include ImportMixin(pages, pageSlugs, news, legacyUsers);
  include ContentMixin(pages, pageSlugs, news);
  include FormsMixin(submissions, formState, admins);
  include SearchMixin(pages, news);
  include ExportMixin(pages, news, legacyUsers, submissions);
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
  type LegacyUser = { legacyId : Nat; email : Text; displayName : Text; role : { #administrator; #editor; #author; #contributor; #subscriber } };
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

The `jobs` record is a stable field, so introducing it needs a migration supplying `{ var timerId = 0; var runs = 0 }`. Call `startJobs` after every deploy: timers never survive an upgrade (the stable run counter does), and it cancels the previous timer first, so repeated calls never stack. Keep the `Principal` import: `caller.isController()` needs it.

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

For the non-controller import check, use an identity that is not a controller: some local setups make `anonymous` one (SKILL.md, silent failure 18).
## Forms, a staff inbox and site search

Tested on mainnet, Flamingo import included; `types.mo` and `main.mo` above declare the state.

Visitors are anonymous, so the rate limit is global; validation is in the canister; only controllers grant staff access. Constants in a mixin are stable state and cannot have initializers under enhanced migration (`M0250`): keep them in `types.mo`.


## src/backend/mixins/Forms.mo

```motoko
import Map "mo:core/Map";
import Set "mo:core/Set";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import Time "mo:core/Time";
import Nat "mo:core/Nat";
import Result "mo:core/Result";
import Iter "mo:core/Iter";
import Array "mo:core/Array";
import Types "../types";

mixin (
  submissions : Map.Map<Nat, Types.Submission>,
  formState : { var nextId : Nat; var windowStart : Int; var windowCount : Nat },
  admins : Set.Set<Principal>,
) {
  func blank(t : Text) : Bool = t.trim(#char ' ').size() == 0;
  func ok(t : Text, max : Nat) : Bool = not blank(t) and t.size() <= max;
  func validEmail(e : Text) : Bool {
    if (e.size() > 200 or e.contains(#char ' ')) return false;
    let parts = e.split(#char '@').toArray();
    parts.size() == 2 and parts[0].size() > 0 and parts[1].contains(#char '.')
  };
  func admitted() : Bool {
    let now = Time.now();
    if (now - formState.windowStart > 60_000_000_000) { formState.windowStart := now; formState.windowCount := 0 };
    if (formState.windowCount >= Types.maxSubmissionsPerMinute) return false;
    formState.windowCount += 1;
    true
  };
  func store(kind : { #contact; #report }, name : Text, email : Text, subject : Text, location : ?Text, message : Text) : Nat {
    let id = formState.nextId;
    formState.nextId += 1;
    submissions.add(id, { id; kind; name; email; subject; location; message; createdAt = Time.now(); handled = false; legacyId = null });
    id
  };
  func isAdmin(p : Principal) : Bool = p.isController() or admins.contains(p);

  public shared func submitContact(input : Types.ContactInput) : async Result.Result<Nat, Types.FormError> {
    if (not ok(input.name, 100)) return #err(#invalid "name");
    if (not validEmail(input.email)) return #err(#invalid "email");
    if (not ok(input.subject, 200)) return #err(#invalid "subject");
    if (not ok(input.message, 5000)) return #err(#invalid "message");
    if (not admitted()) return #err(#busy);
    #ok(store(#contact, input.name, input.email, input.subject, null, input.message))
  };

  public shared func submitReport(input : Types.ReportInput) : async Result.Result<Nat, Types.FormError> {
    if (not ok(input.name, 100)) return #err(#invalid "name");
    if (not validEmail(input.email)) return #err(#invalid "email");
    if (Types.issueTypes.find(func(t : Text) : Bool = t == input.issueType) == null) return #err(#invalid "issueType");
    if (not ok(input.location, 200)) return #err(#invalid "location");
    if (not ok(input.message, 5000)) return #err(#invalid "message");
    if (not admitted()) return #err(#busy);
    #ok(store(#report, input.name, input.email, input.issueType, ?input.location, input.message))
  };

  public shared query ({ caller }) func whoami() : async { principal : Principal; admin : Bool } {
    { principal = caller; admin = isAdmin(caller) }
  };

  /// Newest first. Admins only.
  public shared query ({ caller }) func listSubmissions(offset : Nat, limit : Nat) : async Result.Result<[Types.Submission], Types.AdminError> {
    if (not isAdmin(caller)) return #err(#notAuthorized);
    #ok(submissions.reverseEntries().map(func((_, s) : (Nat, Types.Submission)) : Types.Submission = s).drop(offset).take(Nat.min(limit, 100)).toArray())
  };

  public shared ({ caller }) func setHandled(id : Nat, handled : Bool) : async Result.Result<(), Types.AdminError> {
    if (not isAdmin(caller)) return #err(#notAuthorized);
    let ?s = submissions.get(id) else return #ok;
    submissions.add(id, { s with handled });
    #ok
  };

  public shared ({ caller }) func addAdmin(p : Principal) : async Result.Result<(), Types.AdminError> {
    if (not caller.isController()) return #err(#notAuthorized);
    admins.add(p);
    #ok
  };
  public shared ({ caller }) func removeAdmin(p : Principal) : async Result.Result<(), Types.AdminError> {
    if (not caller.isController()) return #err(#notAuthorized);
    admins.remove(p);
    #ok
  };

  /// Flamingo import: controllers only; re-runs replace.
  public shared ({ caller }) func importSubmissions(rows : [Types.SubmissionRow]) : async Result.Result<Nat, Types.ImportError> {
    if (not caller.isController()) return #err(#notController);
    if (rows.size() > Types.maxImportBatch) return #err(#batchTooLarge({ max = Types.maxImportBatch; got = rows.size() }));
    for (r in rows.values()) submissions.add(r.id, r);
    #ok(rows.size())
  };
};
```

## src/backend/mixins/Search.mo

```motoko
import Map "mo:core/Map";
import Text "mo:core/Text";
import Char "mo:core/Char";
import Nat32 "mo:core/Nat32";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Iter "mo:core/Iter";
import Types "../types";

/// Search over published pages and news; title matches come first.
mixin (
  pages : Map.Map<Nat, Types.Page>,
  news : Map.Map<Nat, Types.NewsItem>,
) {
  func lower(t : Text) : Text = t.map(func(c : Char) : Char = if (c >= 'A' and c <= 'Z') Nat32.toChar(c.toNat32() + 32) else c);

  /// Text of an HTML fragment, tags dropped and whitespace collapsed, at most `max` characters.
  func plain(html : Text, max : Nat) : Text {
    var out = "";
    var n = 0;
    var inTag = false;
    var space = false;
    label scan for (c in html.chars()) {
      if (n >= max) break scan;
      if (c == '<') { inTag := true; space := true } else if (c == '>') { inTag := false } else if (not inTag) {
        if (c == ' ' or c == '\n' or c == '\t') { space := true } else {
          if (space and n > 0) { out #= " "; n += 1 };
          space := false;
          out #= Char.toText(c);
          n += 1;
        };
      };
    };
    out
  };

  public query func search(q : Text, limit : Nat) : async [Types.SearchHit] {
    let needle = lower(q.trim(#char ' '));
    if (needle.size() < 2 or needle.size() > 100) return [];
    let inTitle = List.empty<Types.SearchHit>();
    let inBody = List.empty<Types.SearchHit>();
    func consider(slug : Text, title : Text, kind : { #page; #news }, body : Text, summary : ?Text) {
      let text = plain(body, 1_000_000);
      let snippet = switch (summary) { case (?s) s; case null plain(body, 160) };
      if (lower(title).contains(#text needle)) inTitle.add({ slug; title; kind; snippet })
      else if (lower(text).contains(#text needle)) inBody.add({ slug; title; kind; snippet });
    };
    for (p in pages.values()) if (p.published) consider(p.slug, p.title, #page, p.bodyHtml, null);
    for (n in news.values()) if (n.publishedAt != null) consider(n.slug, n.title, #news, n.bodyHtml, n.summary);
    for (h in inBody.values()) inTitle.add(h);
    inTitle.values().take(Nat.min(limit, 50)).toArray()
  };
};
```

## src/backend/migrations/20261022_000000.mo

```motoko
import Map "mo:core/Map";
import Set "mo:core/Set";

/// Declares only the fields it adds: pages, news and users carry over untouched.
module {
  type Submission = { id : Nat; kind : { #contact; #report }; name : Text; email : Text; subject : Text; location : ?Text; message : Text; createdAt : Int; handled : Bool; legacyId : ?Nat };
  type OldActor = {};
  type NewActor = { submissions : Map.Map<Nat, Submission>; formState : { var nextId : Nat; var windowStart : Int; var windowCount : Nat }; admins : Set.Set<Principal> };
  public func migration(_ : OldActor) : NewActor {
    { submissions = Map.empty(); formState = { var nextId = 1_000_000; var windowStart = 0; var windowCount = 0 }; admins = Set.empty() }
  };
};
```

No forms or search: remove the three stable fields and two `include` lines from `main.mo`, their types, and this migration together (`M0169`), and `exportSubmissions` from `Export.mo`.



**From the pages:** bindings from `@icp-sdk/bindgen`, ids and root key via `safeGetCanisterEnv()`, results as `{ __kind__: "ok" | "err" }`; decode snippet entities as text (`DOMParser` `textContent`); staff use `new AuthClient()` (`@icp-sdk/auth@^11`) with `HttpAgent.create({ identity, rootKey })`. CSP `connect-src 'self' https://icp-api.io https://*.icp0.io https://*.icp.net`; no `unsafe-eval`.

## src/backend/mixins/Export.mo

Controller-only read-back of every stored field, 100 per call: reconcile against the source export, then keep it as the off-site backup. On the mainnet demo it caught three form messages from the migration window.

```motoko
import Map "mo:core/Map";
import Principal "mo:core/Principal";
import Iter "mo:core/Iter";
import Nat "mo:core/Nat";
import Result "mo:core/Result";
import Types "../types";

mixin (
  pages : Map.Map<Nat, Types.Page>,
  news : Map.Map<Nat, Types.NewsItem>,
  legacyUsers : Map.Map<Nat, Types.LegacyUser>,
  submissions : Map.Map<Nat, Types.Submission>,
) {
  func slice<T>(m : Map.Map<Nat, T>, offset : Nat, limit : Nat) : [T] =
    Iter.toArray(Iter.take(Iter.drop(Map.values(m), offset), Nat.min(limit, 100)));

  public shared query ({ caller }) func exportPages(offset : Nat, limit : Nat) : async Result.Result<[Types.Page], Types.AdminError> {
    if (caller.isController()) #ok(slice(pages, offset, limit)) else #err(#notAuthorized)
  };

  public shared query ({ caller }) func exportNews(offset : Nat, limit : Nat) : async Result.Result<[Types.NewsItem], Types.AdminError> {
    if (caller.isController()) #ok(slice(news, offset, limit)) else #err(#notAuthorized)
  };

  public shared query ({ caller }) func exportLegacyUsers(offset : Nat, limit : Nat) : async Result.Result<[Types.LegacyUser], Types.AdminError> {
    if (caller.isController()) #ok(slice(legacyUsers, offset, limit)) else #err(#notAuthorized)
  };

  public shared query ({ caller }) func exportSubmissions(offset : Nat, limit : Nat) : async Result.Result<[Types.Submission], Types.AdminError> {
    if (caller.isController()) #ok(slice(submissions, offset, limit)) else #err(#notAuthorized)
  };
};
```
