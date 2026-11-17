# Sign-in, households and invites

Code: `server/internal/core/{auth,google,households,mock_oauth}.go`, `app/lib/core/{session,login_screen,onboarding_screen}.dart`,
`app/lib/core/api/http_auth_api.dart`.

## Model

```
users ──< identities (provider, subject)      account = a person who signs in
  └──< members >── households                 member = a person in a family (may have no account, e.g. a child)
          invite_email                         member waiting for an account with this e-mail
sessions (token_hash, user_id, member_id?)    member_id = the selected household
invites  (token_hash, household_id, member_id?, expires_at, used_at)
auth_flows                                     OAuth flows in progress (≤ 15 min): sign-in and calendar connect
```

- Accounts are matched by `(provider, subject)`, not e-mail. One account can be in several households.
- Signing in with a **verified** e-mail attaches the account to members waiting for it (`invite_email`).
- Tokens (sessions, invites, codes) are stored only as SHA-256; provider credentials are encrypted (`OIKO_SECRET_KEY`).

## Google sign-in (OIDC: authorization code + PKCE)

All OAuth is done by the backend; the app never sees the client secret.

```
app    → GET /auth/google/start?return=<app url>&challenge=S256(verifier)
           backend: return URL allowed? store auth_flows, state cookie → 302 Google
Google → GET /auth/google/callback?state&code
           backend: state == cookie, code exchange (PKCE), id_token checks → account
           → 302 <app url>?code=<one-time>   (or ?error=)
app    → POST /auth/exchange {code, verifier} → {token}
```

- Web: the page goes to Google and back; the verifier survives in localStorage. Android: Custom Tab via
  `flutter_web_auth_2`, returning to `oikoboard://auth`.
- The code is useless without the app's verifier and is burned on the first failed attempt.
- Connecting a Google Calendar reuses this callback as a separate flow started and finished by the signed-in app —
  see [calendar.md](calendar.md).

MCP clients (ChatGPT, Claude…) sign in through the same flow as part of their OAuth authorization — see
[mcp.md](mcp.md#oauth-chatgpt-claude).

## Households and invites

An account without a household sees "create a household / have an invite?". Invites are one-time, valid 7 days,
for a new person or an existing member without an account (a child signs in and takes over "Kuba"). Link:
`<app url>?invite=<token>`; opened before signing in, it is remembered until after sign-in.

Module, view and WebSocket endpoints require a household (`403 no_household`, WS close 4001).

## Dev sign-in

- `OIKO_DEV_LOGIN=1`: `POST /auth/dev/login {email}` — any e-mail, no verification.
- `OIKO_MOCK_OAUTH=1`: `/auth/google/start` shows a "who are you?" page (existing accounts, members without an
  account, any e-mail) instead of Google; the rest of the flow is real, so invites and the app work unchanged.
  Calendar connects create a mock account.

Both only for local development.

## Configuration

| Variable | Meaning |
|---|---|
| `OIKO_GOOGLE_CLIENT_ID`, `OIKO_GOOGLE_CLIENT_SECRET` | OAuth "Web application" client; without them Google is off |
| `OIKO_PUBLIC_URL` | public API URL (default `http://localhost:8090`), the callback is derived from it; also the OAuth issuer / MCP resource |
| `OIKO_RETURN_URLS` | allowed return URLs, comma-separated (default localhost, 127.0.0.1, `oikoboard://auth`) |
| `OIKO_APP_URL` | web app URL, for invite links created on Android |
| `OIKO_SECRET_KEY` | 32 bytes (base64/hex) encrypting stored credentials; required for Google Calendar |

## Google Cloud Console

1. Google Auth Platform → Branding, Audience **External**, publishing status **In production** (unverified is fine
   for a family; in *Testing* calendar refresh tokens expire after 7 days).
2. Data access: `openid`, `email`, `profile`, `calendar.events`, `calendar.calendarlist.readonly`;
   APIs & Services → enable **Google Calendar API**.
3. Clients → Web application, redirect URI `http://localhost:8090/api/v1/auth/google/callback`
   (+ `https://<host>/api/v1/auth/google/callback` when deployed).

Google only redirects to `localhost` or a real HTTPS domain. Android emulator: `adb reverse tcp:8090 tcp:8090`.
