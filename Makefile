.PHONY: all build-core build-go clean run release-linux release-macos release-windows

all: clean build-core build-go

build-core:
	@echo "=> Compiling Zig Engine (ReleaseFast)..."
	cd core && zig build -Doptimize=ReleaseFast

build-go:
	@echo "=> Compiling Go Orchestrator (Stripping debug symbols)..."
	mkdir -p bin
	go build -a -ldflags="-s -w" -o bin/deraine-db ./cmd/derained

# Multi-platform Releases
release-linux: clean
	@echo "=> Packaging for Linux (amd64)..."
	cd core && zig build -Dtarget=x86_64-linux -Doptimize=ReleaseFast
	GOOS=linux GOARCH=amd64 CGO_ENABLED=1 go build -ldflags="-s -w" -o bin/deraine-db-linux-amd64 ./cmd/derained

release-macos: clean
	@echo "=> Packaging for macOS (Universal)..."
	cd core && zig build -Doptimize=ReleaseFast
	GOOS=darwin GOARCH=arm64 CGO_ENABLED=1 go build -ldflags="-s -w" -o bin/deraine-db-darwin-arm64 ./cmd/derained
	GOOS=darwin GOARCH=amd64 CGO_ENABLED=1 go build -ldflags="-s -w" -o bin/deraine-db-darwin-amd64 ./cmd/derained

release-windows: clean
	@echo "=> Packaging for Windows (amd64)..."
	cd core && zig build -Dtarget=x86_64-windows -Doptimize=ReleaseFast
	GOOS=windows GOARCH=amd64 CGO_ENABLED=1 go build -ldflags="-s -w" -o bin/deraine-db-windows.exe ./cmd/derained

clean:
	@echo "=> Cleaning workspace..."
	rm -rf bin/
	rm -rf core/zig-cache/
	rm -rf core/zig-out/
	rm -f test_bridge.drb
	rm -f *.drb *.dridx

run: all
	@echo "=> Executing DeraineDB..."
	./bin/deraine-db