package app

import (
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
)

// ServeWeb serves the built web app (flutter build web) from dir on every
// path the API doesn't own, falling back to index.html for client-side routes.
// The app and the API share one origin, which a release web build expects.
func (a *App) ServeWeb(dir string) {
	a.Router.NoRoute(func(c *gin.Context) {
		p := c.Request.URL.Path
		if c.Request.Method != http.MethodGet && c.Request.Method != http.MethodHead ||
			strings.HasPrefix(p, "/api/") || strings.HasPrefix(p, "/oauth/") ||
			strings.HasPrefix(p, "/.well-known/") || p == "/mcp" {
			c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
			return
		}
		clean := path.Clean("/" + p)
		if st, err := os.Stat(filepath.Join(dir, filepath.FromSlash(clean))); err != nil || st.IsDir() {
			clean = "/index.html"
		}
		h := c.Writer.Header()
		if clean == "/index.html" || strings.HasSuffix(clean, "flutter_service_worker.js") ||
			strings.HasSuffix(clean, "flutter_bootstrap.js") || strings.HasSuffix(clean, "version.json") {
			h.Set("Cache-Control", "no-cache") // new deploys show up on reload
		}
		// ServeContent, not http.FileServer: that one redirects /index.html → ./ (a loop
		// behind proxies that ask for /index.html).
		f, err := os.Open(filepath.Join(dir, filepath.FromSlash(clean)))
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
			return
		}
		defer f.Close()
		st, err := f.Stat()
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
			return
		}
		http.ServeContent(c.Writer, c.Request, clean, st.ModTime(), f)
	})
}
