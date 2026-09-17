package server

import (
	"fmt"
	"unsafe"
)

/*
#cgo CFLAGS: -I../../core/include
#cgo LDFLAGS: -L../../core/zig-out/lib -lcore
#include "deraine_core.h"
#include <stdlib.h>
*/
import "C"

// OpenDB opens (creating it if needed) the engine's data file at path.
func OpenDB(path string) (unsafe.Pointer, error) {
	cPath := C.CString(path)
	defer C.free(unsafe.Pointer(cPath))

	handle := C.deraine_open_db(cPath)
	if handle == nil {
		return nil, fmt.Errorf("could not open/create db at %s", path)
	}
	return handle, nil
}

// CloseDB releases all resources associated with handle.
func CloseDB(handle unsafe.Pointer) {
	C.deraine_close_db(handle)
}
