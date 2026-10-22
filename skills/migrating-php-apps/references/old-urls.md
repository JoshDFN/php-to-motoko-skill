# Keeping Old URLs Working

Search engines, bookmarks, printed letters and other sites link to the old URLs. Decide each URL's fate in this order, cheapest first. Results below were checked with `http_request` calls against a deployed `@dfinity/static-site@v0.4.0` canister.

| Old URL | Technique | Result |
|---------|-----------|--------|
| `/afval`, `/nieuws/12` (pretty URL, same path kept) | Build the page at the old path: `dist/afval.html`, `dist/nieuws/12.html` | `200`, no redirect needed |
| `/oud-afval` (path renamed) | Exact rule in `_redirects`: `/oud-afval  /afval  301` | `301`, `Location: /afval` |
| `/index.php?page=afval`, `/news.php?id=12` | Rewrite the script path to a mapping page | `200` with the mapping page; its script sends the browser on |
| anything else | `404.html` at the root of `dir` | `404` with your page |

Why not one rule per query string: `_redirects` matches the path only (no query-string conditions) and has no `:splat` or `:placeholder` captures, because every response must be certified ahead of time.

## dist/_redirects

```text
# Renamed page: exact path, permanent redirect
/oud-afval    /afval        301
# Old script URLs: query strings cannot be matched here, so serve the mapping page
/index.php    /legacy.html  200
/news.php     /legacy.html  200
```

Put `_redirects` and `_headers` in the folder your build copies into `dir` (Vite: `public/`), or they are absent at deploy time.

## dist/legacy.html and dist/legacy.js

The script is a separate file so it works under a `script-src 'self'` Content-Security-Policy.

```html
<!doctype html><meta charset="utf-8"><title>Doorsturen…</title>
<script src="/legacy.js"></script>
<noscript><a href="/">Ga naar de homepage</a></noscript>
```

```javascript
// Old PHP URLs carried their meaning in the query string, which _redirects cannot match.
// Map them in the browser. Generated from the export; keep it in sync with the data.
(function () {
  var q = new URLSearchParams(location.search);
  var routes = {
    "/index.php": function () { var p = q.get("page"); return !p || p === "home" ? "/" : "/" + encodeURIComponent(p); },
    "/news.php": function () { var id = q.get("id"); return id ? "/nieuws/" + encodeURIComponent(id) : "/"; }
  };
  var to = (routes[location.pathname] || function () { return "/"; })();
  location.replace(to);
})();
```

Query-string URLs on a path that is now a real page (WordPress plain permalinks such as `/?p=123` and `/?page_id=5` land on `/`, which serves `index.html`) never reach a rule: real files win. Put the same mapping logic at the top of that page instead.

## Generating exact rules from the export

When paths change (new slugs, new section names), generate the rules from the exported data instead of writing them by hand:

```bash
python3 - <<'EOF' >> dist/_redirects
import json
for line in open("export/news.jsonl", encoding="utf-8"):
    row = json.loads(line)
    if row.get("publishedAt") is None:
        continue  # unpublished: no public URL to keep
    print(f"/nieuws/{row['legacyId']}  /news/{row['slug']}  301")
EOF
```

Rules are matched top to bottom, after real files and the automatic clean-URL rules; keep a SPA catch-all (`/*  /index.html  200`) last.

## Testing every old URL

Run the access-log URL list (SKILL.md, Phase 1) through the deployed frontend and check each status:

```bash
for u in /nieuws/12 /oud-afval "/index.php?page=afval" /bestaat-niet; do
  echo -n "$u -> "
  icp canister call frontend http_request "(record { url = \"$u\"; method = \"GET\"; body = vec {}; headers = vec {}; certificate_version = opt 2 })" --query \
    | grep -a -o 'status_code = [0-9]*'
done
```

Response bodies are printed as escaped blobs; use `grep -a`. Then repeat the important ones in a real browser on the live domain, where the mapping page's script runs.
