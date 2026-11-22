package app_test

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"strings"
	"testing"
)

// upload sends a file as the app does (multipart, client-assigned id optional).
func (c *client) upload(name, id string, data []byte, out any) int {
	c.e.t.Helper()
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	if id != "" {
		w.WriteField("id", id)
	}
	fw, _ := w.CreateFormFile("file", name)
	fw.Write(data)
	w.Close()
	req, _ := http.NewRequest("POST", c.e.srv.URL+"/api/v1/files", &buf)
	req.Header.Set("Content-Type", w.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+c.token)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		c.e.t.Fatal(err)
	}
	defer res.Body.Close()
	if out != nil {
		json.NewDecoder(res.Body).Decode(out)
	}
	return res.StatusCode
}

// raw GETs a path (absolute under the server, or /api/v1-relative with the token).
func (c *client) raw(path string, auth bool) (int, http.Header, []byte) {
	c.e.t.Helper()
	req, _ := http.NewRequest("GET", c.e.srv.URL+path, nil)
	if auth {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		c.e.t.Fatal(err)
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)
	return res.StatusCode, res.Header, body
}

type fileOut struct {
	ID    string
	Name  string
	Mime  string
	Size  int64
	Used  int64
	Quota int64
}

func TestFilesAndAttachments(t *testing.T) {
	e := setup(t)
	a := e.newFamily("Kowalscy")
	b := e.newFamily("Nowakowie")
	_, lists := a.view("todo.lists", nil)
	list := lists["todo_lists"][0]["id"]

	png := []byte("\x89PNG\r\n\x1a\nfake")
	var f fileOut
	if st := a.upload(`C:\photos\cat.png`, "", png, &f); st != http.StatusCreated ||
		f.Name != "cat.png" || f.Mime != "image/png" || f.Size != int64(len(png)) || f.Used != f.Size {
		t.Fatalf("upload: %d %+v", st, f)
	}
	// A retry with the same id stores nothing new.
	var again fileOut
	if st := a.upload("cat.png", f.ID, png, &again); st != http.StatusCreated || again.ID != f.ID || again.Used != f.Size {
		t.Fatalf("retried upload: %d %+v", st, again)
	}
	if st := b.upload("x.txt", f.ID, []byte("x"), nil); st != http.StatusConflict {
		t.Fatalf("other household reusing the id: %d", st)
	}

	// Content: the family's members only, or a signed link.
	if st, h, body := a.raw("/api/v1/files/"+f.ID, true); st != http.StatusOK || !bytes.Equal(body, png) ||
		h.Get("Content-Type") != "image/png" || !strings.HasPrefix(h.Get("Content-Disposition"), "inline") {
		t.Fatalf("get: %d %v", st, h)
	}
	if st, _, _ := b.raw("/api/v1/files/"+f.ID, true); st != http.StatusNotFound {
		t.Fatalf("other household get: %d", st)
	}
	var link struct{ URL string }
	if st := a.do("POST", "/files/"+f.ID+"/link", nil, &link); st != http.StatusOK {
		t.Fatalf("link: %d", st)
	}
	if st, _, body := a.raw(link.URL, false); st != http.StatusOK || !bytes.Equal(body, png) {
		t.Fatalf("download: %d", st)
	}
	if st, _, _ := a.raw(strings.Replace(link.URL, "sig=", "sig=0", 1), false); st != http.StatusForbidden {
		t.Fatalf("tampered link: %d", st)
	}
	if st := b.do("POST", "/files/"+f.ID+"/link", nil, nil); st != http.StatusNotFound {
		t.Fatalf("other household link: %d", st)
	}
	// Anything but a few safe types is downloaded, never shown.
	var page fileOut
	a.upload("x.html", "", []byte("<script>alert(1)</script>"), &page)
	if _, h, _ := a.raw("/api/v1/files/"+page.ID, true); !strings.HasPrefix(h.Get("Content-Disposition"), "attachment") {
		t.Fatalf("html disposition: %v", h)
	}

	// A new task with the file; a comment with only a file.
	var item struct{ ID string }
	if st := a.do("POST", "/todo/items", map[string]any{"list_id": list, "title": "Paszport",
		"attachment_ids": []string{f.ID}}, &item); st != http.StatusCreated {
		t.Fatalf("task with attachment: %d", st)
	}
	w := a.ws()
	snap := w.sub("a", "todo.attachments", map[string]any{"item_id": item.ID})
	if rows := snap.Data["todo_attachments"]; len(rows) != 1 || rows[0]["name"] != "cat.png" || rows[0]["comment_id"] != nil {
		t.Fatalf("snapshot: %+v", snap.Data)
	}
	var doc fileOut
	a.upload("scan.pdf", "", []byte("%PDF-1.4"), &doc)
	var cm struct{ ID string }
	if st := a.do("POST", "/todo/comments", map[string]any{"item_id": item.ID, "body": "",
		"attachment_ids": []string{doc.ID}}, &cm); st != http.StatusCreated {
		t.Fatalf("comment with a file only: %d", st)
	}
	if m := w.next(); m.Entity != "todo_attachments" || m.ID != doc.ID || m.Row["comment_id"] != cm.ID {
		t.Fatalf("comment attachment change: %+v", m)
	}
	// Attaching to an existing task.
	if st := a.do("POST", "/todo/attachments", map[string]any{"id": page.ID, "item_id": item.ID}, nil); st != http.StatusCreated {
		t.Fatalf("attach: %d", st)
	}
	if m := w.next(); m.ID != page.ID {
		t.Fatalf("attach change: %+v", m)
	}
	if st := b.do("POST", "/todo/attachments", map[string]any{"id": page.ID, "item_id": item.ID}, nil); st == http.StatusCreated {
		t.Fatalf("other household attach: %d", st)
	}

	// Removing an attachment deletes its file.
	if st := a.do("DELETE", "/todo/attachments/"+page.ID, nil, nil); st != http.StatusNoContent {
		t.Fatalf("delete attachment: %d", st)
	}
	if m := w.next(); m.T != "remove" || m.ID != page.ID {
		t.Fatalf("delete change: %+v", m)
	}
	if st, _, _ := a.raw("/api/v1/files/"+page.ID, true); st != http.StatusNotFound {
		t.Fatalf("file after delete: %d", st)
	}

	// Quota.
	var usage struct{ Used, Quota int64 }
	a.do("GET", "/files/usage", nil, &usage)
	if usage.Used != f.Size+doc.Size || usage.Quota != 1<<30 {
		t.Fatalf("usage: %+v", usage)
	}
	e.app.Files.Quota = usage.Used + 10
	var quota struct{ Error string }
	if st := a.upload("big.bin", "", make([]byte, 11), &quota); st != http.StatusRequestEntityTooLarge || quota.Error != "quota_exceeded" {
		t.Fatalf("over quota: %d %+v", st, quota)
	}
	if st := a.upload("ok.bin", "", make([]byte, 10), nil); st != http.StatusCreated {
		t.Fatalf("within quota: %d", st)
	}

	// Cleanup: unreferenced files go a day after upload; attached ones stay.
	var stray fileOut
	b.upload("stray.txt", "", []byte("x"), &stray)
	e.db.Exec("UPDATE files SET created_at = now() - interval '2 days'")
	a.do("DELETE", "/todo/comments/"+cm.ID, nil, nil) // its attachment goes with it
	e.app.Files.Cleanup(context.Background())
	var left []string
	e.db.Raw("SELECT name FROM files ORDER BY name").Scan(&left)
	if strings.Join(left, ",") != "cat.png" {
		t.Fatalf("after cleanup: %v", left)
	}
}

func TestTodoMoveBetweenLists(t *testing.T) {
	e := setup(t)
	a := e.newFamily("Kowalscy")
	b := e.newFamily("Nowakowie")
	mama := e.memberID("Kowalscy", "Mama")
	var from, to struct{ ID string }
	a.do("POST", "/todo/lists", map[string]any{"name": "Dom"}, &from)
	a.do("POST", "/todo/lists", map[string]any{"name": "Wakacje"}, &to)
	var item struct{ ID string }
	a.do("POST", "/todo/items", map[string]any{"list_id": from.ID, "title": "Paszport", "assignee_id": mama}, &item)
	a.do("POST", "/todo/comments", map[string]any{"item_id": item.ID, "body": "Wniosek złożony"}, nil)

	w := a.ws()
	w.sub("from", "todo.list", map[string]any{"list_id": from.ID})
	w.sub("to", "todo.list", map[string]any{"list_id": to.ID})
	if st := a.do("PATCH", "/todo/items/"+item.ID, map[string]any{"list_id": to.ID}, nil); st != http.StatusOK {
		t.Fatalf("move: %d", st)
	}
	got := map[string]string{}
	for range 2 {
		m := w.next()
		got[m.Sub] = m.T
	}
	if got["from"] != "remove" || got["to"] != "upsert" {
		t.Fatalf("views: %v", got)
	}
	// The comments stay; the inbox entry now points at the new list.
	if _, d := a.view("todo.comments", map[string]any{"item_id": item.ID}); len(d["todo_comments"]) != 1 {
		t.Fatalf("comments: %+v", d)
	}
	if in := e.login("Kowalscy", "Mama").inbox(mama); len(in) == 0 || in[0]["list_id"] != to.ID {
		t.Fatalf("inbox: %+v", in)
	}

	// Not to another household's list, nor to none.
	var other struct{ ID string }
	b.do("POST", "/todo/lists", map[string]any{"name": "Obca"}, &other)
	if st := a.do("PATCH", "/todo/items/"+item.ID, map[string]any{"list_id": other.ID}, nil); st != http.StatusBadRequest {
		t.Fatalf("move to another household: %d", st)
	}
	if st := a.do("PATCH", "/todo/items/"+item.ID, map[string]any{"list_id": nil}, nil); st != http.StatusBadRequest {
		t.Fatalf("move to null: %d", st)
	}
}
