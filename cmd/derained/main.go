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
	"time"
	"unsafe"
)

func main() {
	fmt.Println("DeraineDB - Memory Benchmark (Baseline)")

	dbPath := C.CString("test_bridge.drb")
	defer C.free(unsafe.Pointer(dbPath))

	handle := C.deraine_open_db(dbPath)
	if handle == nil {
		fmt.Println("❌ Critical Error: Handle failed.")
		return
	}
	defer C.deraine_close_db(handle)

	fmt.Printf("🚀 Starting Sprint 6: Mathematics & Vector Search...\n")

	const totalVectors = 5000
	const vectorLen uint32 = 4

	startTime := time.Now()
	for i := 0; i < totalVectors; i++ {
		index := C.uint64_t(i)
		tag := C.uint32_t(1)

		data := []C.float{C.float(i), C.float(i) + 1.0, C.float(i) + 2.0, C.float(i) + 3.0}

		res := C.deraine_write_vector(handle, index, tag, &data[0], C.uint32_t(vectorLen))
		if res != 0 {
			fmt.Printf("❌ Write failed at index %d\n", i)
			return
		}
	}
	ingestionDuration := time.Since(startTime)
	fmt.Printf("✅ %d mathematical embeddings inserted in %v.\n", totalVectors, ingestionDuration)

	query := []C.float{500.0, 501.0, 502.0, 503.0}
	fmt.Printf("\n🔍 Querying Vector: %v\n", query)

	const K = 3
	outIds := make([]C.uint64_t, K)
	outDists := make([]C.float, K)

	searchStart := time.Now()
	matches := C.deraine_search(
		handle,
		&query[0],
		C.uint32_t(vectorLen),
		0,
		K,
		&outIds[0],
		&outDists[0],
	)
	searchDuration := time.Since(searchStart)

	if matches >= 0 {
		fmt.Printf("✅ Search completed in %v. Found %d matches.\n", searchDuration, matches)
		fmt.Println("\n🏆 Top Results:")
		for i := 0; i < int(matches); i++ {
			fmt.Printf("   #%d -> Vector ID: %d | Euclidean Distance: %f\n", i+1, uint64(outIds[i]), float32(outDists[i]))
		}
	} else {
		fmt.Printf("❌ Search failed with code: %d\n", matches)
	}

	resSync := C.deraine_sync(handle)
	if resSync != 0 {
		fmt.Println("❌ Final Sync failed.")
	}

	fmt.Println("\n--------------------------------------------------")
	fmt.Printf("✅ Sprint 6 AI Vector Search Test Complete!\n")
	fmt.Println("--------------------------------------------------")
}
