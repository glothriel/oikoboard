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
		// Flutter's file names aren't content-hashed (main.dart.js, icons): browsers and
		// proxies (Cloudflare) must revalidate every file, or a new release isn't seen.
		c.Header("Cache-Control", "no-cache")
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
