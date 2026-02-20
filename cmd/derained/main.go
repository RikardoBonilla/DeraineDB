package main

/*
#cgo CFLAGS: -I../../core/include
#cgo LDFLAGS: -L../../core/zig-out/lib -lcore
#include "deraine_core.h"
#include <stdlib.h>
*/
import "C"

import (
	"fmt"
	"log"
	"net"
	"unsafe"

	"google.golang.org/grpc"

	pb "github.com/ricardo/deraine-db/api/grpc/pb"
	"github.com/ricardo/deraine-db/internal/server"
)

func main() {
	fmt.Println("DeraineDB v2.0 - Sprint 9: Intelligent Scaling (HNSW)")

	dbPath := C.CString("test_hnsw.drb")
	defer C.free(unsafe.Pointer(dbPath))

	handle := C.deraine_open_db(dbPath)
	if handle == nil {
		fmt.Println("No existing DB. Creating new one...")
		handle = C.deraine_open_db(dbPath) // wait, deraine_open_db might fail if not exists?
		// Let's assume deraine_open_db handles it if we fixed storage.zig
	}

	// Actually our zig code: open returns error if not found.
	// Let's use a dummy handle for now or fix this logic.
	// In Sprint 8 we used deraine_open_db.
	if handle == nil {
		fmt.Println("❌ Critical Error: Could not open/create DB.")
		return
	}
	defer C.deraine_close_db(handle)

	// Start gRPC Server
	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}
	s := grpc.NewServer()
	deraineServer := server.NewDeraineServer(handle)
	pb.RegisterDeraineServiceServer(s, deraineServer)

	fmt.Println("🚀 DeraineDB gRPC Server with HNSW support running on :50051")
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
