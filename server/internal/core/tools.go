package core

import (
	"net/http"
	"strings"
)

// ToolAllowed: what an OAuth client (an AI chat acting for a member) may call —
// module data (todos, calendar events) and view snapshots; not household
// management, invites, calendar connections or account settings.
func ToolAllowed(method, route string) bool {
	switch {
	case method == http.MethodGet && strings.HasPrefix(route, "/api/v1/views/"):
		return true
	case strings.HasPrefix(route, "/api/v1/todo/"):
		return true
	case strings.HasPrefix(route, "/api/v1/calendar/events"):
		return method != http.MethodGet
	}
	return false
}
