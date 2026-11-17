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
