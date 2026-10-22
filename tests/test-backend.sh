#!/usr/bin/env bash
# The documented Motoko backend, built from references/backend-example.md alone, on a local ICP network.
# Needs: icp (icp-cli), mops, python3, node. The local network launcher is downloaded by icp-cli on first use.
source "$(dirname "$0")/lib.sh"
need icp mops python3 node
P="$WORK/backend"; project_from_docs "$P"

section "type-checks and compiles"
(cd "$P" && timeout 600 mops install >/dev/null 2>&1 && timeout 600 mops check > "$WORK/mops-check.log" 2>&1) && ok "mops check (pinned toolchain)" || { fail "mops check"; cat "$WORK/mops-check.log"; }
if command -v moc >/dev/null 2>&1; then
  core=$(ls -d "$P"/.mops/core@*/src | head -1)
  (cd "$P/src/backend" && moc --package core "$core" --enhanced-migration=migrations -c main.mo -o "$WORK/main.wasm" >/dev/null 2>&1) && ok "compiles with $(moc --version | head -1)" || fail "moc compile"
fi

section "deploy, import the fixture, reconcile"
mkdir -p "$P/export" && cp "$FIXTURES"/export/*.jsonl "$P/export/" && convert_exports "$P"
net_start "$P" && deploy "$P" backend && ok "deployed on a local network" || fail "deploy"
import_all "$P" "$P/batches" > "$WORK/import.log"; assert_eq "pages import returns ok 4" "$(grep -c 'ok = 4' "$WORK/import.log")" "1"
c=$(counts "$P"); assert_eq "counts: pages" "$(count_of "$c" pages)" "4"; assert_eq "counts: news" "$(count_of "$c" news)" "3"; assert_eq "counts: users" "$(count_of "$c" legacyUsers)" "2"
page=$(call "$P" backend getPage '("english")' --query | tr -s ' \n' ' ')
assert_contains "Unicode round-trip" "$page" 'Résidents & visitors – Ünïcode ✓ 🚲'
assert_contains "tabs, quotes and backslashes survive" "$page" 'tabs\\tand backslashes \\\\ here'
assert_eq "unpublished page stays hidden" "$(call "$P" backend getPage '("concept-beleid")' --query | tr -d '\n ')" "(null)"

section "re-runs are idempotent"
import_all "$P" "$P/batches" >/dev/null; c2=$(counts "$P"); assert_eq "counts unchanged after a second import" "$c2" "$c"

section "access control (pitfall 18: hand the canister to a named identity first)"
icp identity new dev --storage plaintext >/dev/null 2>&1 || true; icp identity new stranger --storage plaintext >/dev/null 2>&1 || true
DEV=$(icp identity list | awk '/ dev /{print $2}')
(cd "$P" && icp canister settings update backend --add-controller "$DEV" -e local >/dev/null 2>&1 && icp canister settings update backend --remove-controller 2vxsx-fae -e local --identity dev >/dev/null 2>&1) && ok "canister handed to 'dev', anonymous removed" || fail "hand-over"
assert_contains "a non-controller import is refused" "$(call "$P" backend importPages --args-file "$P/batches/pages-0001.did" --identity stranger)" "notController"
assert_contains "an anonymous import is refused" "$(call "$P" backend importPages --args-file "$P/batches/pages-0001.did" --identity anonymous)" "notController"
assert_eq "no data changed" "$(counts "$P")" "$c"

section "upgrade keeps the data"
deploy "$P" backend --identity dev && assert_eq "counts after upgrade" "$(counts "$P")" "$c" || fail "upgrade"

section "scheduled jobs (the timer snippet)"
python3 - "$P" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); m = (p / "src/backend/main.mo").read_text()
m = m.replace('import Map "mo:core/Map";', 'import Map "mo:core/Map";\nimport Timer "mo:core/Timer";\nimport Principal "mo:core/Principal";', 1)
m = m.replace("  let legacyUsers : Map.Map<Nat, Types.LegacyUser>;\n", """  let legacyUsers : Map.Map<Nat, Types.LegacyUser>;
  let jobs : { var timerId : Nat; var runs : Nat };
  func nightly() : async () { jobs.runs += 1 };
  public shared ({ caller }) func startJobs() : async () {
    if (not caller.isController()) return;
    Timer.cancelTimer(jobs.timerId);
    jobs.timerId := Timer.recurringTimer<system>(#seconds(2), nightly);
  };
  public query func jobRuns() : async Nat { jobs.runs };
""", 1); (p / "src/backend/main.mo").write_text(m)
g = p / "src/backend/migrations/20261021_000000.mo"; s = g.read_text()
s = s.replace("    legacyUsers : Map.Map<Nat, LegacyUser>;\n  };", "    legacyUsers : Map.Map<Nat, LegacyUser>;\n    jobs : { var timerId : Nat; var runs : Nat };\n  };", 1)
s = s.replace("legacyUsers = Map.empty() };", "legacyUsers = Map.empty(); jobs = { var timerId = 0; var runs = 0 } };", 1); g.write_text(s)
PY
# the jobs field is new stable state: a fresh canister replays the chain, so reinstall the data too
(cd "$P" && icp canister stop backend -e local --identity dev >/dev/null 2>&1; icp canister delete backend -e local --identity dev >/dev/null 2>&1; rm -f .icp/data/mappings/local.ids.json)
deploy "$P" backend && import_all "$P" "$P/batches" >/dev/null
call "$P" backend startJobs '()' >/dev/null; sleep 7; r1=$(call "$P" backend jobRuns '()' --query | tr -d '() :nat\n')
[ "${r1:-0}" -ge 2 ] && ok "timer ran $r1 times in 7 s" || fail "timer did not run (runs=$r1)"
call "$P" backend startJobs '()' >/dev/null; call "$P" backend startJobs '()' >/dev/null; sleep 6; r2=$(call "$P" backend jobRuns '()' --query | tr -d '() :nat\n')
[ $((r2 - r1)) -le 4 ] && ok "re-arming does not stack timers (+$((r2 - r1)) in 6 s)" || fail "timers stacked (+$((r2 - r1)))"
deploy "$P" backend; r3=$(call "$P" backend jobRuns '()' --query | tr -d '() :nat\n'); sleep 5; r4=$(call "$P" backend jobRuns '()' --query | tr -d '() :nat\n')
assert_eq "timer stops at an upgrade until startJobs runs again" "$r4" "$r3"; [ "$r3" -ge "$r2" ] && ok "the stable run counter survived the upgrade" || fail "counter lost"

section "post-go-live migration: add a field to Page, old batch files keep loading"
python3 - "$P" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p / "src/backend/types.mo"; s = t.read_text()
s = s.replace("    updatedAt : Int; // nanoseconds since 1970-01-01 UTC, the same unit as Time.now()\n", "    updatedAt : Int; // nanoseconds since 1970-01-01 UTC, the same unit as Time.now()\n    views : Nat;\n", 1)
# PageRow stays the old shape; the import fills the new field
s = s.replace("  public type PageRow = Page;", "  public type PageRow = { legacyId : Nat; slug : Text; title : Text; bodyHtml : Text; published : Bool; updatedAt : Int };", 1); t.write_text(s)
i = p / "src/backend/mixins/Import.mo"; m = i.read_text()
m = m.replace("pages.add(row.legacyId, row);", "pages.add(row.legacyId, { row with views = 0 });", 1); i.write_text(m)
roles = "{ #administrator; #editor; #author; #contributor; #subscriber }"
(p / "src/backend/migrations/20261021_120000.mo").write_text(f'''import Map "mo:core/Map";
module {{
  type OldPage = {{ legacyId : Nat; slug : Text; title : Text; bodyHtml : Text; published : Bool; updatedAt : Int }};
  type NewPage = {{ legacyId : Nat; slug : Text; title : Text; bodyHtml : Text; published : Bool; updatedAt : Int; views : Nat }};
  type NewsItem = {{ legacyId : Nat; slug : Text; title : Text; summary : ?Text; bodyHtml : Text; publishedAt : ?Int; authorLegacyId : ?Nat }};
  type LegacyUser = {{ legacyId : Nat; email : Text; displayName : Text; role : {roles} }};
  type Jobs = {{ var timerId : Nat; var runs : Nat }};
  type OldActor = {{ pages : Map.Map<Nat, OldPage>; pageSlugs : Map.Map<Text, Nat>; news : Map.Map<Nat, NewsItem>; legacyUsers : Map.Map<Nat, LegacyUser>; jobs : Jobs }};
  type NewActor = {{ pages : Map.Map<Nat, NewPage>; pageSlugs : Map.Map<Text, Nat>; news : Map.Map<Nat, NewsItem>; legacyUsers : Map.Map<Nat, LegacyUser>; jobs : Jobs }};
  public func migration(old : OldActor) : NewActor {{
    {{ pages = old.pages.map<Nat, OldPage, NewPage>(func(_id, pg) {{ {{ pg with views = 0 }} }}); pageSlugs = old.pageSlugs; news = old.news; legacyUsers = old.legacyUsers; jobs = old.jobs }};
  }};
}};
''')
PY
grep -q "pages.add(row.legacyId, { row with views = 0 })" "$P/src/backend/mixins/Import.mo" || echo "  (note: Import.mo add line differs from the expected text; the migration test may need updating)"
(cd "$P" && timeout 600 mops check > "$WORK/mops-check2.log" 2>&1) && ok "new version type-checks" || { fail "type-check after migration"; cat "$WORK/mops-check2.log"; }
deploy "$P" backend && ok "upgraded through the migration chain (no --yes needed)" || fail "upgrade with migration"
assert_eq "data kept" "$(count_of "$(counts "$P")" pages)" "4"
assert_contains "new field present with its default" "$(call "$P" backend getPage '("english")' --query | tr -s ' \n' ' ')" "views = 0"
assert_contains "old batch files still load" "$(call "$P" backend importPages --args-file "$P/batches/pages-0001.did")" "ok = 4"
net_stop "$P"; summary
