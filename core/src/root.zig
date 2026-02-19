const std = @import("std");
pub const storage = @import("storage.zig");

/// DeraineHeader: Main database file header.
/// Located at offset 0 of the .drb file.
pub const DeraineHeader = extern struct {
    magic: [8]u8, // 0-8: Unique format identifier ("DERAINE\x00")
    version: u32, // 8-12: Layout version
    vector_size: u32, // 12-16: Size of DeraineVector struct (sanity check)
    vector_count: u64, // 16-24: Total stored vectors
    data_start_offset: u64, // 24-32: Start of data section

    reserved: [32]u8, // 32-64: Padding to ensure 64-byte alignment

    comptime {
        if (@sizeOf(DeraineHeader) != 64) {
            @compileError("DeraineHeader must be exactly 64 bytes");
        }
    }
};

/// DeraineVector: Fundamental storage unit.
/// Uses 'extern struct' to guarantee identical memory layout across Zig, C, and Go.
/// aligned to 64 bytes to match cache lines on modern processors.
pub const DeraineVector = extern struct {
    id: u64, // 0-8: Unique vector ID
    dimensions: u32, // 8-12: Number of dimensions
    reserved: u32, // 12-16: Padding for alignment
    data_offset: u64, // 16-24: Relative offset in mmap where floats reside

    padding: [40]u8, // 24-64: Padding to complete 64-byte cache line

    comptime {
        if (@sizeOf(DeraineVector) != 64) {
            @compileError("DeraineVector must be exactly 64 bytes for SIMD optimization");
        }
    }
};

// --- CGO Bridge Exports ---

/// Initializes the core engine. Returns 0 on success.
export fn deraine_init() i32 {
    return 0;
}

/// Returns the core version.
export fn deraine_version() i32 {
    return 1;
}

/// Creates a new database from Go.
/// path: Null-terminated C string.
export fn deraine_create_db(path: [*:0]const u8) i32 {
    const path_slice = std.mem.span(path);

    var store = storage.Storage.create(path_slice) catch |err| {
        std.debug.print("Error creating DB: {}\n", .{err});
        return -1;
    };
    // Close immediately for testing purposes
    store.deinit();
    return 0;
}

/// Opens an existing database from Go.
/// path: Null-terminated C string.
export fn deraine_open_db(path: [*:0]const u8) i32 {
    const path_slice = std.mem.span(path);

    var store = storage.Storage.open(path_slice) catch |err| {
        std.debug.print("Error opening DB: {}\n", .{err});
        return -1;
    };
    store.deinit();
    return 0;
}
