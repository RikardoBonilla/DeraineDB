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

	const totalVectors = 1000
	data := []C.float{0.5, 1.5, 2.5, 3.5}
	vectorLen := C.uint32_t(len(data))

	fmt.Printf("🚀 Starting Sprint 4: Full Circle Test (%d vectors)...\n", totalVectors)

	for i := 0; i < totalVectors; i++ {
		index := C.uint64_t(i)
		res := C.deraine_write_vector(handle, index, &data[0], vectorLen)
		if res != 0 {
			fmt.Printf("❌ Write failed at index %d\n", i)
			return
		}
	}

	fmt.Println("✅ 1,000 vectors inserted.")

	fmt.Println("\n🔍 Reading Vector 500...")
	var outData *C.float
	readRes := C.deraine_read_vector(handle, 500, &outData)
	if readRes == 0 {
		sliceView := unsafe.Slice((*float32)(unsafe.Pointer(outData)), 4)
		fmt.Printf("✅ Vector 500 Data: %v\n", sliceView)
	} else {
		fmt.Printf("❌ Failed to read Vector 500. Code: %d\n", readRes)
	}

	fmt.Println("\n🗑️ Deleting Vector 500...")
	delRes := C.deraine_delete_vector(handle, 500)
	if delRes == 0 {
		fmt.Println("✅ Vector 500 deleted (Tombstone set).")
	} else {
		fmt.Printf("❌ Failed to delete Vector 500. Code: %d\n", delRes)
	}

	fmt.Println("\n🔍 Re-reading Vector 500...")
	var outDataAfter *C.float
	readResAfter := C.deraine_read_vector(handle, 500, &outDataAfter)
	if readResAfter == -2 {
		fmt.Println("✅ Success: Engine correctly rejected the read (Vector marked as Deleted).")
	} else {
		fmt.Printf("❌ Failure: Expected 'Deleted' error (-2), got: %d\n", readResAfter)
	}

	resSync := C.deraine_sync(handle)
	if resSync != 0 {
		fmt.Println("❌ Final Sync failed.")
	}

	fmt.Println("\n--------------------------------------------------")
	fmt.Printf("✅ Sprint 4 Full Circle Test Complete!\n")
	fmt.Println("--------------------------------------------------")
}
