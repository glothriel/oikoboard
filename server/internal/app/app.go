// Package app assembles the server from the core and the modules.
package app

import (
	"context"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
	"oikoboard/server/internal/mcp"
	"oikoboard/server/internal/modules/calendar"
	"oikoboard/server/internal/modules/todo"
	"oikoboard/server/internal/realtime"
)

// Modules — a new module = a new entry here (+ a migration with oiko_track).
func Modules(db *gorm.DB, auth *core.Auth, cal *calendar.Syncer, sched todo.Scheduler) []core.Module {
	return []core.Module{
		todo.Module{DB: db, OnItemsChanged: cal.TodosChanged, Scheduler: sched},
		calendar.Module{DB: db, Auth: auth, Providers: cal.Providers, Syncer: cal},
	}
}

type App struct {
	Router *gin.Engine
	Auth   *core.Auth
	Hub    *realtime.Hub
	// Uploaded files; Quota may be changed.
	Files *core.Files
	// Calendar sync; Interval may be changed before Run.
	Calendar *calendar.Syncer
	// Recurring task triggers; attach the DBOS scheduler with Set at startup.
	Recurring *todo.LateScheduler
}

// CalendarProviders builds calendar providers for the auth configuration.
func CalendarProviders(db *gorm.DB, auth *core.Auth, googleAPI string) *calendar.Providers {
	p := &calendar.Providers{DB: db, GoogleAPI: googleAPI}
	if auth.Config.Google != nil {
		p.GoogleClient = auth.CalendarHTTPClient
	}
	return p
}

func New(db *gorm.DB, cfg core.AuthConfig) *App {
	auth := core.NewAuth(db, cfg)
	syncer := &calendar.Syncer{DB: db, Providers: CalendarProviders(db, auth, ""),
		Interval: 2 * time.Minute, TodoDelay: 2 * time.Second}
	recurring := &todo.LateScheduler{}
	mods := Modules(db, auth, syncer, recurring)
	hub := realtime.NewHub(db, auth, core.CollectViews(mods))
	files := core.NewFiles(db, mods)

	r := gin.New()
	r.Use(gin.Recovery(), requestLog(), cors(cfg.AppURL))
	api := r.Group("/api/v1")
	api.GET("/health", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"ok": true}) })
	auth.Routes(api)
	api.GET("/ws", hub.HandleWS) // auth w pierwszej wiadomości

	auth.AccountRoutes(api.Group("", auth.UserMiddleware()))

	protected := api.Group("", auth.Middleware())
	auth.ProtectedRoutes(protected)
	auth.GrantRoutes(protected)
	auth.OAuthRoutes(r)
	protected.GET("/views/:name", hub.HandleViewSnapshot)
	files.Routes(protected, api)
	for _, m := range mods {
		m.Routes(protected)
	}
	r.Any(core.MCPPath, gin.WrapH(mcp.Handler(db, auth, r)))
	return &App{Router: r, Hub: hub, Calendar: syncer, Auth: auth, Files: files, Recurring: recurring}
}

// Run: realtime listener, calendar sync and cleanup of old rows. Blocks until ctx is done.
func (a *App) Run(ctx context.Context, db *gorm.DB, dsn string) {
	go a.Hub.Listen(ctx, dsn)
	go a.Calendar.Run(ctx)
	t := time.NewTicker(time.Hour)
	defer t.Stop()
	for {
		db.WithContext(ctx).Exec("DELETE FROM changes WHERE created_at < now() - interval '30 days'")
		db.WithContext(ctx).Exec("DELETE FROM auth_flows WHERE created_at < now() - interval '1 hour'")
		db.WithContext(ctx).Exec("DELETE FROM invites WHERE expires_at < now() - interval '30 days'")
		db.WithContext(ctx).Exec("DELETE FROM sessions WHERE last_seen_at < now() - interval '90 days'")
		a.Auth.CleanupOAuth(ctx)
		a.Files.Cleanup(ctx)
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

// cors: with a public (non-loopback) app URL, the API (/api/…) only answers
// the app's origin. OAuth and MCP endpoints stay open to any origin: browser
// based MCP clients call them, and they use bearer tokens, not cookies.
func cors(appURL string) gin.HandlerFunc {
	appOrigin := ""
	if u, err := url.Parse(appURL); err == nil && u.Host != "" {
		switch u.Hostname() {
		case "localhost", "127.0.0.1", "::1":
		default:
			appOrigin = u.Scheme + "://" + u.Host
		}
	}
	return func(c *gin.Context) {
		h := c.Writer.Header()
		if appOrigin != "" && strings.HasPrefix(c.Request.URL.Path, "/api/") {
			h.Set("Access-Control-Allow-Origin", appOrigin)
			h.Add("Vary", "Origin")
		} else {
			h.Set("Access-Control-Allow-Origin", "*")
		}
		h.Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Mutation-Id")
		h.Set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

func requestLog() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		if c.Request.URL.Path == "/api/v1/ws" {
			return
		}
		slog.Info("http", "method", c.Request.Method, "path", c.Request.URL.Path,
			"status", c.Writer.Status(), "dur", time.Since(start).Round(time.Millisecond))
	}
}
