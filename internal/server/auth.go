package server

import (
	"context"
	"net/http"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

const apiKeyMetadataKey = "x-api-key"

// NewAPIKeyUnaryInterceptor rejects unary gRPC calls that don't carry the
// configured API key in the "x-api-key" metadata entry.
func NewAPIKeyUnaryInterceptor(apiKey string) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		if err := checkAPIKey(ctx, apiKey); err != nil {
			return nil, err
		}
		return handler(ctx, req)
	}
}

// NewAPIKeyStreamInterceptor is the streaming-call equivalent of
// NewAPIKeyUnaryInterceptor.
func NewAPIKeyStreamInterceptor(apiKey string) grpc.StreamServerInterceptor {
	return func(srv interface{}, ss grpc.ServerStream, info *grpc.StreamServerInfo, handler grpc.StreamHandler) error {
		if err := checkAPIKey(ss.Context(), apiKey); err != nil {
			return err
		}
		return handler(srv, ss)
	}
}

func checkAPIKey(ctx context.Context, apiKey string) error {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		return status.Error(codes.Unauthenticated, "missing x-api-key metadata")
	}
	values := md.Get(apiKeyMetadataKey)
	if len(values) == 0 || values[0] != apiKey {
		return status.Error(codes.Unauthenticated, "invalid or missing API key")
	}
	return nil
}

// RequireAPIKey wraps an HTTP handler so it only runs when the request
// carries the configured key, either via the "X-Api-Key" header or an
// "api_key" query parameter (the latter mainly for Prometheus scrape configs
// that can't set custom headers easily).
func RequireAPIKey(apiKey string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		key := r.Header.Get("X-Api-Key")
		if key == "" {
			key = r.URL.Query().Get("api_key")
		}
		if key == "" || key != apiKey {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}
