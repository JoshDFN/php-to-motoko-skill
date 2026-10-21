# Dynamic delivery and response integrity

Read this when the application needs request-time HTTP rendering, webhooks, ordinary HTTP APIs or an explicit certification policy. A certified static frontend with Motoko API calls remains a useful default. Its file-generation and redirect constraints do not prohibit dynamic applications on ICP.

## Choose delivery per behavior

| Requirement | Candidate design | Verify |
|-------------|------------------|--------|
| Forms, editing, calculations or search in an application UI | Certified frontend assets calling Motoko methods | Correct state changes, input validation, permissions and integrity-appropriate reads |
| Public content with an accepted publishing delay | Pre-render/rebuild assets or maintain certified response data as content changes | Freshness and invalidation; content changes need not require a code upgrade |
| Fresh server-rendered HTTP output | Custom HTTP canister using certified queries where suitable or query-to-update delivery | Routing, authentication, latency, cost, caching and actual gateway behavior |

The HTTP gateway first calls `http_request`. Returning `upgrade = opt true` asks it to call `http_request_update` with the original request except `certificate_version`; the gateway discards the initial response fields and uses the update response. This is a request upgrade to replicated execution, not a deployment or code upgrade. Measure its latency and resource use for the workload. Application authentication and authorization still need an explicit design. Later stream chunks fetched through queries need their own integrity treatment.

For query responses, bind the response and the relevant request inputs to a supported certification policy. Treat method, query parameters, headers and request body according to the chosen policy and application semantics. Do not assume a certified response to one request is safe for another.

The protocol defines a language-independent canister interface. SDK convenience libraries vary: confirm the selected Motoko or Rust package implements the required certification version and mode. Test successful and tampered responses through the intended gateway before promising the architecture works. The static-site recipe certifies all served responses; adding custom dynamic or skipped responses requires a custom HTTP implementation or separate canister, not a header rule.

## Explicit certification opt-out

Response certification v2 already supports:

```text
IC-CertificateExpression: default_certification(ValidationArgs{no_certification:Empty{}})
```

A valid certificate and tree witness must authorize that expression for the exact or wildcard path. A replica cannot create a valid opt-out for an otherwise protected path by adding this header. Once the canister has authorized the skip policy, a replica can change the response body, status and headers for that path. The content is unverified; the permission to skip is certified. This policy is path-scoped, so do not treat method, query or body variations at that path as protected exceptions.

The Rust convenience skip helper uses a root wildcard; do not copy it as an exact-route policy. `no_request_certification` is a different mode: it preserves response certification while removing request binding.

Use an opt-out only when the owner accepts the impact of arbitrary content at that path. Classify impact by how the route is used, including direct navigation, redirects, MIME types and its origin's authority. Low-value data on a sign-in application's origin is not automatically benign: it may become executable content. Keep application HTML, scripts, sign-in, permission decisions and transaction/signing flows protected. An honest backend's authorization checks do not stop altered frontend code from requesting an unintended action with an authorized session.

Do not silently introduce skip policies or raw URLs to make a migration pass. Agree a narrow route policy and test that protected routes remain protected, including after upgrades. If unverified content is necessary, review an origin and authority boundary that makes arbitrary content genuinely benign.

## Primary specifications and implementation

- [HTTP gateway protocol: expressions and update delivery](https://docs.internetcomputer.org/references/http-gateway-protocol-spec/)
- [Response certification guide](https://docs.internetcomputer.org/guides/frontends/certification/)
- [Certified skip-policy helper and semantics](https://github.com/dfinity/response-verification/blob/88dd491ec78c088223e6e3d81848a7b7274950c0/packages/ic-http-certification/src/utils/skip_certification.rs)
- [Internet Identity specification: client application security](https://docs.internetcomputer.org/references/internet-identity-spec/)
- [Official Motoko query-to-update example](https://github.com/dfinity/response-verification/blob/88dd491ec78c088223e6e3d81848a7b7274950c0/examples/http-certification/upgrade-to-update-call/src/motoko-backend/main.mo)
