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
    padding: [39]u8,

    comptime {
        if (@sizeOf(DeraineVector) != 64) {
            @compileError("DeraineVector must be exactly 64 bytes for SIMD optimization");
        }
    }
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

export fn deraine_write_vector(storage_ptr: *storage.Storage, index: u64, data_ptr: [*]const f32, len: u32) i32 {
    const data = data_ptr[0..len];

    storage_ptr.writeVector(index, data) catch |err| {
        std.debug.print("Write Error: {}\n", .{err});
        if (err == storage.StorageError.IndexOutOfBounds) return -3;
        return -1;
    };

    return 0;
}

export fn deraine_read_vector(storage_ptr: *storage.Storage, index: u64, out_data: *[*]const f32) i32 {
    if (storage_ptr.readVector(index)) |data_slice| {
        out_data.* = data_slice.ptr;
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
