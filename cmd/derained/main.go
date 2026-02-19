package main

/*
#cgo CFLAGS: -I../../include
#cgo LDFLAGS: -L../../core/zig-out/lib -lcore
#include <stdlib.h>
#include "deraine_core.h"
*/
import "C"
import (
	"fmt"
	"os"
	"unsafe"
)

func main() {
	fmt.Printf("DeraineDB - Core Version: %d\n", int(C.deraine_version()))

	dbPath := C.CString("test_bridge.drb")
	defer C.free(unsafe.Pointer(dbPath))

	// 1. Try to create the database
	fmt.Println("Attempting to create DB...")
	res := C.deraine_create_db(dbPath)
	if res == 0 {
		fmt.Println("✅ Database 'test_bridge.drb' created successfully.")
	} else {
		fmt.Println("❌ Error creating database.")
		os.Exit(1)
	}

	// 2. Try to open it
	fmt.Println("Attempting to open DB...")
	resOpen := C.deraine_open_db(dbPath)
	if resOpen == 0 {
		fmt.Println("✅ Database opened successfully (Bridge OK).")
	} else {
		fmt.Println("❌ Error opening database.")
		os.Exit(1)
	}

	// Cleanup
	os.Remove("test_bridge.drb")
}
