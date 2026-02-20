.PHONY: all build-core build-go clean run

all: clean build-core build-go

build-core:
	@echo "=> Compiling Zig Engine (ReleaseFast)..."
	cd core && zig build -Doptimize=ReleaseFast

build-go:
	@echo "=> Compiling Go Orchestrator (Stripping debug symbols)..."
	mkdir -p bin
	go build -a -ldflags="-s -w" -o bin/deraine-db ./cmd/derained

clean:
	@echo "=> Cleaning workspace..."
	rm -rf bin/
	rm -rf core/zig-cache/
	rm -rf core/zig-out/
	rm -f test_bridge.drb

run: all
	@echo "=> Executing DeraineDB..."
	./bin/deraine-db