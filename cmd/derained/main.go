// Package main implements the DeraineDB Orchestrator.
// It bridges the Zig-based vector engine with a gRPC API, Prometheus metrics, and an Admin UI.
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
	"net/http"
	"os"
	"time"
	"unsafe"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"google.golang.org/grpc"

	pb "github.com/ricardo/deraine-db/api/grpc/pb"
	"github.com/ricardo/deraine-db/internal/server"
)

func main() {
	fmt.Println("DeraineDB v2.0 - Sprint 11: Persistence & High Availability (Snapshots & Recovery)")

	dbPath := C.CString("test_hnsw.drb")
	defer C.free(unsafe.Pointer(dbPath))

	handle := C.deraine_open_db(dbPath)
	if handle == nil {
		fmt.Println("❌ Critical Error: Could not open/create DB.")
		return
	}
	defer C.deraine_close_db(handle)

	// --- Task 11.3: Crash Recovery (Auto-Heal) ---
	var status C.deraine_status_t
	if C.deraine_get_status(handle, &status) == 0 {
		fmt.Printf("🔍 Engine Status: %d vectors | HNSW Max Level: %d\n", status.vector_count, status.max_level)

		// If index is empty but we have vectors, trigger rebuild
		if status.vector_count > 0 && status.max_level == -1 {
			fmt.Println("⚠️  Index out of sync detected. Triggering HNSW reconstruction...")
			if C.deraine_rebuild_index(handle) != 0 {
				fmt.Println("❌ Error during index reconstruction.")
			} else {
				fmt.Println("✅ HNSW Index rebuilt successfully.")
			}
		}
	}

	// --- Sprint 12: Real-time Observability Server ---
	go func() {
		mux := http.NewServeMux()

		// 1. Prometheus Metrics
		reg := prometheus.NewRegistry()
		reg.MustRegister(server.NewDeraineCollector(handle))
		mux.Handle("/metrics", promhttp.HandlerFor(reg, promhttp.HandlerOpts{}))

		// 2. Admin UI
		mux.HandleFunc("/admin", func(w http.ResponseWriter, r *http.Request) {
			tpl, err := os.ReadFile("internal/server/admin_ui.html")
			if err != nil {
				http.Error(w, "Admin UI template not found", http.StatusInternalServerError)
				return
			}
			w.Header().Set("Content-Type", "text/html")
			w.Write(tpl)
		})

		// 3. API for UI Polling
		mux.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
			var status C.deraine_status_t
			C.deraine_get_status(handle, &status)
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"healthy": %v, "vector_count": %d, "index_level": %d}`,
				status.healthy != 0, status.vector_count, status.max_level)
		})

		mux.HandleFunc("/api/snapshot", func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodPost {
				http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
				return
			}
			path := C.CString("web_backup_" + fmt.Sprintf("%d", time.Now().Unix()))
			defer C.free(unsafe.Pointer(path))
			if C.deraine_create_snapshot(handle, path) == 0 {
				w.WriteHeader(http.StatusOK)
			} else {
				w.WriteHeader(http.StatusInternalServerError)
			}
		})

		fmt.Println("📊 Observability Server (Metrics & Admin) running on :9090")
		if err := http.ListenAndServe(":9090", mux); err != nil {
			log.Printf("Observability server error: %v", err)
		}
	}()

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
