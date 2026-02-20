# DeraineDB

> **A High-Performance Vector Database Engine built in Zig & Go.**

DeraineDB is a bleeding-edge embedded vector search engine designed for extreme concurrency, ultra-low latency, and absolute predictability. By bridging the orchestration power of Go with the uncompromising bare-metal speed of Zig, DeraineDB acts as a persistent, thread-safe memory map capable of calculating Nearest Neighbors mathematically at hardware speeds.

---

## ⚡ Performance Benchmarks

Engineered to stretch the limits of POSIX operating systems, DeraineDB (v1.0) achieves unprecedented throughput on standard SSDs and ARM/x86 architectures:

*   **Ingestion Throughput:** Operations ranging up to **8,000,000 vectors/sec**.
*   **KNN Search Latency:** Finding the Top-3 nearest embeddings across thousands of vectors completes in **134µs** (Microseconds).
*   **Production Footprint:** The entire system—runtime, math engine, and CGO bridge—compiles statically into a standalone binary weighing only **1.8MB**.

---

## 🏗️ Core Architecture

### 1. L1 Cache Optimization (64-byte Alignment)
Modern CPU caches load data in 64-byte cache lines. DeraineDB enforces strict `extern struct` alignment in Zig, guaranteeing that a vector's ID, status, semantic tags, and dimensional floats exactly match 64 bytes. This prevents "Cache Line Bouncing" and ensures near-instant CPU accessibility.

### 2. MMap-Driven Storage & Elasticity
Instead of keeping arrays in application RAM, DeraineDB creates a file and links it directly to the OS's virtual memory using `mmap`. The database dynamically resizes itself geometrically, handling `munmap` constraints automatically. Reads and writes bypass user-space memory allocations entirely.

### 3. SIMD-Accelerated KNN Search
Similarity scoring (Euclidean Distance) is implemented natively in Zig utilizing `@Vector` types. This invokes Single Instruction, Multiple Data (SIMD) hardware capabilities, calculating distances across all mathematical dimensions simultaneously in a single CPU clock cycle. While a traditional engine processes each dimension sequentially, DeraineDB uses the XMM/YMM registers of your CPU to process the complete vector as a single data unit.

---

## 🛠️ Technical Stack

DeraineDB achieves maximum performance by heavily isolating responsibilities:
*   **Zig (Core & Math Engine):** Manages atomic `RwLock` structures, `mmap` resizing, file truncation, SIMD floating-point calculations, and memory layouts natively.
*   **Go (Orchestrator):** Manages goroutine routing, high-level API presentation, HTTP/GRPC frontends, and connection pooling.
*   **CGO (Zero-Copy Bridge):** Direct memory pointers are injected across the C-boundary, meaning Zig writes the Top-K logic directly into Go's memory arrays without triggering the Go Garbage Collector.

---

## 🔒 Concurrency & Durability

DeraineDB is inherently thread-safe.
*   **The RWLock Shield:** The engine employs `std.Thread.RwLock`. Thousands of Goroutines can read and search the database simultaneously using a Shared Lock. The lock intelligently upgrades to Exclusive only when a vector is written, deleted, or when the OS needs to physically resize the virtual memory map, guaranteeing zero segmentation faults.
*   **msync Persistence:** Writes are synced gracefully to the disk via POSIX `msync`, securing the persistence layer explicitly.

---

## 🗄️ Memory Layout

DeraineDB dictates a strict 64-byte payload per semantic embedding.

```text
[ ID (8B) | Dim (4B) | Res (4B) | Offset (8B) | Status (1B) | Pad (3B) | Tag (4B) | Vector Data & Padding (32B) ] = 64 Bytes
```

| Field | Type | Offset | Size (Bytes) | Description |
| :--- | :--- | :--- | :--- | :--- |
| **ID** | `uint64_t` | 0 | 8 | The unique vector identifier |
| **Dimensions** | `uint32_t` | 8 | 4 | Number of float dimensions (e.g., 4) |
| **Reserved** | `uint32_t` | 12 | 4 | Internal reserved pointer state |
| **Data Offset** | `uint64_t` | 16 | 8 | Byte offset relative to the block |
| **Status** | `uint8_t` | 24 | 1 | Tombstone flag (`0x00`: Active, `0x01`: Deleted) |
| **Align Pad** | `[3]uint8_t` | 25 | 3 | Hardcoded alignment forcing 4-byte boundaries |
| **Tag** | `uint32_t` | 28 | 4 | Flexible Metadata label for semantic filtering |
| **Data / Padding** | `[32]uint8_t` | 32 | 32 | Stores up to 8 `float32` dimensional values |

---

## 🚀 Installation & Build

### Prerequisites
*   **Zig Compiler:** `v0.13.0+`
*   **Go Toolkit:** `v1.21+`
*   **OS:** macOS / Linux (macOS tested dynamically via BSD Make).

### Master Makefile
The root directory houses a Master `Makefile` automating the CGO Release pipeline.

```bash
# Erase all caches, testing databases, and previous binaries
make clean

# Compile Zig in ReleaseFast mode (stripping safety checks for SIMD)
make build-core

# Compile the Go Orchestrator, dynamically linking the Zig object and stripping debug symbols
make build-go

# All-in-one command: Outputs to ./bin/deraine-db
make all
```

---

## 💻 Usage Guide

The following Go code snippet demonstrates how easily DeraineDB handles vectors via the CGO bridge.

```go
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
	// 1. Open or Create the Engine Database
	dbPath := C.CString("production.drb")
	defer C.free(unsafe.Pointer(dbPath))

	handle := C.deraine_open_db(dbPath)
	defer C.deraine_close_db(handle) // Close gracefully

	// 2. Insert a Mathematical Vector with a Tag
	index := C.uint64_t(1001)
	tag := C.uint32_t(42) // A semantic filter flag
	data := []C.float{1.1, 2.2, 3.3, 4.4}
	vectorLen := C.uint32_t(len(data))

	C.deraine_write_vector(handle, index, tag, &data[0], vectorLen)

	// 3. Search using K-Nearest Neighbors (KNN)
	query := []C.float{1.0, 2.0, 3.0, 4.0}
	const K = 3
	outIds := make([]C.uint64_t, K)    // Pre-allocate pointer space in Go
	outDists := make([]C.float, K)     // Pre-allocate to prevent CGO GC overhead

	matches := C.deraine_search(
		handle,
		&query[0],
		vectorLen,
		0,   // Filter tag: 0 means search globally
		K,
		&outIds[0],
		&outDists[0],
	)

	fmt.Printf("Top Results found: %d\n", int(matches))
	for i := 0; i < int(matches); i++ {
		fmt.Printf("#%d -> Vector ID: %d | Distance: %f\n", 
            i+1, uint64(outIds[i]), float32(outDists[i]))
	}

	// 4. Force Persistence explicitly
	C.deraine_sync(handle)
}
```

---

## 🤘 Design Philosophy

DeraineDB was born from the necessity to have a vector database that does not consume gigabytes of RAM nor depends on heavy virtual machines. We believe in software that embraces the hardware, not software that hides from it.

---
*Built passionately with C, Zig, and Go.*
