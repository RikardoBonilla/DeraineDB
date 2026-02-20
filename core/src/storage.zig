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

    index_file: std.fs.File,
    index_memory: []align(4096) u8,
    index_header: *root.IndexHeader,

    lock: std.Thread.RwLock = .{},

    pub fn create(path: []const u8) !Storage {
        var file = std.fs.cwd().createFile(path, .{ .read = true, .truncate = true }) catch |e| {
            std.debug.print("createFile error: {}\n", .{e});
            return StorageError.FileCreateError;
        };
        errdefer file.close();

        const initial_size = 64 * 1024;
        file.setEndPos(initial_size) catch return StorageError.TruncateError;

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

        // Create Index File (.dridx)
        var idx_path_buf: [256]u8 = undefined;
        const idx_path = try std.fmt.bufPrint(&idx_path_buf, "{s}.dridx", .{path});
        var idx_file = try std.fs.cwd().createFile(idx_path, .{ .read = true, .truncate = true });
        errdefer idx_file.close();

        const idx_initial_size = 1024 * 1024; // 1MB initial for index
        try idx_file.setEndPos(idx_initial_size);

        const idx_memory = std.posix.mmap(
            null,
            idx_initial_size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            idx_file.handle,
            0,
        ) catch return StorageError.MapError;

        const idx_header = @as(*root.IndexHeader, @ptrCast(idx_memory.ptr));
        idx_header.* = .{
            .magic = "DR_INDEX".*,
            .version = 1,
            .entry_point_id = 0,
            .max_level = -1,
            .m_value = root.HNSW_M,
            .padding = [_]u8{0} ** 32,
        };

        return Storage{
            .file = file,
            .memory = memory,
            .header = header,
            .index_file = idx_file,
            .index_memory = idx_memory,
            .index_header = idx_header,
            .lock = .{},
        };
    }

    pub fn open(path: []const u8) !Storage {
        const file = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch return StorageError.FileOpenError;
        errdefer file.close();
        const stat = try file.stat();

        if (stat.size < @sizeOf(root.DeraineHeader)) return StorageError.FileTooSmall;

        const memory = std.posix.mmap(
            null,
            stat.size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            file.handle,
            0,
        ) catch return StorageError.MapError;

        const header = @as(*root.DeraineHeader, @ptrCast(memory.ptr));
        if (!std.mem.eql(u8, &header.magic, "DERAINE\x00")) return StorageError.InvalidHeader;

        // Open Index File (.dridx)
        var idx_path_buf: [256]u8 = undefined;
        const idx_path = try std.fmt.bufPrint(&idx_path_buf, "{s}.dridx", .{path});
        const idx_file = std.fs.cwd().openFile(idx_path, .{ .mode = .read_write }) catch return StorageError.FileOpenError;
        errdefer idx_file.close();
        const idx_stat = try idx_file.stat();

        const idx_memory = std.posix.mmap(
            null,
            idx_stat.size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            idx_file.handle,
            0,
        ) catch return StorageError.MapError;

        const idx_header = @as(*root.IndexHeader, @ptrCast(idx_memory.ptr));
        if (!std.mem.eql(u8, &idx_header.magic, "DR_INDEX")) return StorageError.InvalidHeader;

        return Storage{
            .file = file,
            .memory = memory,
            .header = header,
            .index_file = idx_file,
            .index_memory = idx_memory,
            .index_header = idx_header,
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
        std.posix.munmap(self.index_memory);
        self.file.close();
        self.index_file.close();
    }

    fn internal_sync(self: *Storage) StorageError!void {
        std.posix.msync(self.memory, c.MS_SYNC) catch return StorageError.MapError;
        std.posix.msync(self.index_memory, c.MS_SYNC) catch return StorageError.MapError;
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
        const new_memory = std.posix.mmap(null, new_size, std.posix.PROT.READ | std.posix.PROT.WRITE, .{ .TYPE = .SHARED }, self.file.handle, 0) catch return StorageError.MapError;
        self.memory = new_memory;
        self.header = @as(*root.DeraineHeader, @ptrCast(self.memory.ptr));
    }

    pub fn resizeIndex(self: *Storage, new_size: usize) !void {
        if (new_size <= self.index_memory.len) return;
        _ = self.internal_sync() catch {};
        std.posix.munmap(self.index_memory);
        self.index_file.setEndPos(new_size) catch return StorageError.TruncateError;
        const new_memory = std.posix.mmap(null, new_size, std.posix.PROT.READ | std.posix.PROT.WRITE, .{ .TYPE = .SHARED }, self.index_file.handle, 0) catch return StorageError.MapError;
        self.index_memory = new_memory;
        self.index_header = @as(*root.IndexHeader, @ptrCast(self.index_memory.ptr));
    }

    fn getIndexNode(self: *Storage, index: u64) *root.IndexNode {
        const header_size = @sizeOf(root.IndexHeader);
        const node_size = @sizeOf(root.IndexNode);
        const offset = header_size + (index * node_size);
        // Ensure index memory is large enough
        if (offset + node_size > self.index_memory.len) {
            // This should be handled by the caller or a resize call
        }
        return @as(*root.IndexNode, @ptrCast(@alignCast(&self.index_memory[offset])));
    }

    fn getRandomLevel() i32 {
        var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp())));
        const random = prng.random();

        var level: i32 = 0;
        const p: f32 = 0.5; // Probability factor for decay
        while (random.float(f32) < p and level < root.HNSW_MAX_LEVEL - 1) {
            level += 1;
        }
        return level;
    }

    // SIMD-Accelerated Greedy Search in a single layer
    fn searchLayer(self: *Storage, query: []const f32, entry_id: u64, layer: i32) u64 {
        var current_id = entry_id;
        var current_dist = self.getDistance(query, current_id) catch 999999.0;
        var changed = true;

        while (changed) {
            changed = false;
            const node = self.getIndexNode(current_id);
            const adj = &node.layers[@as(usize, @intCast(layer))];

            for (0..adj.neighbor_count) |i| {
                const neighbor_id = adj.neighbors[i];
                const d = self.getDistance(query, neighbor_id) catch 999999.0;
                if (d < current_dist) {
                    current_dist = d;
                    current_id = neighbor_id;
                    changed = true;
                }
            }
        }
        return current_id;
    }

    fn getDistance(self: *Storage, query: []const f32, target_id: u64) !f32 {
        // Safe read from mmap
        const header_size = @sizeOf(root.DeraineHeader);
        const vector_size = 64;
        const offset = header_size + (target_id * vector_size);
        const block = self.memory[offset .. offset + vector_size];
        const meta = @as(*root.DeraineVector, @ptrCast(@alignCast(block.ptr)));
        const data_ptr = @as([*]const f32, @ptrCast(@alignCast(&meta.padding[0])));
        return euclideanDistanceSIMD(query, data_ptr[0..4]);
    }

    pub fn insertVectorHNSW(self: *Storage, index: u64, query: []const f32) !void {
        // 1. Determine level
        const level = getRandomLevel();
        const node = self.getIndexNode(index);
        node.max_level = level;

        // Reset adjacency blocks for the new node
        for (0..root.HNSW_MAX_LEVEL) |l| {
            node.layers[l].neighbor_count = 0;
        }

        if (self.index_header.max_level == -1) {
            self.index_header.entry_point_id = index;
            self.index_header.max_level = level;
            return;
        }

        var current_entry = self.index_header.entry_point_id;
        const current_max_level = self.index_header.max_level;

        // 2. Search from top to new vector's level
        var l = current_max_level;
        while (l > level) : (l -= 1) {
            current_entry = self.searchLayer(query, current_entry, l);
        }

        // 3. Insert and connect at each level from min(level, current_max) down to 0
        l = @min(level, current_max_level);
        while (l >= 0) : (l -= 1) {
            // Greedy find closest for this layer
            current_entry = self.searchLayer(query, current_entry, l);

            // Connect New -> Entry (Simplified: just connect to one for now)
            // In a full HNSW, we maintain a list of candidates.
            const target_node = self.getIndexNode(current_entry);
            const target_adj = &target_node.layers[@as(usize, @intCast(l))];

            if (target_adj.neighbor_count < root.HNSW_M) {
                target_adj.neighbors[target_adj.neighbor_count] = index;
                target_adj.neighbor_count += 1;
            }

            const my_adj = &node.layers[@as(usize, @intCast(l))];
            my_adj.neighbors[0] = current_entry;
            my_adj.neighbor_count = 1;

            if (l == 0) break;
        }

        if (level > current_max_level) {
            self.index_header.max_level = level;
            self.index_header.entry_point_id = index;
        }
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

        // Ensure index memory is enough
        const idx_header_size = @sizeOf(root.IndexHeader);
        const idx_node_size = @sizeOf(root.IndexNode);
        const idx_offset = idx_header_size + (index * idx_node_size);
        if (idx_offset + idx_node_size > self.index_memory.len) {
            var new_idx_capacity = self.index_memory.len;
            while (idx_offset + idx_node_size > new_idx_capacity) {
                new_idx_capacity *= 2;
            }
            try self.resizeIndex(new_idx_capacity);
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

        // Trigger HNSW Insertion
        try self.insertVectorHNSW(index, data);
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

    pub fn search(
        self: *Storage,
        query: []const f32,
        filter_tag: u32,
        k: u32,
        out_ids: [*]u64,
        out_distances: [*]f32,
        mode: root.SearchMode,
    ) !usize {
        if (mode == .Flat or self.index_header.max_level == -1) {
            return self.searchFlat(query, filter_tag, k, out_ids, out_distances);
        }
        return self.searchHNSW(query, filter_tag, k, out_ids, out_distances);
    }

    fn searchHNSW(
        self: *Storage,
        query: []const f32,
        filter_tag: u32,
        k: u32,
        out_ids: [*]u64,
        out_distances: [*]f32,
    ) !usize {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        var current_entry = self.index_header.entry_point_id;
        var l = self.index_header.max_level;
        while (l > 0) : (l -= 1) {
            current_entry = self.searchLayer(query, current_entry, l);
        }

        // In layer 0, we do a greedy search or collect Top-K.
        // For v2.0 MVP, let's keep search simple: find the closest, then collect its neighbors.
        const final_id = self.searchLayer(query, current_entry, 0);

        // Collect Top-K from neighbors of the final winner
        const node = self.getIndexNode(final_id);
        const adj = &node.layers[0];

        var count: usize = 0;

        // Add the winner itself
        out_ids[0] = final_id;
        out_distances[0] = try self.getDistance(query, final_id);
        count = 1;

        for (0..adj.neighbor_count) |i| {
            if (count >= k) break;
            const nid = adj.neighbors[i];
            out_ids[count] = nid;
            out_distances[count] = try self.getDistance(query, nid);
            count += 1;
        }

        _ = filter_tag; // TO-DO: Implement HNSW filtering
        return count;
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

    fn searchFlat(
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
