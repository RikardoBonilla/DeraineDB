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

	const totalVectors = 1023
	data := []C.float{0.5, 1.5, 2.5, 3.5}
	vectorLen := C.uint32_t(len(data))

	fmt.Printf("🚀 Starting ingestion of %d vectors...\n", totalVectors)

	startTime := time.Now()

	for i := 0; i < totalVectors; i++ {
		index := C.uint64_t(i)
		res := C.deraine_write_vector(handle, index, &data[0], vectorLen)
		if res != 0 {
			fmt.Printf("❌ Write failed at index %d\n", i)
			break
		}
	}

	duration := time.Since(startTime)

	fmt.Println("--------------------------------------------------")
	fmt.Printf("✅ Benchmark Complete!\n")
	fmt.Printf("⏱️ Total Time: %v\n", duration)
	fmt.Printf("📊 Avg Latency per Vector: %v\n", duration/totalVectors)
	fmt.Printf("📈 Throughput: %.2f vectors/sec\n", float64(totalVectors)/duration.Seconds())
	fmt.Println("--------------------------------------------------")
}
