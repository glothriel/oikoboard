package core

import "strings"

// LikePattern turns a search query into an ILIKE pattern matching it
// anywhere, with the LIKE wildcards in the query escaped.
func LikePattern(q string) string {
	r := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return "%" + r.Replace(q) + "%"
}
