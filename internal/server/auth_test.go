package server

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

func TestCheckAPIKey(t *testing.T) {
	ctx := metadata.NewIncomingContext(context.Background(), metadata.Pairs("x-api-key", "secret"))

	if err := checkAPIKey(ctx, "secret"); err != nil {
		t.Fatalf("expected valid key to pass, got: %v", err)
	}

	if err := checkAPIKey(ctx, "other"); status.Code(err) != codes.Unauthenticated {
		t.Fatalf("expected Unauthenticated for wrong key, got: %v", err)
	}

	if err := checkAPIKey(context.Background(), "secret"); status.Code(err) != codes.Unauthenticated {
		t.Fatalf("expected Unauthenticated for missing metadata, got: %v", err)
	}
}

func TestRequireAPIKey(t *testing.T) {
	var handlerCalled bool
	h := RequireAPIKey("secret", func(w http.ResponseWriter, r *http.Request) {
		handlerCalled = true
		w.WriteHeader(http.StatusOK)
	})

	handlerCalled = false
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()
	h(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for missing key, got %d", rec.Code)
	}
	if handlerCalled {
		t.Fatal("handler should not run without a valid key")
	}

	handlerCalled = false
	req2 := httptest.NewRequest(http.MethodGet, "/", nil)
	req2.Header.Set("X-Api-Key", "secret")
	rec2 := httptest.NewRecorder()
	h(rec2, req2)
	if rec2.Code != http.StatusOK {
		t.Fatalf("expected 200 for correct header key, got %d", rec2.Code)
	}
	if !handlerCalled {
		t.Fatal("handler should have run with a valid header key")
	}

	handlerCalled = false
	req3 := httptest.NewRequest(http.MethodGet, "/?api_key=secret", nil)
	rec3 := httptest.NewRecorder()
	h(rec3, req3)
	if rec3.Code != http.StatusOK {
		t.Fatalf("expected 200 for correct query-param key, got %d", rec3.Code)
	}
	if !handlerCalled {
		t.Fatal("handler should have run with a valid query-param key")
	}

	handlerCalled = false
	req4 := httptest.NewRequest(http.MethodGet, "/", nil)
	req4.Header.Set("X-Api-Key", "wrong")
	rec4 := httptest.NewRecorder()
	h(rec4, req4)
	if rec4.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for wrong key, got %d", rec4.Code)
	}
	if handlerCalled {
		t.Fatal("handler should not run with a wrong key")
	}
}
