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
};

pub const Storage = struct {
    file: std.fs.File,
    memory: []align(4096) u8,
    header: *root.DeraineHeader,

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
        };
    }

    const c = @cImport({
        @cInclude("sys/mman.h");
    });

    pub fn deinit(self: *Storage) void {
        self.sync() catch {};
        std.posix.munmap(self.memory);
        self.file.close();
    }

    pub fn sync(self: *Storage) StorageError!void {
        std.posix.msync(
            self.memory,
            c.MS_SYNC,
        ) catch return StorageError.MapError;
    }

    pub fn resize(self: *Storage, new_size: usize) !void {
        if (new_size <= self.memory.len) return;

        _ = self.sync() catch {};

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

    pub fn writeVector(self: *Storage, index: u64, data: []const f32) !void {
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
        meta.status = 0x00;

        const data_dest = @as([*]f32, @ptrCast(@alignCast(&meta.padding[0])));
        @memcpy(data_dest[0..data.len], data);

        if (index >= self.header.vector_count) {
            self.header.vector_count = index + 1;
        }
    }

    pub fn readVector(self: *Storage, index: u64) ![]const f32 {
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
        if (index >= self.header.vector_count) return StorageError.IndexOutOfBounds;

        const header_size = @sizeOf(root.DeraineHeader);
        const vector_size = 64;
        const offset = header_size + (index * vector_size);

        const block = self.memory[offset .. offset + vector_size];
        const meta = @as(*root.DeraineVector, @ptrCast(@alignCast(block.ptr)));

        meta.status = 0x01;
    }
};
