package server

import (
	"context"
	"path/filepath"
	"testing"

	pb "github.com/ricardo/deraine-db/api/grpc/pb"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// newTestServer opens a fresh, temp-dir-backed engine instance for each test
// so tests don't share or corrupt state. Cgo can't be used directly in
// _test.go files, so the open/close calls live in db.go instead.
func newTestServer(t *testing.T) *DeraineServer {
	t.Helper()
	path := filepath.Join(t.TempDir(), "test.drb")

	handle, err := OpenDB(path)
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}
	t.Cleanup(func() {
		CloseDB(handle)
	})

	return NewDeraineServer(handle)
}

func testVector(fill float32) []float32 {
	v := make([]float32, 1536)
	for i := range v {
		v[i] = fill
	}
	return v
}

func TestWriteVectorRejectsWrongDimension(t *testing.T) {
	s := newTestServer(t)
	_, err := s.WriteVector(context.Background(), &pb.WriteVectorRequest{
		Id:   1,
		Data: []float32{1, 2, 3, 4},
	})
	if err == nil {
		t.Fatal("expected error for wrong-dimension vector, got nil")
	}
	if status.Code(err) != codes.InvalidArgument {
		t.Fatalf("expected InvalidArgument, got: %v", err)
	}
}

func TestWriteVectorAcceptsCorrectDimension(t *testing.T) {
	s := newTestServer(t)
	resp, err := s.WriteVector(context.Background(), &pb.WriteVectorRequest{
		Id:   1,
		Data: testVector(1.0),
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !resp.Success {
		t.Fatal("expected Success=true")
	}
}

func TestSearchKNNRejectsWrongDimension(t *testing.T) {
	s := newTestServer(t)
	_, err := s.SearchKNN(context.Background(), &pb.SearchKNNRequest{
		QueryVector: []float32{1, 2},
		K:           3,
	})
	if err == nil {
		t.Fatal("expected error for wrong-dimension query, got nil")
	}
	if status.Code(err) != codes.InvalidArgument {
		t.Fatalf("expected InvalidArgument, got: %v", err)
	}
}

func TestSearchKNNFindsWrittenVector(t *testing.T) {
	s := newTestServer(t)
	ctx := context.Background()

	if _, err := s.WriteVector(ctx, &pb.WriteVectorRequest{Id: 42, Data: testVector(5.0)}); err != nil {
		t.Fatalf("write failed: %v", err)
	}

	resp, err := s.SearchKNN(ctx, &pb.SearchKNNRequest{QueryVector: testVector(5.0), K: 1})
	if err != nil {
		t.Fatalf("search failed: %v", err)
	}
	if len(resp.Matches) == 0 {
		t.Fatal("expected at least one match")
	}
	if resp.Matches[0].Id != 42 {
		t.Fatalf("expected match id=42, got %d", resp.Matches[0].Id)
	}
}

func TestDeleteVector(t *testing.T) {
	s := newTestServer(t)
	ctx := context.Background()

	if _, err := s.WriteVector(ctx, &pb.WriteVectorRequest{Id: 7, Data: testVector(2.0)}); err != nil {
		t.Fatalf("write failed: %v", err)
	}

	resp, err := s.DeleteVector(ctx, &pb.DeleteVectorRequest{Id: 7})
	if err != nil {
		t.Fatalf("delete failed: %v", err)
	}
	if !resp.Success {
		t.Fatal("expected Success=true")
	}
}

func TestGetEngineStatus(t *testing.T) {
	s := newTestServer(t)
	resp, err := s.GetEngineStatus(context.Background(), &pb.GetEngineStatusRequest{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !resp.Healthy {
		t.Fatal("expected engine to report healthy")
	}
}

func TestGetStatsReflectsWrites(t *testing.T) {
	s := newTestServer(t)
	ctx := context.Background()

	before, err := s.GetStats(ctx, &pb.GetStatsRequest{})
	if err != nil {
		t.Fatalf("GetStats before: %v", err)
	}
	if before.MemoryUsageBytes == 0 {
		t.Fatal("expected nonzero memory usage even for a freshly opened db")
	}

	if _, err := s.WriteVector(ctx, &pb.WriteVectorRequest{Id: 3, Data: testVector(1.0)}); err != nil {
		t.Fatalf("write failed: %v", err)
	}

	after, err := s.GetStats(ctx, &pb.GetStatsRequest{})
	if err != nil {
		t.Fatalf("GetStats after: %v", err)
	}
	// vector_count is "highest written index + 1", so writing id=3 makes it 4.
	if after.VectorCount != 4 {
		t.Fatalf("expected vector_count=4, got %d", after.VectorCount)
	}
}
