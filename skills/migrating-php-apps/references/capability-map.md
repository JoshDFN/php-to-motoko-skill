# Capability map: what each PHP feature becomes on ICP

Phase 2: every feature gets a row; no row means an owner decision, never a silent drop. **E2E**: tested end to end in `tests/`; **Example**: passes backend tests; **Spec**: follow the named skill, add an acceptance test.

| PHP feature | On ICP (skill; watch) | Status |
|---|---|---|
| Pages, posts, categories, tags | Prebuilt at old URLs (`static-site`) | E2E |
| Menus, page tree | From `menus.jsonl` and page parents | E2E |
| Media | Copied to old paths | E2E |
| Pretty URLs, `?p=`, `.php` | `_redirects` plus a home-page script (`old-urls.md`) | E2E |
| Search (`?s=`) | Backend `search` query | E2E |
| RSS | Static `feed.xml`, `/feed/` redirect | E2E |
| Forms (CF7, Gravity, Webform) | Validated update method, global rate limit (`canister-security`) | E2E |
| Stored submissions (Flamingo) | Imported into the inbox; select values are arrays | E2E |
| Staff area, `/wp-login.php` | Internet Identity, controller-managed `admins` (`internet-identity`) | E2E |
| Custom domain | `custom-domains`; apex needs ALIAS | E2E |
| Multilingual, SEO | One path per language; titles, sitemap from the export | Export E2E |
| Editing (`/wp-admin`) | Staff editor: Internet Identity plus update methods; rebuild on publish | Spec |
| Roles | Checked in every update method | Example |
| Cron, schedulers | Timers, re-armed after every upgrade | Example |
| User accounts | Internet Identity; link legacy accounts with proof, never hashes | Spec |
| Email | Outcall to an email API (`https-outcalls`, `vetkeys`); key secrecy, idempotency | Spec |
| Payments | Provider outcalls or ICP-native (`icrc-ledger`, `ckbtc`); owner decision | Spec |
| Catalogue, stock | Typed records; reserve before `await` | Spec |
| Comments | Visitor update method, staff moderation, rate limits | Spec |
| Uploads | Chunked: 2 MB per message (`multi-canister`) | Spec |
| Bookings, capacity | Check and reserve in one call | Spec |
| Memberships | Internet Identity plus records; billing is an owner decision | Spec |
| Third-party APIs | Outcalls (replicas must agree) or the browser | Spec |
| Incoming webhooks | `http_request_update`, verify signatures (`delivery.md`) | Spec |
| Per-request pages | Prebuilt, browser-rendered or `upgrade = true` (`delivery.md`) | Spec |
| Analytics | Backend counts, or the owner's script | Spec |
| Secrets in config | vetKeys-encrypted or off-chain; one owner decision each | Spec |
| Real-time | Polling, or a separate service | Spec |

No row fits: describe it for users, check nearby rows and `https://skills.internetcomputer.org/llms.txt`, write the acceptance test, offer options.
