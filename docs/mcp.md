# MCP and OAuth (ChatGPT, Claude…)

A person can connect their own AI chat (ChatGPT, Claude…) to the family's todos and calendar: the server exposes an
MCP endpoint (`/mcp`) and is the OAuth authorization server for it. The app's "Czat AI (MCP)" screen shows the URL to
add as a connector and the member's connected apps.

Code: `server/internal/mcp/` (tools), `server/internal/core/oauth.go` (authorization server), migration
`00009_oauth.sql`; app `app/lib/core/ai/`.

## Tools

`/mcp` (streamable HTTP, stateless) accepts **OAuth access tokens**; the actor is the member who connected the app
(`family` returns them as `me`) and changes are recorded as theirs. Tools are task-oriented and resolve people, lists and calendars by name; dates are
`YYYY-MM-DD`, times `YYYY-MM-DDTHH:MM` in the household timezone (`households.timezone`):

`family` (today, people, lists, calendars) · `list_todos` · `add_todo` · `update_todo` · `delete_todo` · `agenda` ·
`create_event` · `update_event` · `delete_event`.

Tools call the **REST API in-process** with the caller's token, so writes use the same handlers, validation and
change feed as the app, and reads use the same views. `core.ToolAllowed` limits OAuth tokens to module data and view
snapshots — no household management, invites, calendar connections or account settings.

## OAuth (ChatGPT, Claude…)

The server is the OAuth 2.1 authorization server the MCP authorization spec expects (`core/oauth.go`,
migration `00009_oauth.sql`):

```
client → POST /mcp                         → 401 WWW-Authenticate: Bearer resource_metadata=…
       → GET /.well-known/oauth-protected-resource/mcp     {resource: <public>/mcp, authorization_servers}
       → GET /.well-known/oauth-authorization-server       endpoints, S256, DCR
       → POST /oauth/register                              dynamic client registration (RFC 7591), or
                                                           client_id = https URL of a metadata document (CIMD)
browser→ GET /oauth/authorize?…&code_challenge             request stored → regular sign-in (Google / mock)
       → /oauth/continue                                   consent page: the app, the household (if several)
       → POST /oauth/consent                               → redirect_uri?code&state&iss
client → POST /oauth/token                                 code + PKCE → access (1 h) + refresh (90 days, rotated)
```

- Sign-in reuses the app's sign-in flow (`auth_flows`), returning to `/oauth/continue` with the server's own PKCE.
  The consent form is bound to the browser (cookie + one-time token).
- A consent creates a **grant** (client, member); codes and tokens hang off it. The app lists the member's grants
  (avatar menu → "Czat AI (MCP)") and deleting one revokes everything. A member who leaves the household
  loses access.
- Redirect URIs must be `https` (or `http` on localhost). Tokens are stored as SHA-256 only.
- CIMD documents are fetched from public addresses only (the URL comes from the caller), cached in `oauth_clients`
  for an hour; only public clients (PKCE, no secret). DCR clients may be public or have a secret.
- Clients need the server on **public HTTPS**; `OIKO_PUBLIC_URL` is the issuer and the resource (without it they are
  derived from each request — fine locally, not behind a proxy).

## Configuration

`OIKO_PUBLIC_URL` — the public HTTPS URL, used as the OAuth issuer and MCP resource; ChatGPT/Claude need it.

A chat-bot assistant (Hermes on Telegram, configured from the app) was prototyped and dropped in favour of this.
