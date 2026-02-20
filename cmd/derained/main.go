package main

/*
#cgo CFLAGS: -I../../core/include
#cgo LDFLAGS: -L../../core/zig-out/lib -lcore
#include "deraine_core.h"
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"fmt"
	"log"
	"net"
	"time"
	"unsafe"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	pb "github.com/ricardo/deraine-db/api/grpc/pb"
	"github.com/ricardo/deraine-db/internal/server"
)

func main() {
	fmt.Println("DeraineDB v2.0 - Sprint 8: Distributed Stability & Connectivity")

	dbPath := C.CString("test_bridge.drb")
	defer C.free(unsafe.Pointer(dbPath))

	handle := C.deraine_open_db(dbPath)
	if handle == nil {
		fmt.Println("❌ Critical Error: Handle failed.")
		return
	}
	defer C.deraine_close_db(handle)

	fmt.Printf("🚀 Starting Baseline Benchmark: Direct CGO vs gRPC Latency\n")

	const totalVectors = 5000
	const vectorLen uint32 = 4

	// Pre-insert vectors via direct CGO
	for i := 0; i < totalVectors; i++ {
		index := C.uint64_t(i)
		tag := C.uint32_t(1)
		data := []C.float{C.float(i), C.float(i) + 1.0, C.float(i) + 2.0, C.float(i) + 3.0}

		C.deraine_write_vector(handle, index, tag, &data[0], C.uint32_t(vectorLen))
	}

	query := []C.float{500.0, 501.0, 502.0, 503.0}
	const K = 3
	outIds := make([]C.uint64_t, K)
	outDists := make([]C.float, K)

	// 1. Local CGO Benchmark
	startLocal := time.Now()
	matchesLocal := C.deraine_search(
		handle,
		&query[0],
		C.uint32_t(vectorLen),
		0,
		K,
		&outIds[0],
		&outDists[0],
	)
	durationLocal := time.Since(startLocal)

	fmt.Printf("\n--- LOCAL CGO SEARCH ---\n")
	fmt.Printf("Matches: %d\nLatency: %v\n", matchesLocal, durationLocal)

	// Start gRPC Server
	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}
	s := grpc.NewServer()
	deraineServer := server.NewDeraineServer(handle)
	pb.RegisterDeraineServiceServer(s, deraineServer)

	go func() {
		if err := s.Serve(lis); err != nil {
			log.Fatalf("failed to serve: %v", err)
		}
	}()
	// Short wait for server to listen
	time.Sleep(200 * time.Millisecond)

	// 2. gRPC Benchmark
	conn, err := grpc.NewClient("localhost:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("did not connect: %v", err)
	}
	defer conn.Close()
	c := pb.NewDeraineServiceClient(conn)

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	gQuery := []float32{500.0, 501.0, 502.0, 503.0}

	// Warmup
	_, _ = c.SearchKNN(ctx, &pb.SearchKNNRequest{QueryVector: gQuery, K: K})

	startGRPC := time.Now()
	r, err := c.SearchKNN(ctx, &pb.SearchKNNRequest{
		QueryVector: gQuery,
		K:           K,
		FilterTag:   0,
	})
	durationGRPC := time.Since(startGRPC)

	if err != nil {
		log.Fatalf("gRPC search failed: %v", err)
	}

	fmt.Printf("\n--- gRPC SEARCH (localhost) ---\n")
	fmt.Printf("Matches: %d\nLatency: %v\n", len(r.Matches), durationGRPC)

	overhead := durationGRPC - durationLocal
	fmt.Printf("\n✅ Network Overhead: %v\n", overhead)

	// Test Safe-Copy vector read
	outData := make([]C.float, vectorLen)
	res_buf := C.deraine_read_vector(handle, C.uint64_t(500), &outData[0], C.uint32_t(vectorLen))
	if res_buf == 0 {
		fmt.Printf("\n🔒 Safe-Copy Test Passed: Read vector 500 perfectly => %v\n", outData)
	} else {
		fmt.Printf("\n❌ Safe-Copy Test Failed: code %d\n", res_buf)
	}

	fmt.Println("\ngRPC Server running on port 50051. Press Ctrl+C to exit.")

	// Let it run so python test can hit it.
	select {}
}
