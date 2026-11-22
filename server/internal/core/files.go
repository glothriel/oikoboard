package core

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"mime"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// FileMeta is an uploaded file without its data.
type FileMeta struct {
	ID          uuid.UUID  `json:"id" gorm:"type:uuid;primaryKey"`
	HouseholdID uuid.UUID  `json:"-"`
	Name        string     `json:"name"`
	Mime        string     `json:"mime"`
	Size        int64      `json:"size"`
	CreatedBy   *uuid.UUID `json:"-"`
	CreatedAt   time.Time  `json:"created_at"`
}

func (FileMeta) TableName() string { return "files" }

// metaColumns: select these when reading FileMeta, or the data comes along.
const metaColumns = "id, household_id, name, mime, size, created_by, created_at"

// FileMetas reads the metadata of the household's files with these ids
// (missing ones are left out).
func FileMetas(tx *gorm.DB, hh uuid.UUID, ids []uuid.UUID) ([]FileMeta, error) {
	out := []FileMeta{}
	if len(ids) == 0 {
		return out, nil
	}
	err := tx.Select(metaColumns).Where("household_id = ? AND id IN ?", hh, ids).Find(&out).Error
	return out, err
}

type fileRow struct {
	FileMeta
	Data []byte
}

const (
	// MaxFileSize: the largest single upload.
	MaxFileSize = 25 << 20
	// DefaultFileQuota: what a household may store in total (OIKO_STORAGE_QUOTA_MB).
	DefaultFileQuota = 1 << 30
	// unreferenced files are kept this long (time to save the form they were uploaded in)
	fileGrace = 24 * time.Hour
	// signed download links (see link) are valid this long
	linkTTL = 10 * time.Minute
)

// Files stores households' uploaded files in the database (table files).
// Owners (e.g. todo_attachments) reference them by id; [Files.Cleanup]
// deletes files no owner references once they're older than a day.
type Files struct {
	DB *gorm.DB
	// Quota: bytes a household may store in total.
	Quota int64
	// Refs: queries returning the ids of files that are in use, one per owner
	// table, e.g. "SELECT id FROM todo_attachments".
	Refs []string
	key  []byte // signs download links; per process, links are short-lived
}

// FileOwner is a module whose tables reference files.
type FileOwner interface {
	// FileRefs: queries returning the ids of the files in use.
	FileRefs() []string
}

func NewFiles(db *gorm.DB, mods []Module) *Files {
	var refs []string
	for _, m := range mods {
		if o, ok := m.(FileOwner); ok {
			refs = append(refs, o.FileRefs()...)
		}
	}
	key := make([]byte, 32)
	_, _ = rand.Read(key)
	return &Files{DB: db, Quota: DefaultFileQuota, Refs: refs, key: key}
}

// Routes: protected = household members; public = signed download links.
func (f *Files) Routes(protected, public *gin.RouterGroup) {
	protected.POST("/files", f.upload)
	protected.GET("/files/usage", f.usage)
	protected.GET("/files/:id", f.get)
	protected.POST("/files/:id/link", f.link)
	public.GET("/files/:id/download", f.download)
}

type usageOut struct {
	Used  int64 `json:"used"`
	Quota int64 `json:"quota"`
}

func (f *Files) used(tx *gorm.DB, hh uuid.UUID) (int64, error) {
	var used int64
	err := tx.Raw("SELECT COALESCE(sum(size), 0) FROM files WHERE household_id = ?", hh).Scan(&used).Error
	return used, err
}

func (f *Files) usage(c *gin.Context) {
	used, err := f.used(f.DB.WithContext(c.Request.Context()), ActorOf(c).HouseholdID)
	if err != nil {
		FailErr(c, err)
		return
	}
	c.JSON(http.StatusOK, usageOut{Used: used, Quota: f.Quota})
}

var errQuota = errors.New("quota exceeded")

// upload: multipart form with "file" and optionally "id" (client-assigned, so
// a retried upload doesn't store the file twice).
func (f *Files) upload(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, MaxFileSize+1<<20)
	fh, err := c.FormFile("file")
	var tooBig *http.MaxBytesError
	switch {
	case errors.As(err, &tooBig) || (err == nil && fh.Size > MaxFileSize):
		Fail(c, http.StatusRequestEntityTooLarge, "too_large",
			fmt.Sprintf("a file can have at most %d MB", MaxFileSize>>20))
		return
	case err != nil:
		Fail(c, http.StatusBadRequest, "bad_request", "no file: "+err.Error())
		return
	}
	id := uuid.New()
	if s := c.PostForm("id"); s != "" {
		if id, err = uuid.Parse(s); err != nil {
			Fail(c, http.StatusBadRequest, "bad_id", "invalid id")
			return
		}
	}
	src, err := fh.Open()
	if err != nil {
		FailErr(c, err)
		return
	}
	defer src.Close()
	data, err := io.ReadAll(src)
	if err != nil {
		FailErr(c, err)
		return
	}
	actor := ActorOf(c)
	row := fileRow{FileMeta: FileMeta{ID: id, HouseholdID: actor.HouseholdID, Name: cleanFileName(fh.Filename),
		Size: int64(len(data))}, Data: data}
	row.Mime = fileMime(fh.Header.Get("Content-Type"), row.Name, data)
	if actor.MemberID != uuid.Nil {
		row.CreatedBy = &actor.MemberID
	}
	var used int64
	err = f.DB.WithContext(c.Request.Context()).Transaction(func(tx *gorm.DB) error {
		// one upload of a household at a time, so two can't both fit the quota
		if err := tx.Exec("SELECT pg_advisory_xact_lock(hashtext('files:' || ?::text))", actor.HouseholdID).Error; err != nil {
			return err
		}
		var err error
		if used, err = f.used(tx, actor.HouseholdID); err != nil {
			return err
		}
		var existing FileMeta
		if err := tx.Select(metaColumns).Where("id = ?", id).Limit(1).Find(&existing).Error; err != nil {
			return err
		}
		if existing.ID != uuid.Nil { // a retry
			if existing.HouseholdID != actor.HouseholdID {
				return ErrIDConflict
			}
			row.FileMeta = existing
			return nil
		}
		if used+row.Size > f.Quota {
			return errQuota
		}
		used += row.Size
		return tx.Table("files").Clauses(clause.OnConflict{DoNothing: true}).Create(&row).Error
	})
	switch {
	case errors.Is(err, errQuota):
		Fail(c, http.StatusRequestEntityTooLarge, "quota_exceeded",
			fmt.Sprintf("the family's storage is full (%d of %d MB used)", used>>20, f.Quota>>20))
	case errors.Is(err, ErrIDConflict):
		Fail(c, http.StatusConflict, "id_conflict", "the id is already taken")
	case err != nil:
		FailErr(c, err)
	default:
		c.JSON(http.StatusCreated, gin.H{"id": row.ID, "name": row.Name, "mime": row.Mime, "size": row.Size,
			"created_at": row.CreatedAt, "used": used, "quota": f.Quota})
	}
}

// get: the file's content, for the app (bearer auth).
func (f *Files) get(c *gin.Context) {
	id, ok := ParamUUID(c, "id")
	if !ok {
		return
	}
	f.serve(c, ActorOf(c).HouseholdID, id)
}

// link: a short-lived URL that downloads the file without the bearer token
// (for a browser: open in a new tab, or the system's download on Android).
func (f *Files) link(c *gin.Context) {
	id, ok := ParamUUID(c, "id")
	if !ok {
		return
	}
	var n int64
	if err := f.DB.WithContext(c.Request.Context()).Model(&FileMeta{}).
		Where("household_id = ? AND id = ?", ActorOf(c).HouseholdID, id).Count(&n).Error; err != nil {
		FailErr(c, err)
		return
	}
	if n == 0 {
		FailErr(c, gorm.ErrRecordNotFound)
		return
	}
	exp := strconv.FormatInt(time.Now().Add(linkTTL).Unix(), 10)
	c.JSON(http.StatusOK, gin.H{
		"url": fmt.Sprintf("/api/v1/files/%s/download?exp=%s&sig=%s", id, exp, f.sign(id, exp)),
	})
}

func (f *Files) sign(id uuid.UUID, exp string) string {
	m := hmac.New(sha256.New, f.key)
	m.Write([]byte(id.String() + "|" + exp))
	return hex.EncodeToString(m.Sum(nil))
}

func (f *Files) download(c *gin.Context) {
	id, ok := ParamUUID(c, "id")
	if !ok {
		return
	}
	exp := c.Query("exp")
	t, err := strconv.ParseInt(exp, 10, 64)
	if err != nil || time.Now().Unix() > t ||
		!hmac.Equal([]byte(c.Query("sig")), []byte(f.sign(id, exp))) {
		Fail(c, http.StatusForbidden, "forbidden", "the link is invalid or has expired")
		return
	}
	var meta FileMeta
	if err := f.DB.WithContext(c.Request.Context()).Select(metaColumns).Where("id = ?", id).
		First(&meta).Error; err != nil {
		FailErr(c, err)
		return
	}
	f.serve(c, meta.HouseholdID, id)
}

// inlineTypes may be shown by the browser; everything else is downloaded, so
// an uploaded page or SVG never runs as the app's origin.
var inlineTypes = map[string]bool{
	"image/jpeg": true, "image/png": true, "image/gif": true, "image/webp": true, "application/pdf": true,
}

func (f *Files) serve(c *gin.Context, hh, id uuid.UUID) {
	var row fileRow
	err := f.DB.WithContext(c.Request.Context()).Table("files").
		Where("household_id = ? AND id = ?", hh, id).First(&row).Error
	if err != nil {
		FailErr(c, err)
		return
	}
	disposition := "attachment"
	if inlineTypes[row.Mime] {
		disposition = "inline"
	}
	h := c.Writer.Header()
	h.Set("Content-Disposition", mime.FormatMediaType(disposition, map[string]string{"filename": row.Name}))
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Content-Security-Policy", "sandbox; default-src 'none'")
	h.Set("Cache-Control", "private, max-age=31536000, immutable") // a file never changes
	c.Data(http.StatusOK, row.Mime, row.Data)
}

// Cleanup deletes files no owner references, a day after their upload.
func (f *Files) Cleanup(ctx context.Context) {
	q := "DELETE FROM files WHERE created_at < now() - make_interval(secs => ?)"
	for _, ref := range f.Refs {
		q += " AND id NOT IN (" + ref + ")"
	}
	res := f.DB.WithContext(ctx).Exec(q, fileGrace.Seconds())
	if res.Error != nil {
		slog.Error("file cleanup", "err", res.Error)
	} else if res.RowsAffected > 0 {
		slog.Info("deleted unused files", "count", res.RowsAffected)
	}
}

// cleanFileName: the base name, without control characters, at most 200 bytes.
func cleanFileName(name string) string {
	name = filepath.Base(strings.ReplaceAll(name, `\`, "/"))
	name = strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return -1
		}
		return r
	}, strings.TrimSpace(name))
	for len(name) > 200 {
		_, size := utf8.DecodeLastRuneInString(name)
		name = name[:len(name)-size]
	}
	if name == "" || name == "." || name == "/" {
		return "file"
	}
	return name
}

// fileMime: the type the client sent, else by the extension, else sniffed.
func fileMime(sent, name string, data []byte) string {
	if t, _, err := mime.ParseMediaType(sent); err == nil && t != "application/octet-stream" {
		return t
	}
	if t, _, err := mime.ParseMediaType(mime.TypeByExtension(strings.ToLower(filepath.Ext(name)))); err == nil {
		return t
	}
	t, _, _ := mime.ParseMediaType(http.DetectContentType(data))
	return t
}
