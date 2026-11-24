# Backward compatibility

Surfaces other parties depend on. A change to any of them needs a migration or compatibility path, stated in the PR, and is reviewed as high impact. Derived from the current repository.

| Surface | Where | Rule |
|---|---|---|
| Database schema | `server/migrations/` (goose, embedded) | Applied migrations are immutable; changes are new numbered migrations with a down. Existing data must survive (e.g. backfill defaults). |
| REST API | `server/internal/app`, `server/internal/modules/*` | Shipped endpoints, fields and status codes keep their meaning; additions are optional. The released Android app can be older than the server. |
| Realtime protocol | `changes` feed, WebSocket views (`docs/backend-realtime.md`) | Message shapes and entity types stay readable by older clients; a new entity type needs its trigger and view. |
| Auth / OAuth | `server/internal/core/oauth.go`, `docs/auth.md` | Issuer, token format, scopes and redirect URI rules (loopback port ignored per RFC 8252) stay valid for connected clients. |
| MCP tools | `server/internal/mcp`, `docs/mcp.md` | Tool names, arguments and result shapes used by external agents keep working. |
| Environment configuration | `OIKO_*` vars in `server/cmd/oikoboard/main.go`, `docker-compose.yml` | Existing variables keep their names and defaults; removing one needs a deprecation. |
| Stored files and device data | file storage, cached avatars/attachments in the app | Existing stored data stays readable after an upgrade. |
| Translations | `app/lib/l10n/*.arb` | Keys already used are not renamed or removed without updating both languages. |

## Policy

- **A newer server must support the current and the previous major app version.** An app update is never a precondition for upgrading the server, and the Android app cannot be force-updated instantly.
- **Deprecation**: a behaviour is deprecated for at least one major app release before it is removed. The PR that deprecates it says so, and the PR that removes it names the app version it ships in.
- A breaking change must say who is affected, how they migrate, and how it is rolled back.
- Explicit API versioning, the code layout for it and an enforced compatibility check are tracked in #45; until they land, every change to a surface above is additive.

## Compatibility matrix

| App major version | Server | Status |
|---|---|---|
| current | current | supported |
| previous | current | supported (policy above) |
| older than previous | current | not guaranteed |

The matrix gets concrete version numbers once the app and server are versioned independently (#45).
