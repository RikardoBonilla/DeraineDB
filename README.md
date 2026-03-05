<p align="center">
  <img src="assets/logo.png" width="250" alt="DeraineDB Logo">
</p>

# DeraineDB v2.0-stable
> **The 33.7MB Vector Engine that thinks in Microseconds.**

Why build another vector database? Because empowering local AI shouldn't require downloading gigabytes of Java/Python dependencies or dedicating 8GB of RAM just to start a container. 

DeraineDB is a hyper-optimized, embedded vector search engine built for the Edge and local RAG (Retrieval-Augmented Generation) applications. It bridges the bare-metal, memory-mapped speed of **Zig** with the production-grade network orchestration of **Go**, creating a "Hardware-First" storage layer that runs on fractions of a megabyte.

---

## ⚡ The "Zero-Bloat" Proof (Real Benchmarks)

We don't just claim to be fast; we measure it at the microsecond level. DeraineDB is natively engineered to handle massive dense vectors (like OpenAI's or Llama 3.2's **1536 Dimensions**) without breaking a sweat.

**Stress Test Results (1,000 Vectors x 1536 Dimensions):**

| Metric | DeraineDB v2.0 Performance |
| :--- | :--- |
| **Docker Image Size** | **33.7 MB** (Full Engine + API) |
| **Live RAM Usage** | **~20.99 MiB** |
| **Ingestion Latency** | **1.16 ms** / vector |
| **HNSW Search (Warm)**| **0.898 ms** (Sub-millisecond!) |

---

## 🏗️ Architectural Marvels

DeraineDB abandons bloated traditional database architectures to achieve sub-millisecond latencies through three core innovations:

### 1. HNSW Graph Segregation (Zig Core)
We implemented a strict separation of church and state. Payload data (vectors) lives in memory-mapped `.drb` files with strict cache-line alignment (6208 bytes per block: 64 bytes of struct header + 6144 bytes of `float32` payload). 
To prevent `mmap` buffer overflows, we mathematically compute pointer jumps directly to the payload's memory space: `@as([*]const f32, @ptrCast(@alignCast(block.ptr + @sizeOf(root.DeraineVector))))`. 
The HNSW (Hierarchical Navigable Small World) navigation graph lives safely in isolated `.dridx` files. This guarantees log(N) search complexity without memory corruption or cross-boundary payload overwrites.

### 2. The "Zero-Copy" CGO Bridge (Go Orchestrator)
Traditional Go wrappers suffer from massive Garbage Collection pauses when passing thousands of floats to C by iterating and casting elements individually. DeraineDB eliminates this by using `unsafe.Pointer` to map Protobuf slices directly into Zig's memory space: `(*C.float)(unsafe.Pointer(&req.QueryVector[0]))`. Zero copies. Zero GC overhead. Infinite throughput.

### 3. Hardware-Level Metadata Filtering
Instead of slow JSON metadata parsing, DeraineDB uses a `uint64` `metadata_mask`. Categorical filtering is resolved using Bitwise AND operations `(m & filter_mask) != 0` directly inside the HNSW *Greedy Routing* algorithm's hot loop, filtering out irrelevant vectors in a single CPU clock cycle before distance computation is even attempted.

---

## 🚀 Quick Start

### 1. Deploy via Docker (Recommended)
Launch the ultra-lightweight engine in seconds:

```bash
docker run -d \
  --name derainedb \
  -p 50051:50051 -p 9090:9090 \
  -v $(pwd)/data:/app/data \
  deraine-db:v2.0-stable
```

### 2. Official SDKs
DeraineDB provides high-performance clients for modern stacks out of the box.

*   **[Python SDK](sdk/python):** AI-ready wrapper. 
*   **[Go SDK](sdk/go):** Native orchestration with connection pooling.
*   **[Rust SDK](sdk/rust):** Zero-cost async client using `tonic`.
*   **[JS/TS SDK](sdk/js):** Web and Node.js compatible.

**Python RAG Example:**
```python
import time
from derainedb.client import DeraineClient
from sentence_transformers import SentenceTransformer

embedder = SentenceTransformer('all-MiniLM-L6-v2')
db = DeraineClient(host="localhost", port=50051)

# 1. Ingestion (Store memory with a 64-bit metadata category)
text = "DeraineDB uses Zig and Go for sub-millisecond vector indexing."
vector = embedder.encode(text).tolist() + [0.0] * (1536 - 384) # Pad to 1536D

db.write(id=1, data=vector, metadata_mask=0x01)
print("Vector stored in memory-mapped file.")

# 2. HNSW Search (O(log N) routing)
query = "What languages does DeraineDB use?"
q_vector = embedder.encode(query).tolist() + [0.0] * (1536 - 384)

results = db.search(query=q_vector, k=1, filter_mask=0x01)
if results:
    print(f"Match found! ID: {results[0]['id']} | Distance: {results[0]['distance']:.4f}")
```

**Go SDK Example:**
```go
package main

import (
	"context"
	"fmt"
	"log"

	"github.com/ricardo/derainedb/sdk/go/client"
)

func main() {
	db, err := client.NewClient("localhost:50051")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// 1. Ingestion
	vector := make([]float32, 1536)
	vector[0] = 0.5 // Simulated embedding
	err = db.Write(context.Background(), 1, vector, 0x01)
	if err == nil {
		fmt.Println("Vector stored successfully.")
	}

	// 2. HNSW Search
	query := make([]float32, 1536)
	query[0] = 0.5
	results, _ := db.Search(context.Background(), query, 3, 0x01)
	
	if len(results) > 0 {
		fmt.Printf("Match ID: %d | Distance: %.4f\n", results[0].Id, results[0].Distance)
	}
}
```

**JS/TS SDK Example:**
```typescript
import { DeraineClient } from 'derainedb';

async function main() {
  const db = new DeraineClient('localhost:50051');

  // 1. Ingestion
  const vector = new Array(1536).fill(0);
  vector[0] = 0.5; // Simulated embedding
  
  await db.write({ id: 1, data: vector, metadataMask: 1 });
  console.log('Vector stored in DeraineDB.');

  // 2. HNSW Search
  const query = new Array(1536).fill(0);
  query[0] = 0.5;
  
  const results = await db.search({ query, k: 3, filterMask: 1 });
  if (results.length > 0) {
    console.log(`Match ID: ${results[0].id} | Distance: ${results[0].distance}`);
  }
}

main();
```

---
*Built passionately for the next generation of AI infrastructure.* *Created by Ricardo Andres Bonilla Prada - RKD "Hecho en Colombia".*