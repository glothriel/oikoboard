// Package migrations zawiera migracje SQL (goose) wkompilowane w binarkę.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
