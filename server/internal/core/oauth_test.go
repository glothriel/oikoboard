package core

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestClientMetadataDocument(t *testing.T) {
	var body string
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(strings.ReplaceAll(body, "SELF", "https://"+r.Host+r.URL.Path)))
	}))
	defer srv.Close()
	id := srv.URL + "/oauth/client.json"
	ctx := context.Background()

	// The real client refuses loopback (the URL comes from whoever calls /authorize).
	body = `{"client_id":"SELF","client_name":"ChatGPT","redirect_uris":["https://chatgpt.com/cb"]}`
	if _, err := fetchClientMetadata(ctx, id); err == nil || !strings.Contains(err.Error(), "non-public") {
		t.Fatalf("loopback allowed: %v", err)
	}

	orig := metadataHTTP
	metadataHTTP = srv.Client()
	defer func() { metadataHTTP = orig }()

	doc, err := fetchClientMetadata(ctx, id)
	if err != nil || doc.ClientName != "ChatGPT" || len(doc.RedirectURIs) != 1 {
		t.Fatalf("valid document: %+v %v", doc, err)
	}
	// ChatGPT: prefers private_key_jwt, also supports none (we use none).
	body = `{"client_id":"SELF","redirect_uris":["https://chatgpt.com/cb"],"token_endpoint_auth_method":"private_key_jwt","token_endpoint_auth_methods_supported":["none","private_key_jwt"]}`
	if _, err := fetchClientMetadata(ctx, id); err != nil {
		t.Fatalf("chatgpt document: %v", err)
	}
	for name, b := range map[string]string{
		"id mismatch":   `{"client_id":"https://other.example/x","redirect_uris":["https://a.example/cb"]}`,
		"no redirects":  `{"client_id":"SELF","redirect_uris":[]}`,
		"http redirect": `{"client_id":"SELF","redirect_uris":["http://a.example/cb"]}`,
		"confidential":  `{"client_id":"SELF","redirect_uris":["https://a.example/cb"],"token_endpoint_auth_method":"client_secret_basic"}`,
	} {
		body = b
		if _, err := fetchClientMetadata(ctx, id); err == nil {
			t.Errorf("%s: accepted", name)
		}
	}
	if _, err := fetchClientMetadata(ctx, "http://example.com/c.json"); err == nil {
		t.Error("http client_id accepted")
	}
}

func TestPgTextArray(t *testing.T) {
	in := pgTextArray{"https://a.example/cb?x=1,2", `quo"te`, `back\slash`}
	v, _ := in.Value()
	var out pgTextArray
	if err := out.Scan(v); err != nil || len(out) != 3 || out[0] != in[0] || out[1] != in[1] || out[2] != in[2] {
		t.Fatalf("round trip: %q → %v → %q %v", in, v, out, err)
	}
}

func TestRedirectRegistered(t *testing.T) {
	reg := []string{"http://localhost/callback", "http://127.0.0.1/callback", "https://chatgpt.com/cb"}
	for uri, want := range map[string]bool{
		"http://localhost/callback":       true,
		"http://localhost:53124/callback": true,
		"http://127.0.0.1:8080/callback":  true,
		"https://chatgpt.com/cb":          true,
		"https://chatgpt.com:444/cb":      false,
		"http://localhost:53124/other":    false,
		"http://[::1]:53124/callback":     false,
		"http://evil.example/callback":    false,
		"http://localhost:1/callback?x=1": false,
		"":                                false,
	} {
		if got := redirectRegistered(reg, uri); got != want {
			t.Errorf("%q: got %v, want %v", uri, got, want)
		}
	}
}
