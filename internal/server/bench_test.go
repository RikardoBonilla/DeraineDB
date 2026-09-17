package server

import (
	"context"
	"fmt"
	"math/rand"
	"testing"
	"time"

	pb "github.com/ricardo/deraine-db/api/grpc/pb"
)

func randomVector(r *rand.Rand) []float32 {
	v := make([]float32, 1536)
	for i := range v {
		v[i] = r.Float32()
	}
	return v
}

func TestBenchmarkRealLatency(t *testing.T) {
	s := newTestServer(t)
	ctx := context.Background()
	r := rand.New(rand.NewSource(42))

	const n = 1000
	vectors := make([][]float32, n)
	for i := range vectors {
		vectors[i] = randomVector(r)
	}

	start := time.Now()
	for i := 0; i < n; i++ {
		_, err := s.WriteVector(ctx, &pb.WriteVectorRequest{
			Id:           uint64(i),
			Data:         vectors[i],
			MetadataMask: 0x01,
		})
		if err != nil {
			t.Fatalf("write %d failed: %v", i, err)
		}
	}
	writeElapsed := time.Since(start)
	avgWrite := writeElapsed / n
	fmt.Printf("\n=== DeraineDB real benchmark (this machine, post-HNSW-fix) ===\n")
	fmt.Printf("Ingestion: %d vectors x 1536 dims in %v (avg %v/vector)\n", n, writeElapsed, avgWrite)

	const searches = 200
	queries := make([][]float32, searches)
	for i := range queries {
		queries[i] = randomVector(r)
	}

	start = time.Now()
	for i := 0; i < searches; i++ {
		_, err := s.SearchKNN(ctx, &pb.SearchKNNRequest{
			QueryVector: queries[i],
			K:           5,
			FilterMask:  0x01,
		})
		if err != nil {
			t.Fatalf("search %d failed: %v", i, err)
		}
	}
	searchElapsed := time.Since(start)
	avgSearch := searchElapsed / searches
	fmt.Printf("HNSW Search (warm): %d queries (k=5) in %v (avg %v/query)\n", searches, searchElapsed, avgSearch)

	hits := 0
	total := 0
	for id := 0; id < n; id += 10 {
		total++
		resp, err := s.SearchKNN(ctx, &pb.SearchKNNRequest{QueryVector: vectors[id], K: 5, FilterMask: 0x01})
		if err != nil {
			t.Fatalf("correctness search %d failed: %v", id, err)
		}
		found := false
		for _, m := range resp.Matches {
			if m.Id == uint64(id) {
				found = true
			}
		}
		if found {
			hits++
		} else {
			fmt.Printf("  MISS: query for id=%d not found in its own top-5: %+v\n", id, resp.Matches)
		}
	}
	recallPct := 100 * float64(hits) / float64(total)
	fmt.Printf("Self-recall@5: %d/%d (%.1f%%) exact self-matches found in top-5\n", hits, total, recallPct)

	stats, err := s.GetStats(ctx, &pb.GetStatsRequest{})
	if err != nil {
		t.Fatalf("GetStats failed: %v", err)
	}
	fmt.Printf("Memory footprint: %.2f MiB (mmap) for %d vectors\n", float64(stats.MemoryUsageBytes)/1024/1024, stats.VectorCount)
	fmt.Printf("================================================\n")

	// HNSW is an approximate index - 100% recall isn't the bar. This guards
	// against a regression back to the ~50% self-recall bug found and
	// fixed earlier (single-neighbor graph connectivity + a reseeded-
	// every-call PRNG), not against normal approximate-search behavior.
	const minAcceptableRecallPct = 85.0
	if recallPct < minAcceptableRecallPct {
		t.Fatalf("self-recall regression: %.1f%% (%d/%d), want >= %.0f%%", recallPct, hits, total, minAcceptableRecallPct)
	}
}
