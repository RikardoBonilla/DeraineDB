<p align="center">
  <img src="assets/logo.png" width="250" alt="DeraineDB Logo">
</p>

# DeraineDB v2.0-stable

[![CI Pipeline](https://github.com/RikardoBonilla/DeraineDB/actions/workflows/pipeline.yml/badge.svg)](https://github.com/RikardoBonilla/DeraineDB/actions)
[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/RikardoBonilla/DeraineDB/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

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

## 🏗️ High-Level Architecture
DeraineDB uses a decoupled "Engine + Orchestrator" model:

1. **Zig Core (Engine):** Handles memory-mapped storage, HNSW graph navigation, and SIMD math. It is compiled as a static library (.a) with CGO compatibility.
2. **Go Orchestrator:** Manages the gRPC server, Prometheus metrics, and Admin dashboard.
3. **MMap Persistence:** Uses dual-file storage (Data `.drb` + Index `.dridx`) for atomic persistence and instant recovery.

---

## 🚀 Getting Started

### 📦 Run via Docker (Recommended)
The fastest way to deploy DeraineDB in production:

```bash
# Pull and run using Docker Compose
docker-compose up -d --build
```
*   **gRPC API:** `localhost:50051`
*   **Admin Dashboard:** `http://localhost:9090/admin`
*   **Metrics:** `http://localhost:9090/metrics`

### 🛠️ Build from Source
Requires **Zig 0.15.2** and **Go 1.25**.

```bash
# Compile native binary (ReleaseFast)
make all

# Run server
./bin/deraine-db
```

---

## 🌐 Official SDKs (v2.0)
DeraineDB provides high-performance clients for modern stacks:

*   **[Python SDK](sdk/python):** AI-ready wrapper with latency instrumentation.
*   **[Go SDK](sdk/go):** Native orchestration with connection pooling.
*   **[Rust SDK](sdk/rust):** Zero-cost async client using `tonic`.
*   **[JS/TS SDK](sdk/js):** Web and Node.js compatible.

---

## 📚 Technical Reference
*   **[Installation Guide](docs/installation.md):** Deep-dive into specific compilation flags.
*   **[Metadata Filtering](docs/metadata-filtering.md):** Implementing hardware-first categorical filters.
*   **[Quickstart Comparison](docs/quickstart-comparison.md):** Side-by-side code examples for all languages.

---
*Built passionately for the next generation of AI infrastructure.*
*Created by Ricardo Andres Bonilla Prada - RKD "Echo en Colombia".*