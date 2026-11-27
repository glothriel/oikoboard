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
	// Not allowed on purpose: /api/v1/fitness/ (body data is sensitive; the
	// fitness.* views are refused by ViewAllowed).
	case strings.HasPrefix(route, "/api/v1/todo/"):
		return true
	case strings.HasPrefix(route, "/api/v1/calendar/events"):
		return method != http.MethodGet
	}
	return false
}

// sensitiveViewPrefixes: views a delegated client must not read even though it
// may read other view snapshots (body weight, birth date).
var sensitiveViewPrefixes = []string{"fitness."}

// ViewAllowed: may the actor read the named view?
func ViewAllowed(a Actor, name string) bool {
	if !a.Restricted() {
		return true
	}
	for _, p := range sensitiveViewPrefixes {
		if strings.HasPrefix(name, p) {
			return false
		}
	}
	return true
}
