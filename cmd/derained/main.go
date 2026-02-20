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
	"math/rand"
	"sync"
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

	fmt.Printf("🚀 Starting Sprint 5: Concurrency Stress Test (100 Goroutines)...\n")

	var wg sync.WaitGroup
	const numRoutines = 100
	const opsPerRoutine = 500

	data := []C.float{0.5, 1.5, 2.5, 3.5}
	vectorLen := C.uint32_t(len(data))

	startTime := time.Now()

	for i := 0; i < numRoutines; i++ {
		wg.Add(1)
		go func(routineID int) {
			defer wg.Done()

			r := rand.New(rand.NewSource(time.Now().UnixNano() + int64(routineID)))

			for j := 0; j < opsPerRoutine; j++ {
				opType := r.Float32()
				index := C.uint64_t(r.Intn(100000))

				if opType < 0.4 {
					C.deraine_write_vector(handle, index, &data[0], vectorLen)
				} else if opType < 0.8 {
					var outData *C.float
					res := C.deraine_read_vector(handle, index, &outData)
					if res == 0 {
						_ = unsafe.Slice((*float32)(unsafe.Pointer(outData)), 4)
					}
				} else {
					C.deraine_delete_vector(handle, index)
				}
			}
		}(i)
	}

	wg.Wait()

	testDuration := time.Since(startTime)
	totalOps := numRoutines * opsPerRoutine

	resSync := C.deraine_sync(handle)
	if resSync != 0 {
		fmt.Println("❌ Final Sync failed.")
	}

	fmt.Println("\n--------------------------------------------------")
	fmt.Printf("✅ Sprint 5 Concurrency Test Complete! (Zero Segfaults)\n")
	fmt.Printf("⚡ Processed %d concurrent operations in %v\n", totalOps, testDuration)
	fmt.Printf("📈 Concurrent Throughput: %.2f ops/sec\n", float64(totalOps)/testDuration.Seconds())
	fmt.Println("--------------------------------------------------")
}
