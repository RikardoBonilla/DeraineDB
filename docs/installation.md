# Installation & Build Guide

DeraineDB is designed to be built from source with minimal dependencies.

## Prerequisites
- **Zig:** v0.13.0 (for the Core Engine)
- **Go:** v1.25+ (for the Orchestrator)
- **Git**

## 1. Clone the Repository
```bash
git clone https://github.com/RikardoBonilla/DeraineDB.git
cd DeraineDB
```

## 2. Full Build
The Master Makefile handles the CGO bridge and optimization flags automatically:
```bash
make all
```
This generates the optimized binary in `./bin/deraine-db`.

## 3. Running the Server
```bash
./bin/deraine-db
```
The server will start:
- **gRPC API:** `:50051`
- **Admin & Metrics:** `:9090`

## 4. Install an SDK
Choose your preferred language to begin integration:

### Python
```bash
pip install ./sdk/python
```

### Go
```bash
go get github.com/ricardo/deraine-db/sdk/go
```

### Node.js
```bash
npm install ./sdk/js
```

### Rust
Add this to your `Cargo.toml`:
```toml
[dependencies]
derainedb-rust = { path = "./sdk/rust" }
```
