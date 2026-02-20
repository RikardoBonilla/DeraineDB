const std = @import("std");
pub const storage = @import("storage.zig");

pub const DeraineHeader = extern struct {
    magic: [8]u8,
    version: u32,
    vector_size: u32,
    vector_count: u64,
    data_start_offset: u64,

    reserved: [32]u8,

    comptime {
        if (@sizeOf(DeraineHeader) != 64) {
            @compileError("DeraineHeader must be exactly 64 bytes");
        }
    }
};

pub const DeraineVector = extern struct {
    id: u64,
    dimensions: u32,
    reserved: u32,
    data_offset: u64,
    status: u8,
    align_pad: [3]u8,
    tag: u32,
    padding: [32]u8,

    comptime {
        if (@sizeOf(DeraineVector) != 64) {
            @compileError("DeraineVector must be exactly 64 bytes for SIMD optimization");
        }
    }
};

pub const HNSW_M = 16; // Max connections per layer
pub const HNSW_EF_CONSTRUCTION = 128;
pub const HNSW_MAX_LEVEL = 16;

pub const IndexHeader = extern struct {
    magic: [8]u8,
    version: u32,
    entry_point_id: u64,
    max_level: i32,
    m_value: u32,
    padding: [32]u8,

    comptime {
        if (@sizeOf(IndexHeader) != 64) {
            @compileError("IndexHeader must be exactly 64 bytes");
        }
    }
};

// Adjacency block for a single vector at a single level
pub const AdjacencyBlock = extern struct {
    neighbor_count: u32,
    neighbors: [HNSW_M]u64,
    padding: [60]u8, // Total 4 + 128 + 60 = 192 bytes. Aligned to 64.
};

pub const IndexNode = extern struct {
    max_level: i32,
    // Each node can have up to HNSW_MAX_LEVEL levels.
    layers: [HNSW_MAX_LEVEL]AdjacencyBlock,

    comptime {
        const expected_size = @sizeOf(i32) + (@sizeOf(AdjacencyBlock) * HNSW_MAX_LEVEL);
        _ = expected_size;
    }
};

pub const SearchMode = enum(i32) {
    Flat = 0,
    HNSW = 1,
};

export fn deraine_init() i32 {
    return 0;
}

export fn deraine_version() i32 {
    return 1;
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

export fn deraine_open_db(path: [*:0]const u8) ?*storage.Storage {
    const allocator = gpa.allocator();
    const path_slice = std.mem.span(path);
    const store = allocator.create(storage.Storage) catch {
        return null;
    };

    if (storage.Storage.open(path_slice)) |opened_store| {
        store.* = opened_store;
    } else |_| {
        if (storage.Storage.create(path_slice)) |created_store| {
            store.* = created_store;
        } else |_| {
            allocator.destroy(store);
            return null;
        }
    }

    return store;
}

export fn deraine_close_db(storage_ptr: *storage.Storage) void {
    storage_ptr.deinit();
    const allocator = gpa.allocator();
    allocator.destroy(storage_ptr);
}

export fn deraine_sync(storage_ptr: *storage.Storage) i32 {
    storage_ptr.sync() catch |err| {
        std.debug.print("Sync Error: {}\n", .{err});
        return -1;
    };
    return 0;
}

export fn deraine_write_vector(storage_ptr: *storage.Storage, index: u64, tag: u32, data_ptr: [*]const f32, len: u32) i32 {
    const data = data_ptr[0..len];

    storage_ptr.writeVector(index, tag, data) catch |err| {
        std.debug.print("Write Error: {}\n", .{err});
        if (err == storage.StorageError.IndexOutOfBounds) return -3;
        return -1;
    };

    return 0;
}

export fn deraine_read_vector(storage_ptr: *storage.Storage, index: u64, out_data: [*]f32, out_len: u32) i32 {
    if (storage_ptr.readVector(index)) |data_slice| {
        const copy_len = @min(out_len, @as(u32, @intCast(data_slice.len)));
        @memcpy(out_data[0..copy_len], data_slice[0..copy_len]);
        return 0;
    } else |err| {
        return switch (err) {
            storage.StorageError.VectorDeleted => -2,
            storage.StorageError.IndexOutOfBounds => -3,
            else => -1,
        };
    }
}

export fn deraine_delete_vector(storage_ptr: *storage.Storage, index: u64) i32 {
    storage_ptr.deleteVector(index) catch |err| {
        std.debug.print("Delete Error: {}\n", .{err});
        return switch (err) {
            storage.StorageError.IndexOutOfBounds => -3,
            else => -1,
        };
    };
    return 0;
}

export fn deraine_search(
    storage_ptr: *storage.Storage,
    query_ptr: [*]const f32,
    query_len: u32,
    filter_tag: u32,
    k: u32,
    out_ids: [*]u64,
    out_distances: [*]f32,
    mode: i32,
) i32 {
    const query = query_ptr[0..query_len];
    const search_mode: SearchMode = @enumFromInt(mode);

    const matches = storage_ptr.search(query, filter_tag, k, out_ids, out_distances, search_mode) catch |err| {
        std.debug.print("Search Error: {}\n", .{err});
        return -1;
    };

    return @as(i32, @intCast(matches));
}
