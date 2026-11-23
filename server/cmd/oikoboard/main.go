// oikoboard — the API server.
//
//	go run ./cmd/oikoboard          # migrations + server (+ seed if OIKO_SEED=1 and the DB is empty)
//	go run ./cmd/oikoboard migrate  # migrations only
//	go run ./cmd/oikoboard seed     # add another sample family
//	go run ./cmd/oikoboard link-email "Nasza rodzina" Tata someone@gmail.com
//	                                # the member waits for an account with this e-mail
//
// Configuration via environment variables (or a .env file in the working
// directory; the environment wins):
//
//	OIKO_DATABASE_URL, OIKO_ADDR
//	OIKO_PUBLIC_URL             public API URL (default http://localhost:8090); also the OAuth issuer / MCP resource
//	OIKO_GOOGLE_CLIENT_ID/SECRET Google OAuth client (without them Google sign-in is off)
//	OIKO_RETURN_URLS            where sign-in may return to, comma-separated
//	OIKO_APP_URL                web app URL (invite links; when public, the only CORS origin for /api)
//	OIKO_DEV_LOGIN=1            sign-in with just an e-mail — LOCAL ONLY
//	OIKO_MOCK_OAUTH=1           fake Google: a "who are you?" page — LOCAL ONLY
//	OIKO_SECRET_KEY             32 bytes (base64/hex) encrypting stored credentials; required for Google Calendar
//	OIKO_CALENDAR_SYNC          calendar polling interval (default 2m)
//	OIKO_STORAGE_QUOTA_MB       uploaded files a family may store (default 1024)
//	OIKO_WEB_DIR                built web app to serve on / (the production image sets it)
//	OIKO_SEED=1                 add a sample family when the database is empty — LOCAL ONLY
//	OIKO_SEED_EMAILS            e.g. "Tata=someone@gmail.com,Mama=..." for the seed
package main

import (
	"bufio"
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"oikoboard/server/internal/app"
	"oikoboard/server/internal/core"
	"oikoboard/server/internal/modules/todo"
	"oikoboard/server/internal/recurring"
	"oikoboard/server/internal/seed"

	_ "time/tzdata" // IANA zones for expanding recurring events, also in minimal containers
)

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// loadDotEnv wczytuje KEY=VALUE z .env (bez nadpisywania środowiska).
func loadDotEnv(path string) {
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		k, v = strings.TrimSpace(k), strings.Trim(strings.TrimSpace(v), `"'`)
		if _, set := os.LookupEnv(k); !set {
			os.Setenv(k, v)
		}
	}
}

func authConfig() core.AuthConfig {
	public := env("OIKO_PUBLIC_URL", "http://localhost:8090")
	cfg := core.AuthConfig{
		DevLogin:  env("OIKO_DEV_LOGIN", "") == "1",
		MockOAuth: env("OIKO_MOCK_OAUTH", "") == "1",
		ReturnURLs: strings.Split(
			env("OIKO_RETURN_URLS", "http://localhost:*,http://127.0.0.1:*,oikoboard://auth"), ","),
		AppURL:    env("OIKO_APP_URL", ""),
		PublicURL: os.Getenv("OIKO_PUBLIC_URL"),
	}
	sealer, err := core.NewSealer(env("OIKO_SECRET_KEY", ""))
	if err != nil {
		fatal("OIKO_SECRET_KEY", err)
	}
	cfg.Sealer = sealer
	if id := env("OIKO_GOOGLE_CLIENT_ID", ""); id != "" {
		cfg.Google = &core.GoogleConfig{
			ClientID: id, ClientSecret: env("OIKO_GOOGLE_CLIENT_SECRET", ""), PublicURL: public,
		}
		slog.Info("logowanie Google włączone", "callback", strings.TrimRight(public, "/")+"/api/v1/auth/google/callback")
	} else if !cfg.MockOAuth {
		slog.Warn("brak OIKO_GOOGLE_CLIENT_ID — logowanie Google wyłączone")
	}
	return cfg
}

func main() {
	loadDotEnv(".env")
	dsn := env("OIKO_DATABASE_URL", "postgres://oiko:oiko@localhost:5433/oiko?sslmode=disable")
	addr := env("OIKO_ADDR", ":8090")
	cmd := "serve"
	if len(os.Args) > 1 {
		cmd = os.Args[1]
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	db, err := core.OpenDB(dsn)
	if err != nil {
		fatal("db", err)
	}
	if err := core.Migrate(db); err != nil {
		fatal("migracje", err)
	}

	switch cmd {
	case "migrate":
		return
	case "seed":
		if err := seed.Family(ctx, db, "Rodzina "+time.Now().Format("15:04:05")); err != nil {
			fatal("seed", err)
		}
		slog.Info("dodano przykładową rodzinę")
		return
	case "link-email":
		if len(os.Args) != 5 {
			fatal("użycie", errors.New(`link-email "<rodzina>" <członek> <e-mail>`))
		}
		if err := seed.LinkEmail(ctx, db, os.Args[2], os.Args[3], os.Args[4]); err != nil {
			fatal("link-email", err)
		}
		slog.Info("gotowe — członek zostanie przypięty przy logowaniu tym e-mailem")
		return
	case "serve":
	default:
		fatal("nieznana komenda", errors.New(cmd))
	}

	if env("OIKO_SEED", "") == "1" {
		seedEmpty(ctx, db)
	}

	gin.SetMode(gin.ReleaseMode)
	a := app.New(db, authConfig())
	if d, err := time.ParseDuration(env("OIKO_CALENDAR_SYNC", "2m")); err == nil && d > 0 {
		a.Calendar.Interval = d
	}
	if mb, err := strconv.ParseInt(env("OIKO_STORAGE_QUOTA_MB", ""), 10, 64); err == nil && mb > 0 {
		a.Files.Quota = mb << 20
	}
	if dir := env("OIKO_WEB_DIR", ""); dir != "" {
		a.ServeWeb(dir)
		slog.Info("serving the web app", "dir", dir)
	}
	go a.Run(ctx, db, dsn)

	// Recurring tasks: DBOS schedules + a catch-up for what was missed while down.
	sched, err := recurring.New(ctx, db, dsn, a.Calendar.TodosChanged)
	if err != nil {
		fatal("recurring tasks", err)
	}
	defer sched.Shutdown(10 * time.Second)
	a.Recurring.Set(sched)
	if err := sched.Reconcile(ctx); err != nil {
		fatal("recurring tasks: reconcile", err)
	}
	if err := todo.CatchUp(ctx, db, a.Calendar.TodosChanged, time.Now()); err != nil {
		fatal("recurring tasks: catch-up", err)
	}

	srv := &http.Server{Addr: addr, Handler: a.Router}
	go func() {
		<-ctx.Done()
		sctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(sctx)
	}()
	slog.Info("oikoboard nasłuchuje", "addr", addr)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		fatal("http", err)
	}
}

// seedEmpty adds a sample family to an empty database (OIKO_SEED_EMAILS links accounts).
func seedEmpty(ctx context.Context, db *gorm.DB) {
	if seeded, err := seed.Run(ctx, db); err != nil {
		fatal("seed", err)
	} else if seeded {
		slog.Info("empty database — added a sample family")
		for _, pair := range strings.Split(env("OIKO_SEED_EMAILS", ""), ",") {
			if who, email, ok := strings.Cut(strings.TrimSpace(pair), "="); ok {
				if err := seed.LinkEmail(ctx, db, seed.DefaultFamily, who, email); err != nil {
					fatal("OIKO_SEED_EMAILS", err)
				}
			}
		}
	}
}

func fatal(what string, err error) {
	slog.Error(what, "err", err)
	os.Exit(1)
}
