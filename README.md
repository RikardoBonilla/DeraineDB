# DeraineDB

> **The 1.8MB Vector Engine that thinks in Microseconds.**

DeraineDB is a high-performance, embedded vector search engine designed for extreme concurrency and predictable low latency. It bridges the bare-metal speed of **Zig** with the production-grade orchestration of **Go**, creating a "Hardware-First" storage layer for modern AI applications.

---

## ⚡ Performance: HNSW & SIMD
Engineered for speed, DeraineDB (v2.0) leverages advanced indexing and hardware acceleration:

*   **HNSW Indexing:** Navigates million-scale datasets in **0.7ms - 0.8ms** using hierarchical graph traversal.
*   **SIMD Acceleration:** Euclidean Distance calculations are parallelized at the CPU register level (@Vector).
*   **Metadata Filtering:** 64-bit `metadata_mask` allows categorical filtering *before* distance calculation, maintaining $O(\log N)$ complexity.
*   **Zero-Copy Memory Map:** Direct `mmap` mapping bypasses userspace buffers for instant data access.

### Benchmarks (100k Vectors, 4 Dimensions)
| Mode | Latency (avg) | Accuracy |
| :--- | :--- | :--- |
| **Flat Search** | 12.4ms | 100% |
| **HNSW (v2.0)** | **0.804ms** | 99.8% |

---

## 🏗️ Architecture
- **64-byte Alignment:** Every vector is perfectly aligned to CPU cache lines to prevent bouncing and maximize throughput.
- **Auto-Heal Recovery:** Automatic HNSW reconstruction if the index is out-of-sync or missing.
- **Atomic Snapshots:** Point-in-time point backups using exclusive RWLock and forced `msync`.
- **Hybrid Stack:** Zig handles memory/math; Go handles gRPC, metrics, and API orchestration.

---

## 🚀 Quick Start (Python)

```python
import grpc
import deraine_pb2
import deraine_pb2_grpc

# Connect to DeraineDB (default :50051)
channel = grpc.insecure_channel('localhost:50051')
stub = deraine_pb2_grpc.DeraineServiceStub(channel)

# Ingest a vector with a categorical mask
stub.WriteVector(deraine_pb2.WriteVectorRequest(
    id=1001,
    data=[1.1, 2.2, 3.3, 4.4],
    metadata_mask=0x01 # Category: Images
))

# Search with filters
response = stub.SearchKNN(deraine_pb2.SearchKNNRequest(
    query=[1.0, 2.0, 3.0, 4.0],
    k=3,
    filter_mask=0x01
))

for match in response.matches:
    print(f"ID: {match.id}, Score: {match.distance}")
```

---

## 🛠️ Management & Monitoring
DeraineDB includes built-in observability for production stability:

*   **Admin UI:** Web dashboard at `http://localhost:9090/admin`.
*   **Prometheus:** Live metrics at `http://localhost:9090/metrics`.
*   **Grafana:** Reference dashboard available in `/grafana/dashboard.json`.

---

## 🛠️ Build from Source
```bash
# Compile everything (Zig + Go)
make all

# Run the server
./bin/deraine-db
```

---
*Built passionately for the next generation of AI infrastructure.*
