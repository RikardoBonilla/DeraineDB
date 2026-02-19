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

    /// Creates a new database file and initializes the header.
    pub fn create(path: []const u8) !Storage {
        // Create with .read=true to allow mmap PROT.READ
        const file = std.fs.cwd().createFile(path, .{ .read = true, .exclusive = true }) catch return StorageError.FileCreateError;
        errdefer file.close();

        const initial_size = 64 * 1024;
        try file.setEndPos(initial_size);

        const memory = std.posix.mmap(
            null,
            initial_size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            file.handle,
            0,
        ) catch return StorageError.MapError;

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

    /// Opens an existing database file and validates the header.
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
};
