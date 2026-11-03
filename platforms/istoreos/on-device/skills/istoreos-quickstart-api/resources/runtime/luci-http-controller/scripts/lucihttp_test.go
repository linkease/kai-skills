package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestEndpointURLUsesCallerPrefix(t *testing.T) {
	base, err := normalizeBaseURL("router.local", "https")
	if err != nil {
		t.Fatal(err)
	}
	got, err := endpointURL(base, "/cgi-bin/luci/custom", "/status/")
	if err != nil {
		t.Fatal(err)
	}
	if want := "https://router.local/cgi-bin/luci/custom/status"; got != want {
		t.Fatalf("endpoint = %q, want %q", got, want)
	}
}

func TestEndpointURLRejectsTraversal(t *testing.T) {
	base, _ := normalizeBaseURL("router.local", "http")
	if _, err := endpointURL(base, "/cgi-bin/luci", "../admin"); err == nil {
		t.Fatal("expected traversal to fail")
	}
}

func TestLoginAndBoundedRequest(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/cgi-bin/luci/" {
			http.SetCookie(w, &http.Cookie{Name: "sysauth", Value: "sid", Path: "/"})
			return
		}
		if r.URL.Path != "/cgi-bin/luci/custom/status" {
			t.Fatalf("unexpected path %q", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer server.Close()

	client, err := newLuCIClient(server.URL, "http", false, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	if err := client.login(context.Background(), "root", "secret"); err != nil {
		t.Fatal(err)
	}
	data, err := client.request(context.Background(), "GET", "/cgi-bin/luci/custom", "/status", "")
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != `{"ok":true}` {
		t.Fatalf("response = %q", data)
	}
}

func TestWriteRequiresApproval(t *testing.T) {
	if err := requireWriteApproval("POST", false); err == nil {
		t.Fatal("expected POST without approval to fail")
	}
	if err := requireWriteApproval("GET", false); err != nil {
		t.Fatalf("GET unexpectedly failed: %v", err)
	}
}
