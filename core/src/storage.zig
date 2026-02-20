const std = @import("std");
const root = @import("root.zig");

pub const StorageError = error{
    FileOpenError,
    FileCreateError,
    TruncateError,
    MapError,
    InvalidHeader,
    FileTooSmall,
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

    pub fn deinit(self: *Storage) void {
        std.posix.munmap(self.memory);
        self.file.close();
    }

    pub fn writeVector(self: *Storage, index: u64, data: []const f32) !void {
        const header_size = @sizeOf(root.DeraineHeader);
        const vector_size = 64;
        const offset = header_size + (index * vector_size);

        if (offset + vector_size > self.memory.len) {
            return error.MemoryBoundaryExceeded;
        }

        const destination = @as([*]f32, @ptrCast(@alignCast(self.memory.ptr + offset)));

        @memcpy(destination[0..data.len], data);

        if (index >= self.header.vector_count) {
            self.header.vector_count = index + 1;
        }
    }
};
