# Exporting, Converting and Importing the Data

The source author reports an end-to-end MariaDB 10.11 export, conversion and local import with icp-cli 1.7.0, followed by reconciliation and a populated-state upgrade, including accents, emoji, quotes, tabs, backslashes, newlines and NULLs. That run was not repeated for this revision. The revised converter has local fixture checks for escaping, numeric validation, timestamp precision and bounded batches; these do not establish a database-to-canister round trip.

## 1. Back up first

Run the backup and export commands from a private working directory outside every served document root. Restrict access to its files; never copy the directory into frontend assets.

```bash
DB_USER=readonly_user   # a database account that can only read
DB_NAME=app_db          # the PHP app's database
mysqldump --single-transaction --routines --default-character-set=utf8mb4 -u "$DB_USER" -p "$DB_NAME" > "backup-$(date +%F).sql"
```

This file is a recovery input. It can contain personal data: store it like production data, verify the restore procedure, and dispose of it only under the owner's retention policy and authorization.

## 2. Export one table per file as JSON lines

MySQL 5.7.8+ and MariaDB 10.2.3+ have `JSON_OBJECT`. Name the JSON keys exactly like the Motoko record fields, so the converter needs no mapping.

```bash
db() { mysql --default-character-set=utf8mb4 --batch --raw --skip-column-names -u "$DB_USER" -p "$DB_NAME" "$@"; }
mkdir -p export

db -e "SET time_zone = '+00:00';
  SELECT JSON_OBJECT('legacyId', id, 'slug', slug, 'title', title, 'bodyHtml', body,
                     'published', published, 'updatedAt', UNIX_TIMESTAMP(updated_at))
  FROM pages ORDER BY id;" > export/pages.jsonl

db -e "SET time_zone = '+00:00';
  SELECT JSON_OBJECT('legacyId', id, 'slug', slug, 'title', title, 'summary', summary, 'bodyHtml', body,
                     'publishedAt', UNIX_TIMESTAMP(published_at), 'authorLegacyId', author_id)
  FROM news ORDER BY id;" > export/news.jsonl

# Identity data only: never select password hashes, tokens or secrets
db -e "SELECT JSON_OBJECT('legacyId', id, 'email', LOWER(TRIM(email)), 'displayName', display_name, 'role', role)
  FROM users ORDER BY id;" > export/users.jsonl
```

- `--raw` is mandatory. Without it the client escapes backslashes, tabs and newlines again: in testing, one row became unparseable and another parsed with corrupted text.
- `SET time_zone` must name the zone the PHP app **wrote** `DATETIME` values in (php.ini `date.timezone`, `date_default_timezone_set`). `+00:00` is right only if the app wrote UTC. `TIMESTAMP` columns are stored in UTC and convert correctly whatever the session zone.
- `TINYINT(1)` booleans arrive as `0`/`1`; the converter's `bool` type accepts both forms.
- Double-encoded text (`Ã©` where `é` belongs) means UTF-8 bytes were stored in a `latin1` column. Repair it in the `SELECT`, then spot-check: `CONVERT(CAST(CONVERT(title USING latin1) AS BINARY) USING utf8mb4)`.
- Columns holding serialized PHP (`a:2:{...}`) must be decoded before conversion; see `frameworks.md` (WordPress).

**PostgreSQL** (same idea; not part of the tested run, so check the first lines of each file):

```bash
psql -At -d "$DB_NAME" -c "SELECT row_to_json(t) FROM (
  SELECT id AS \"legacyId\", slug, title, body AS \"bodyHtml\", published,
         EXTRACT(EPOCH FROM updated_at) AS \"updatedAt\"
  FROM pages ORDER BY id) t" > export/pages.jsonl
```

Do not use `COPY ... TO STDOUT` in text format for this: it escapes backslashes in the JSON again.

Check every export before converting: `wc -l` against `SELECT COUNT(*)`, and `python3 -c "import json,sys; [json.loads(l) for l in open(sys.argv[1])]" export/pages.jsonl`.

## 3. Convert to Candid batch files

`jsonl_to_candid.py` (stdlib only) writes `PREFIX-0001.did`, `PREFIX-0002.did`, ... each holding one call's argument, `(vec { record { ... }; ... })`. Defaults: at most 500 rows and 1 MB of text per file including its Candid envelope, matching `maxImportBatch` in the backend and staying far below the 2 MB message limit. It fails with the file, line and field when a field is missing or a non-optional field is NULL. Fractional identifiers are rejected; decimal epoch values retain precision through nanosecond conversion (sub-nanosecond values round half to even). A single oversized record is rejected for explicit chunking/schema review.

```python
#!/usr/bin/env python3
"""Turn one exported table (JSON lines) into Candid argument files for a batch import method.

Usage:
  python3 jsonl_to_candid.py IN.jsonl OUT_PREFIX field:type [field:type ...] [--max-rows N] [--max-bytes N]

Types: nat, int, text, bool, time (Unix seconds -> Int nanoseconds), variant (text -> tag),
       and opt:<type> for nullable columns (opt:text, opt:nat, opt:time, ...).
Writes OUT_PREFIX-0001.did, OUT_PREFIX-0002.did, ... each holding `(vec { record {...}; ... })`.
Stdlib only. Fails loudly on missing fields or NULLs in non-opt fields, naming the line.
"""
import json, re, sys
from decimal import Decimal, InvalidOperation, ROUND_HALF_EVEN

KEYWORDS = {"type", "import", "opt", "vec", "record", "variant", "func", "service", "oneway",
            "query", "composite_query", "blob", "principal", "text", "null", "reserved", "empty",
            "bool", "nat", "int", "float32", "float64", "true", "false"}
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

def text(s):
    out = []
    for ch in s:
        o = ord(ch)
        if ch == "\\": out.append("\\\\")
        elif ch == '"': out.append('\\"')
        elif ch == "\n": out.append("\\n")
        elif ch == "\r": out.append("\\r")
        elif ch == "\t": out.append("\\t")
        elif o < 0x20 or o == 0x7F: out.append("\\u{%x}" % o)
        else: out.append(ch)
    return '"' + "".join(out) + '"'

def label(name):
    return name if IDENT.match(name) and name not in KEYWORDS else text(name)

def value(v, ty, where):
    if ty.startswith("opt:"):
        return "null" if v is None else "opt (" + value(v, ty[4:], where) + ")"  # parens: `opt 5 : nat` is a type error
    if v is None:
        raise ValueError(f"{where}: NULL in non-optional field (use opt:{ty})")
    if ty == "text":
        return text(str(v))
    if ty == "bool":
        if v in (True, 1, "1", "true", "TRUE"): return "true"
        if v in (False, 0, "0", "false", "FALSE"): return "false"
        raise ValueError(f"{where}: not a boolean: {v!r}")
    if ty in ("nat", "int"):
        try:
            n_decimal = Decimal(str(v))
        except (InvalidOperation, ValueError):
            raise ValueError(f"{where}: not an integer: {v!r}")
        if isinstance(v, bool) or not n_decimal.is_finite() or n_decimal != n_decimal.to_integral_value():
            raise ValueError(f"{where}: not an integer: {v!r}")
        n = int(n_decimal)
        if ty == "nat" and n < 0: raise ValueError(f"{where}: negative value for nat: {n}")
        return f"{n} : {ty}"
    if ty == "time":  # Unix seconds (int or decimal string) -> Int nanoseconds, like Time.now()
        try:
            seconds = Decimal(str(v))
        except (InvalidOperation, ValueError):
            raise ValueError(f"{where}: not a finite epoch value: {v!r}")
        if not seconds.is_finite(): raise ValueError(f"{where}: not a finite epoch value: {v!r}")
        nanos = int((seconds * 1_000_000_000).to_integral_value(rounding=ROUND_HALF_EVEN))
        return f"{nanos} : int"
    if ty == "variant":
        tag = str(v)
        if not IDENT.match(tag): raise ValueError(f"{where}: {tag!r} is not a valid variant tag")
        return "variant { " + label(tag) + " }"
    raise ValueError(f"unknown type {ty!r}")

def main(argv):
    args, max_rows, max_bytes = [], 500, 1_000_000
    it = iter(argv)
    for a in it:
        if a == "--max-rows": max_rows = int(next(it))
        elif a == "--max-bytes": max_bytes = int(next(it))
        else: args.append(a)
    if len(args) < 3: sys.exit(__doc__)
    src, prefix, specs = args[0], args[1], [s.split(":", 1) for s in args[2:]]
    envelope = len("(vec {\n  ".encode()) + len("\n})\n".encode())
    if max_rows < 1 or max_bytes <= envelope: raise ValueError("Batch limits must be positive and leave room for the Candid envelope")
    batches, cur, size = [], [], envelope
    with open(src, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            if not line.strip(): continue
            row = json.loads(line, parse_float=Decimal)
            fields = []
            for name, ty in specs:
                if name not in row: raise ValueError(f"{src}:{n}: missing field {name!r}")
                fields.append(f"{label(name)} = {value(row[name], ty, f'{src}:{n}:{name}')}")
            rec = "record { " + "; ".join(fields) + " }"
            b = len(rec.encode("utf-8"))
            if envelope + b > max_bytes:
                raise ValueError(f"{src}:{n}: one record exceeds --max-bytes; review chunking or the import schema")
            separator = 4 if cur else 0
            if cur and (len(cur) >= max_rows or size + separator + b > max_bytes):
                batches.append(cur); cur, size, separator = [], envelope, 0
            cur.append(rec); size += separator + b
    if cur: batches.append(cur)
    for i, recs in enumerate(batches, 1):
        with open(f"{prefix}-{i:04d}.did", "w", encoding="utf-8") as out:
            out.write("(vec {\n  " + ";\n  ".join(recs) + "\n})\n")
    print(f"{src}: {sum(map(len, batches))} rows -> {len(batches)} batch file(s) {prefix}-*.did")

if __name__ == "__main__":
    main(sys.argv[1:])
```

```bash
set -euo pipefail
# Run each conversion in a fresh private working directory. Refuse to reuse old batches.
mkdir -m 700 batches
python3 jsonl_to_candid.py export/pages.jsonl batches/pages \
  legacyId:nat slug:text title:text bodyHtml:text published:bool updatedAt:time
python3 jsonl_to_candid.py export/news.jsonl batches/news \
  legacyId:nat slug:text title:text summary:opt:text bodyHtml:text publishedAt:opt:time authorLegacyId:opt:nat
python3 jsonl_to_candid.py export/users.jsonl batches/users \
  legacyId:nat email:text displayName:text role:variant
touch batches/.complete
```

Run this conversion block as one Bash script. If `batches` already exists, use a new private working directory for the new export rather than merging output files. The converter does not remove old batch files: reusing a prefix after a smaller export could otherwise import stale rows. The completion marker is written only after all three conversions succeed; do not create it manually after an error.

Candid text rules the converter follows (both caused real failures before they were handled):

- An annotation inside an option needs parentheses: `opt (1555011000000000000 : int)`. `opt 1555011000000000000 : int` fails with `type mismatch`.
- Text escapes: `\\`, `\"`, `\n`, `\r`, `\t`; other control characters as `\u{..}`. Non-ASCII UTF-8 is written as is.

## 4. Import

Save this as `import_batches.py`. It processes the three tables in order and stops the entire run on a command failure, an application-level `err`, malformed output or an unexpected result shape. The `icp-cli` 1.7.0 flags `--output candid --json` return a JSON envelope with a `response_candid` string; see the [official output implementation](https://github.com/dfinity/icp-cli/blob/v1.7.0/crates/icp-cli/src/call_output.rs). A returned application error does not by itself make the CLI exit unsuccessfully.

```python
#!/usr/bin/env python3
import json, os, re, subprocess, sys
from pathlib import Path

environment = os.environ.get("MIGRATION_ENV")
if not environment:
    sys.exit("Set MIGRATION_ENV to the approved target environment.")
batch_dir = Path("batches")
if not (batch_dir / ".complete").is_file():
    sys.exit("Batch conversion is incomplete; review and regenerate before importing.")
groups = [("pages", "importPages"), ("news", "importNews"), ("users", "importLegacyUsers")]
work = [(path, method) for prefix, method in groups for path in sorted(batch_dir.glob(f"{prefix}-*.did"))]
if not work:
    sys.exit("No batch files found; check the export counts before continuing.")
success = re.compile(r"\(\s*variant\s*\{\s*ok\s*=\s*([0-9]+(?:_[0-9]+)*)\s*:\s*nat\s*;?\s*\}\s*,?\s*\)")
for path, method in work:
    result = subprocess.run(
        ["icp", "canister", "call", "backend", method, "--args-file", str(path),
         "-e", environment, "--output", "candid", "--json"],
        text=True, capture_output=True,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        sys.exit(f"Stopped at {path}: CLI exit {result.returncode}.")
    try:
        reply = json.loads(result.stdout)["response_candid"]
    except (ValueError, KeyError, TypeError):
        sys.exit(f"Stopped at {path}: missing or malformed Candid JSON output.")
    match = success.fullmatch(reply) if isinstance(reply, str) else None
    if not match:
        sys.exit(f"Stopped at {path}: rejected or unexpected import result: {reply!r}")
    print(f"{path}: imported {int(match.group(1).replace('_', ''))} rows")
```

```bash
export MIGRATION_ENV=local   # change to ic only for the approved production target
python3 import_batches.py
```

The success check is deliberately specific to this example's `Result<Nat, ImportError>` interface. If you change that interface or CLI output format, update and test the decoder before importing. A zero-row source table generates no batch files; reconcile its source count separately. Because imports upsert by legacy id, rerun the driver with the same completed batch set after fixing a failure. Generate a new, separate batch directory for a new export.

## 5. Reconcile

```bash
icp canister call backend importCounts '()' --query -e "$MIGRATION_ENV"
# compare each number with SELECT COUNT(*) FROM <table> (respecting any WHERE used in the export)
icp canister call backend getPage '("english")' --query -e "$MIGRATION_ENV"   # a row with accents, emoji, quotes, tabs, backslashes
sha256sum uploads/2019/*.pdf                                     # compare with the migrated copies
```

Write the numbers into the hand-over evidence. A mismatch is investigated, never rounded away.

## 6. Final delta at cutover

After the write freeze, either rerun the full export, convert and import (simplest, safe because imports upsert), or export only rows changed since the rehearsal (`WHERE updated_at > '<last export time>'`) if the table has a reliable change column. Rows deleted in PHP since the rehearsal need an explicit delete method or a full rebuild of that table; decide which before the freeze. Reconcile again, then snapshot the backend.
