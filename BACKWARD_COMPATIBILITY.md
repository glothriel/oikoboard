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

A breaking change must say who is affected, how they migrate, and how it is rolled back.
