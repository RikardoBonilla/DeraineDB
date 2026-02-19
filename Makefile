# Variables de configuración
ZIG_LIB_DIR = core/zig-out/lib
INCLUDE_DIR = include
BINARY_NAME = bin/luminad

# Flags para que Go encuentre a Zig
export CGO_CFLAGS = -I$(shell pwd)/$(INCLUDE_DIR)
export CGO_LDFLAGS = -L$(shell pwd)/$(ZIG_LIB_DIR) -lcore

.PHONY: all core build clean

all: core build

# 1. Compilar Zig como librería estática (.a)
core:
	@echo "[METAL] Compilando Core en Zig..."
	cd core && zig build -Doptimize=ReleaseFast
	@echo "[METAL] Copiando headers..."
	cp core/zig-out/include/lumina_core.h include/

# 2. Compilar Go vinculando la librería de Zig
build:
	@echo "[LOGIC] Compilando Orquestador en Go..."
	mkdir -p bin
	go build -o $(BINARY_NAME) ./cmd/luminad

clean:
	rm -rf bin/
	cd core && rm -rf zig-out/ zig-cache/