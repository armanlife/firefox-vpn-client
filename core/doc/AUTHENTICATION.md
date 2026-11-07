# Authentication, Credentials, and Renewal

Read [architecture](ARCHITECTURE.md) for call boundaries and [sessions](SESSIONS.md) for the effect of renewal on open streams.

## Credential types

| Credential | Used by | Source and storage |
| --- | --- | --- |
| Firefox Account password | User-initiated sign-in | Stored encrypted for **Sign in again** |
| FxA session token | HAWK-authenticated sign-in steps and OAuth issuance | Created by sign-in; process memory only |
| OAuth access token | Guardian API requests | FxA response; `user-data/accounts/<id>/credentials.json` |
| OAuth refresh token | FxA refresh grant | Issued with offline access; stored with the access token |
| Guardian ProxyPass | Fastly CONNECT `Proxy-Authorization` | Guardian response; process memory |
| Fastly challenge cookies | Challenged account-API calls | Shared control-plane cookie jar, process memory |
| Dashboard password | Dashboard login | bcrypt hash in `config.json`; sessions in memory |

These values are not interchangeable. A ProxyPass update does not imply an OAuth refresh, and successful OAuth refresh does not prove a target CONNECT succeeded.

## Sign-in and account flow

Accounts are added from the dashboard ([DASHBOARD.md](DASHBOARD.md)) or with `-add-account` on the terminal. The dashboard sign-in (`signin_flow.go`) runs in the background and asks the person for input when FxA needs it:

| FxA situation | Step | API used |
| --- | --- | --- |
| Password accepted, session unverified (default) | `need_email_code` | `POST /session/verify_code` |
| Account with two-step authentication | `need_totp` | `POST /session/verify/totp` |
| Confirmation by link (legacy servers) | `need_email_link` | none; the person confirms they opened it |
| Sign-in blocked as unusual (errno 125) | `need_unblock_code` | `POST /account/login/send_unblock_code`, then login with `unblockCode` |
| Fastly image CAPTCHA during any call | `need_captcha` | answered inside the challenge solver through `fxa.WithCaptchaSolver` |
| Email typed in another letter case than the account's (errno 120) | none | login again with the email the error names, and the typed one as `originalLoginEmail` |

The password's key stretching uses the email exactly as the account has it, so FxA refuses another letter case and names the account's own spelling; `fxa.Login` repeats the sign-in once with it, as Firefox does, and the account is stored under that spelling (`fxa.SignedInEmail`). Email and authenticator verification allow up to five rejected codes. Network errors, HTTP 406 challenge failures, and temporary server errors keep the same code prompt open for another submission within the 15-minute sign-in deadline. The terminal `-add-account` supports email codes and confirmation links only.

An account can also come from a browser sign-in (`POST /signin/browser`): the app's webview shows accounts.firefox.com as Firefox desktop's sync sign-in (`context=fx_desktop_v3&service=sync`) and captures the session token from the page's `fxaccounts:login` WebChannel message, with every code and CAPTCHA handled in the page itself. The page sends that message right after the password, before any code the sign-in asks for, so the app hands the token over at once and keeps the page open. The core (`startBrowser` in `signin_flow.go`) asks `GET /recovery_email/status` (`fxa.SessionVerified`) every 3 seconds until FxA reports the session confirmed, then exchanges the token (`fxa.OAuthToken`, retried briefly while FxA still answers errnos 104 and 138); the app closes the page once that sign-in has finished, and cancels it when the page is closed first. The account is stored without a password, so signing it in again goes through the browser too. The webview reaches the pages through the core's sign-in proxy (`POST /signin/browser/proxy`, `internal/signinproxy`), which connects the way the core's own account requests do, with no account and the VPN off; the app sets it with WebView2's `--proxy-server` on Windows, androidx.webkit's `ProxyController` on Android, and `WKWebsiteDataStore.proxyConfigurations` on macOS 14 and later (on earlier macOS the page connects by itself).

After verification, `fxa.OAuthToken` issues offline OAuth credentials, the account is stored (an existing account with the same email is updated and becomes ready), its quota is read, and the account manager reloads. The temporary session token is discarded.

Each account's credentials are loaded by `AccountPool.AuthFor` and refreshed by `FreshRuntimeAuth`/`refreshRuntimeAuth` (`internal/proxy`); refreshed credentials are written back to that account's own file through `runtimeAuth.persist`.

[internal/fxa](../internal/fxa/fxa.go) owns password derivation and HAWK signing (`hawk.go`), `fxa.Login`, `fxa.LoginWithUnblockCode`, `fxa.SendUnblockCode`, `fxa.VerifySession`, `fxa.VerifyTOTP`, `fxa.OAuthToken`, `fxa.RefreshToken`, and `fxa.RegisterDevice`. OAuth issuance uses the FxA credentials grant with `access_type=offline`; refresh uses `grant_type=refresh_token`. When refresh returns no replacement refresh token, the existing one is preserved.

Defaults and relevant paths:

| Service | Endpoint / path |
| --- | --- |
| FxA base | `https://api.accounts.firefox.com/v1` |
| OAuth | `/oauth/token` relative to that base |
| OAuth authorization code | `/oauth/authorization` relative to that base |
| OAuth token fallback | `https://oauth.accounts.firefox.com/v1/token` |
| Guardian base | `https://vpn.mozilla.org`, `network.guardian_endpoint` in `config.json` |
| Guardian pass | `GET /api/v1/fpn/token` |
| Guardian quota | `HEAD /api/v1/fpn/token` (headers only, no pass minted) |
| Guardian status | `GET /api/v1/fpn/status` |
| Guardian activation | `POST /api/v1/fpn/activate` |

Every Guardian request sends `Authorization: Bearer`, `Content-Type: application/json`, and `Cache-Control: max-age=0` (fetch's no-cache mode), as Firefox's `GuardianClient` does. Every control-plane request also carries desktop Firefox's `User-Agent` and `Accept: */*` (`controlplane.ApplyFirefoxHeaders`).

[internal/guardian/guardian.go](../internal/guardian/guardian.go) parses the pass and quota headers. A non-200 answer is a `guardian.HTTPError` whose `errors.Is` classification follows Firefox's `GuardianClient.toError`:

| Status | Sentinel(s) | Meaning / CLI handling |
| --- | --- | --- |
| 401 | `ErrTokenInvalid` | OAuth access token refused; refresh it |
| 403 | `ErrTokenInvalid`, `ErrNotEntitled` | Valid token, no proxy entitlement; activate the account |
| 429 | `ErrQuotaExceeded` | Quota spent; `RetryAfter` and quota usage are carried when sent |
| 451 | `ErrRegionUnavailable` | Guardian refuses the requesting region; not retried |
| 5xx | `ErrServer` | Transient; retried with backoff |

`guardian.IsTransient`, `guardian.RetryAfter`, and `guardian.UsageFromError` expose these properties to the CLI. FxA rejections of a stored refresh or session token (HTTP 400/401/403, except errno 107) match `ErrReauthRequired`. Preserve typed errors and `errors.Is`/`errors.As` behavior when changing API parsing.

## Stored credentials

Each account keeps its OAuth credentials in `user-data/accounts/<id>/credentials.json` (fields `access_token`, `refresh_token`, `scope`, `obtained_at`, `expires_in`, and `password`), written through `securefile.WritePrivate`: temporary file in the same folder, owner-only permissions on POSIX, write/close, rename, and a replacement fallback that can remove the old file before a retry. On Windows the file inherits the data folder's ACL.

Direct sign-in saves the Firefox Account password for the user-initiated **Sign in again** action ([password.go](../internal/accounts/password.go)): `password` is `v1:` plus base64 of an AES-256-GCM nonce and ciphertext, under a random key in `user-data/accounts/secret.key`. This keeps it out of plain sight; anyone with the whole data folder can decrypt it. Saving refreshed tokens keeps the password (`writeCredentialsLocked`). The API never returns it; `GET /accounts` only reports `has_password`.

A rejected refresh token or a refreshed access token still refused by Guardian marks the account for **Sign in again**. The dashboard can reuse a saved password only when the user chooses that action. Background renewal uses existing OAuth credentials.

### Connected services name

`AccountPool.EnsureDevice` registers a device record named "Firefox's built-in VPN" (type `desktop`) with `POST /v1/account/device`, authenticated with the account's refresh token, which is how the Mozilla account's connected services page lists this program. Firefox's own built-in VPN takes its token through the signed-in Firefox (`fxAccounts.getOAuthToken`, scope `profile` and `vpn`) with the same Firefox client ID this program uses. The record is made once per refresh token (`device_id` and a token fingerprint in `account.json`, written with `Store.SaveDevice`; the account manager saves only its own fields with `Store.SaveState`, so it never erases the record): at sign-in and at startup for accounts without one. When FxA refuses the refresh token there (for example after the entry was removed from connected services), the account is marked for **Sign in again**. The only active account can continue until its current access token stops working. Other failures are logged and change nothing else. A Guardian 401 in the quota check renews at once too.

A completed sign-in ends its session token with `fxa.DestroySession` (`POST /v1/session/destroy`) once the OAuth tokens exist. The program needs only the refresh token; a session left alive appeared in connected services as a second entry named "unknown" next to "Firefox's built-in VPN". OAuth tokens are separate from the session in FxA (Firefox itself destroys its session and its OAuth tokens separately when signing out). Entries named "unknown" left by earlier versions can be signed out on the connected services page.

`runtimeAuth.accessTokenValid` applies a two-minute margin. Loading credentials keeps their acquisition time; it never resets the access-token lifetime.


Ordinary development does not need real credentials. Tests use temporary HOME/USERPROFILE and data folders with synthetic credentials. Do not include account secrets or response bodies in reports.

## ProxyPass and claim times

`ProxyPassInfo` holds the raw pass, decoded claims, raw and parsed quota metadata (`Usage`, `UsageErr`), the local receipt time, and the claim-time correction. The client decodes JWT claims for timing but does not verify their cryptographic signature; the upstream validates acceptance. `aud` may be a string or an array.

`anchorProxyPassClaims` follows Firefox (bug 2054514): when the claims disagree with the local clock by more than one minute, the pass is treated as valid from the moment it was received for its claimed lifetime (`exp - nbf`, or `exp - iat` without `nbf`). While the clocks agree, the raw claims are used, which never extends a pass beyond its signed expiry. A pass without `exp`, or whose `exp` is not after its start claim, is rejected. Use `ProxyPassInfo.ExpiresAt()` and `NotBefore()` rather than duplicating raw claim-time conversion; a change here affects both admission and renewal scheduling.

`ProxyUsage` parses quota headers like Firefox: `X-Quota-Unlimited: true` needs nothing else; otherwise `X-Quota-Limit`, `X-Quota-Remaining`, and `X-Quota-Reset` (RFC 3339, or Unix seconds) must all be present, non-negative, and consistent. Invalid headers leave `Usage` nil without rejecting the pass.

## Renewal call path

```text
RunRenewalLoop
  -> nextRenewalDelay
  -> renewWithTimeout
  -> renew / renewLocked under renewMu (context cancelled at the watchdog deadline)
  -> acquireUsablePass
       -> AccountPool.AcquirePass (account selection and failover; MULTI-ACCOUNT.md)
            -> FreshRuntimeAuth (refresh when the access token is near expiry)
            -> fetchProxyPassCtx (bounded retry) / guardian.FetchProxyPass
            -> recoverGuardianRejection: refresh on 401, activate on 403
  -> adoptPass
       -> updateCurrentSessionToken, or sessionFactory + swapSession
```

| Timing | Current constant / behavior |
| --- | --- |
| ProxyPass lead | `proxyPassRenewLead`: two minutes before expiry |
| Minimum spacing of successful renewals | `minRenewalInterval`: 10 seconds |
| Guardian pass fetch retry | 500 ms doubling backoff inside `guardianRetryBudget` (30 seconds), only for transport errors and HTTP 5xx; `Retry-After` is honored when it fits |
| Retry after a transient renewal failure | `proxyPassRetryDelay`: 30 seconds (longer when `Retry-After` asks) |
| Retry after a terminal renewal failure | `terminalRenewalRetryDelay`: 15 minutes; spent quota waits for `X-Quota-Reset` (capped at six hours) |
| Renewal watchdog | `PassRenewTimeout`: two minutes, then `proxyPassRenewAbandonGrace`: 30 seconds |
| Runtime OAuth lead | `oauthRefreshLead`: two minutes |
| Quota reading | From the quota headers of every pass request (about every 8 minutes), as Firefox does; once the last reading plus the tunnel traffic since then is within 5 GiB of the switch threshold (whether or not another account can take over), also a `HEAD` request after every 512 MiB of tunnel traffic |

OAuth refresh is reached through the authentication/pass lifecycle; there is no separate periodic OAuth refresh timer.

`renewWithTimeout` runs the renewal with a context that is cancelled at the watchdog deadline, so FxA, challenge, and Guardian calls stop. A timed-out renewal is recorded as an ordinary failure and retried; if the cancelled worker returns with a success after all, that counts. A worker that has not returned after the abandon grace is reported as stuck (status `renewal_failed`), and the loop waits for it before the next renewal: the process never exits, since on Android it carries the phone's VPN and on a desktop the system proxy points at it. The Fastly challenge solver, the usual long wait, gives up when its caller's context ends. `proxy.connect_timeout` is not this watchdog.

Terminal failures are reported, not hammered: `reauth_required` (FxA rejected the stored credential), `region_unavailable` (HTTP 451), `not_entitled`, `quota_exhausted`, and `no_usable_account` back off as listed above (the last one until the earliest quota reset). The failure code and next attempt time are written to the status file.

## Recovery and quota

Startup, renewal, quota checks, and manual account switches all obtain passes through `AccountPool.AcquirePass`; tests that build a controller without an account pool exercise the same recovery through `acquireUsablePass` with one fixed auth.

- HTTP 401 triggers an OAuth refresh; HTTP 403 (also after a refresh) triggers Guardian activation (`recoverGuardianRejection`).
- Transient network/server failures and HTTP 451 return without trying other accounts, because every account would fail the same way.
- Quota at the switch threshold, HTTP 429, a spent quota, an FxA sign-in requirement, or a persistent Guardian rejection move to the next usable account; see [MULTI-ACCOUNT.md](MULTI-ACCOUNT.md).
- The quota monitor reads usage with `HEAD` and only fetches a pass when the active account must hand over. When a user clicks **Refresh quota** and Guardian refuses `HEAD` with HTTP 403, the service tries the normal pass `GET` once and reads only the quota headers. The current tunnel keeps its pass.
- A CONNECT HTTP 429 is a transport-level error observation; it does not alone trigger immediate session reconstruction.

Do not infer live quota-exhaustion behavior from parsing quota headers. The historical live run observed quota values but did not deliberately exhaust an account.

## Challenge and timeout boundaries

[internal/controlplane](../internal/controlplane/client.go) owns a shared 30-second HTTP client and cookie jar. Configure `controlplane.SetTransport` before requests start. This client is distinct from data-plane sessions.

Control-plane and challenge requests set `Accept-Encoding: identity`. In live HTTP/1.1 tests against Mozilla's token endpoint, Go's automatic `gzip` header received HTTP 406, while `identity` reached FxA for both the sign-in and refresh grants. Challenge probes on the website and API responses are evaluated separately.

OAuth issuance, PKCE authorization/code exchange, and refresh requests share the native Firefox OAuth header profile: JSON-preferred `Accept`, `Accept-Language: en-US, en`, `Content-Type: application/json; charset=utf-8`, `Cache-Control: no-cache`, `Pragma: no-cache`, `Sec-Fetch-Dest: empty`, `Sec-Fetch-Mode: no-cors`, `Sec-Fetch-Site: none`, and `Priority: u=4`. The same profile is retained when retrying a grant or using the alternate OAuth endpoint. The common Firefox User-Agent, TLS profile, `identity` encoding, and the separate Guardian and challenge request profiles are unchanged.

When the account API returns HTTP 406 during refresh, the core first tries Mozilla's published OAuth token endpoint once with the same refresh grant. Both endpoints use the same refresh tokens. If the OAuth endpoint is unreachable or also returns 406, the original account-API challenge flow runs. A confirmed invalid refresh token (OAuth HTTP 400, errno 108) requires reauthentication.

When the Hawk-signed token exchange in the app or dashboard's direct sign-in returns HTTP 406, the core retries the same grant over HTTP/2 with the Firefox TLS profile. This retry uses the default control-plane route and shares the original recovery budget. It runs after the initial 406 and can run again after the first solve. A transport error or another 406 leaves the existing recovery available.

The core can also use the same verified session to request an authorization code with S256 PKCE and a fresh state value. After matching the returned state, it exchanges the code and verifier at Mozilla's OAuth token endpoint. If either step of the alternate grant returns HTTP 406, both grants share one challenge recovery budget. After each solve, the core retries the original token request first and tries the alternate grant again if the original still returns 406. Other FxA errors retain their codes for the sign-in flow. This keeps email, TOTP, and unblock verification in the existing sign-in flow. Only the authorization request carries the session's Hawk credential in the alternate grant.

[challenge.go](../internal/fxa/challenge.go) handles account-API HTTP 406 challenges, PoW/PAT, and challenge cookies. The CLI and runtime token refresh limit the first HTTP attempt of each FxA call to 15 seconds. After the first 406, the fallback, up to five challenge solves, and their API retries share a 90-second budget. Each solve may take up to 60 seconds within that budget. The caller's operation deadline and cancellation still apply. Every successful solve is followed by a retry if the budget permits, including the fifth.

`Fastly challenge page probe passed` records the challenge page's host, task types, rounds, and duration. The separate `FxA API retry returned HTTP …` line records the original request's method, host, path, and response status. A cleared challenge page alone does not establish acceptance at the API endpoint.

Solved challenge cookies are installed for the account API, its root path, the alternate OAuth origin (`oauth.accounts.firefox.com`), and the sign-in site. Retries at either token endpoint can then carry the solved cookie; it is not copied to Guardian or unrelated hosts.

The solver reads the challenge script's initialization arguments as JSON and checks the asset prefix against the path it fetched. The legacy regular expression remains a fallback for flat calls with JavaScript comments after the prefix. Neither parser executes the script.

Do not disable production TLS validation to work around a challenge or local interception. Test-only certificate configurations must remain local to tests.

## Relevant tests

- `TestAccountPool*`, `TestDashboardSignInWithEmailCode`: account failover and the dashboard sign-in flow.
- `TestLoginWithUnblockCodeSendsCode`, `TestVerifyTOTPReportsRejectedCode`, `TestAnswerChallengeAsksCaptchaSolver`: unblock codes, TOTP, and CAPTCHA answers.
- `TestLoginCorrectsTheEmailCase`: an email in another letter case is signed in with the account's own spelling.
- `TestNewFxaAPIErrorParsesErrno`: typed account error parsing.
- `TestAnchorProxyPassClaims*`, `TestFetchProxyPassSendsNoCacheAndAnchorsExpiry`: Guardian claim-time anchoring.
- `TestHTTPErrorClassifiesStatus`, `TestParseProxyUsage`, `TestFxaAPIErrorClassifiesReauthRequired`: status, quota, and sign-in classification.
- `TestFetchProxyPassRetriesTransientGuardianFailure`, `TestAcquireUsablePassActivatesOnNotEntitledWithoutRefresh`, `TestRenewalRetryDelayBacksOffTerminalFailures`: retry and recovery policy.
- `TestWritePrivateReplacesContentAndTightensPermissions`: credential file replacement and permissions.
- `TestAuditSOCKSConnectAndRenewal`: controlled automatic expired-access refresh, pass renewal, saved response, and stream preservation for H2/H3.
- `TestLiveOAuthRefresh`: explicit real-account refresh and Guardian acceptance, only with authorization and opt-in.
