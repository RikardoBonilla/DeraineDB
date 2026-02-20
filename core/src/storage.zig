const std = @import("std");
const root = @import("root.zig");

pub const StorageError = error{
    FileOpenError,
    FileCreateError,
    TruncateError,
    MapError,
    InvalidHeader,
    FileTooSmall,
    IndexOutOfBounds,
    VectorDeleted,
    LockFailed,
};

pub const Storage = struct {
    file: std.fs.File,
    memory: []align(4096) u8,
    header: *root.DeraineHeader,
    lock: std.Thread.RwLock = .{},

    pub fn create(path: []const u8) !Storage {
        var file = std.fs.cwd().createFile(path, .{ .read = true, .truncate = true }) catch |e| {
            std.debug.print("createFile error: {}\n", .{e});
            return StorageError.FileCreateError;
        };
        errdefer file.close();

        const initial_size = 64 * 1024;
        file.setEndPos(initial_size) catch |e| {
            std.debug.print("setEndPos error: {}\n", .{e});
            return StorageError.TruncateError;
        };

        const memory = std.posix.mmap(
            null,
            initial_size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            file.handle,
            0,
        ) catch |e| {
            std.debug.print("mmap error: {}\n", .{e});
            return StorageError.MapError;
        };

        const header = @as(*root.DeraineHeader, @ptrCast(memory.ptr));
        header.* = .{
            .magic = "DERAINE\x00".*,
            .version = 1,
            .vector_size = 64,
            .vector_count = 0,
            .data_start_offset = 4096,
            .reserved = [_]u8{0} ** 32,
        };

        return Storage{
            .file = file,
            .memory = memory,
            .header = header,
            .lock = .{},
        };
    }

    pub fn open(path: []const u8) !Storage {
        const file = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch return StorageError.FileOpenError;
        const stat = try file.stat();

        if (stat.size < @sizeOf(root.DeraineHeader)) {
            return StorageError.FileTooSmall;
        }

        const memory = std.posix.mmap(
            null,
            stat.size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            file.handle,
            0,
        ) catch return StorageError.MapError;

        const header = @as(*root.DeraineHeader, @ptrCast(memory.ptr));

        if (!std.mem.eql(u8, &header.magic, "DERAINE\x00")) {
            return StorageError.InvalidHeader;
        }

        return Storage{
            .file = file,
            .memory = memory,
            .header = header,
            .lock = .{},
        };
    }

    const c = @cImport({
        @cInclude("sys/mman.h");
    });

    pub fn deinit(self: *Storage) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.internal_sync() catch {};
        std.posix.munmap(self.memory);
        self.file.close();
    }

    fn internal_sync(self: *Storage) StorageError!void {
        std.posix.msync(
            self.memory,
            c.MS_SYNC,
        ) catch return StorageError.MapError;
    }

    pub fn sync(self: *Storage) StorageError!void {
        self.lock.lockShared();
        defer self.lock.unlockShared();
        return self.internal_sync();
    }

    pub fn resize(self: *Storage, new_size: usize) !void {
        if (new_size <= self.memory.len) return;

        _ = self.internal_sync() catch {};

        std.posix.munmap(self.memory);

        self.file.setEndPos(new_size) catch return StorageError.TruncateError;

        const new_memory = std.posix.mmap(
            null,
            new_size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            self.file.handle,
            0,
        ) catch return StorageError.MapError;

        self.memory = new_memory;
        self.header = @as(*root.DeraineHeader, @ptrCast(self.memory.ptr));
    }

    pub fn writeVector(self: *Storage, index: u64, tag: u32, data: []const f32) !void {
        self.lock.lock();
        defer self.lock.unlock();

        const header_size = @sizeOf(root.DeraineHeader);
        const vector_size = 64;
        const offset = header_size + (index * vector_size);

        if (offset + vector_size > self.memory.len) {
            var new_capacity = self.memory.len;
            while (offset + vector_size > new_capacity) {
                new_capacity *= 2;
            }
            try self.resize(new_capacity);
        }

        const block = self.memory[offset .. offset + vector_size];

        const meta = @as(*root.DeraineVector, @ptrCast(@alignCast(block.ptr)));
        meta.id = index;
        meta.tag = tag;
        meta.status = 0x00;

        const data_dest = @as([*]f32, @ptrCast(@alignCast(&meta.padding[0])));
        @memcpy(data_dest[0..data.len], data);

        if (index >= self.header.vector_count) {
            self.header.vector_count = index + 1;
        }
    }

    pub fn readVector(self: *Storage, index: u64) ![]const f32 {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        if (index >= self.header.vector_count) return StorageError.IndexOutOfBounds;

        const header_size = @sizeOf(root.DeraineHeader);
        const vector_size = 64;
        const offset = header_size + (index * vector_size);

        const block = self.memory[offset .. offset + vector_size];
        const meta = @as(*root.DeraineVector, @ptrCast(@alignCast(block.ptr)));

        if (meta.status == 0x01) {
            return StorageError.VectorDeleted;
        }

        const dim = 4;
        const data_ptr = @as([*]const f32, @ptrCast(@alignCast(&meta.padding[0])));
        return data_ptr[0..dim];
    }

    pub fn deleteVector(self: *Storage, index: u64) !void {
        self.lock.lock();
        defer self.lock.unlock();

        if (index >= self.header.vector_count) return StorageError.IndexOutOfBounds;

        const header_size = @sizeOf(root.DeraineHeader);
        const vector_size = 64;
        const offset = header_size + (index * vector_size);

        const block = self.memory[offset .. offset + vector_size];
        const meta = @as(*root.DeraineVector, @ptrCast(@alignCast(block.ptr)));

        meta.status = 0x01;
    }

    inline fn euclideanDistanceSIMD(a: []const f32, b: []const f32) f32 {
        var sum: f32 = 0;
        var i: usize = 0;
        const vec_len = 4;

        while (i + vec_len <= a.len) : (i += vec_len) {
            const va: @Vector(vec_len, f32) = a[i .. i + vec_len][0..vec_len].*;
            const vb: @Vector(vec_len, f32) = b[i .. i + vec_len][0..vec_len].*;
            const diff = va - vb;
            const squared = diff * diff;
            sum += @reduce(.Add, squared);
        }

        while (i < a.len) : (i += 1) {
            const diff = a[i] - b[i];
            sum += diff * diff;
        }

        return std.math.sqrt(sum);
    }

    pub fn search(
        self: *Storage,
        query: []const f32,
        filter_tag: u32,
        k: u32,
        out_ids: [*]u64,
        out_distances: [*]f32,
    ) !usize {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        const header_size = @sizeOf(root.DeraineHeader);
        const vector_size = 64;
        const dim: usize = 4;

        var count: usize = 0;

        for (0..self.header.vector_count) |i| {
            const offset = header_size + (i * vector_size);
            const block = self.memory[offset .. offset + vector_size];
            const meta = @as(*root.DeraineVector, @ptrCast(@alignCast(block.ptr)));

            if (meta.status == 0x01) continue;
            if (filter_tag != 0 and meta.tag != filter_tag) continue;

            const data_ptr = @as([*]const f32, @ptrCast(@alignCast(&meta.padding[0])));
            const dist = euclideanDistanceSIMD(query, data_ptr[0..dim]);

            if (count < k) {
                out_ids[count] = meta.id;
                out_distances[count] = dist;
                count += 1;

                var j = count - 1;
                while (j > 0 and out_distances[j - 1] > out_distances[j]) : (j -= 1) {
                    std.mem.swap(f32, &out_distances[j - 1], &out_distances[j]);
                    std.mem.swap(u64, &out_ids[j - 1], &out_ids[j]);
                }
            } else if (dist < out_distances[k - 1]) {
                out_ids[k - 1] = meta.id;
                out_distances[k - 1] = dist;

                var j = k - 1;
                while (j > 0 and out_distances[j - 1] > out_distances[j]) : (j -= 1) {
                    std.mem.swap(f32, &out_distances[j - 1], &out_distances[j]);
                    std.mem.swap(u64, &out_ids[j - 1], &out_ids[j]);
                }
            }
        }

        return count;
    }
};
