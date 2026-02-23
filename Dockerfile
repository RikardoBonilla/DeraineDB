# Header: DeraineDB Production Image v2.0-stable

# --- Stage 1: Build Stage ---
# Using golang:1.25-alpine to match go.mod compliance
FROM golang:1.25-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    curl \
    xz \
    build-base \
    git

# Install Zig 0.13.0 (Stable target for production)
RUN curl -O https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz && \
    mkdir -p /usr/local/zig && \
    tar -xf zig-linux-x86_64-0.13.0.tar.xz -C /usr/local/zig --strip-components=1 && \
    ln -s /usr/local/zig/zig /usr/bin/zig && \
    rm zig-linux-x86_64-0.13.0.tar.xz

WORKDIR /app

# Copy dependency files first
COPY go.mod go.sum ./
# Copy local modules (needed for 'replace' directives in go.mod)
COPY api/ ./api/
RUN go mod download

# Copy the rest of the source
COPY . .

# Apply Zig 0.13.0 Compatibility Patch for Docker Build
RUN cp core/build_0_13.zig core/build.zig && \
    cp core/build_0_13.zig.zon core/build.zig.zon

# Build Zig Core
RUN cd core && zig build -Doptimize=ReleaseFast

# Build Go Server with CGO_ENABLED=1 to link with the Zig library
# CGO_CFLAGS and CGO_LDFLAGS are picked up from #cgo directives in main.go
RUN CGO_ENABLED=1 go build -a -ldflags="-s -w" -o bin/deraine-db ./cmd/derained

# --- Stage 2: Final Stage ---
FROM alpine:latest

# Install runtime dependencies (like libc)
RUN apk add --no-cache ca-certificates libc6-compat

WORKDIR /app

# Copy the binary from the builder stage
COPY --from=builder /app/bin/deraine-db .

# Copy UI and assets (Verified paths during audit)
COPY internal/server/admin_ui.html ./internal/server/admin_ui.html
COPY assets ./assets

# Setup data directory for persistence
RUN mkdir -p /app/data
VOLUME /app/data

# Environment variables
ENV DERAINE_DB_DATA_DIR=/app/data
ENV DERAINE_DB_PORT=50051

# Expose gRPC and Metrics/Admin ports
EXPOSE 50051 9090

# Execute the engine
ENTRYPOINT ["./deraine-db"]
