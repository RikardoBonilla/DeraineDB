const std = @import("std");
const root = @import("root.zig");
const storage = @import("storage.zig");

test "Storage Creation & Open" {
    const test_path = "test_db.drb";
    defer std.fs.cwd().deleteFile(test_path) catch {}; // Cleanup

    // 1. Create DB
    {
        var s = try storage.Storage.create(test_path);
        defer s.deinit();

        try std.testing.expect(s.header.version == 1);
        try std.testing.expect(s.header.vector_count == 0);
        try std.testing.expect(s.header.data_start_offset % 4096 == 0);

        s.header.vector_count = 123;
    }

    // 2. Open DB (Persistence Check)
    {
        var s = try storage.Storage.open(test_path);
        defer s.deinit();

        try std.testing.expectEqual(@as(u64, 123), s.header.vector_count);
        try std.testing.expectEqualStrings("DERAINE\x00", &s.header.magic);
    }
}
