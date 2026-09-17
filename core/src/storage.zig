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
    allocator: std.mem.Allocator,
    base_path: []const u8,
    file: std.fs.File,
    memory: []align(4096) u8,
    header: *root.DeraineHeader,

    index_file: std.fs.File,
    index_memory: []align(4096) u8,
    index_header: *root.IndexHeader,

    lock: std.Thread.RwLock = .{},

    pub fn create(allocator: std.mem.Allocator, path: []const u8) !Storage {
        var file = std.fs.cwd().createFile(path, .{ .read = true, .truncate = true }) catch |e| {
            std.debug.print("createFile error: {}\n", .{e});
            return StorageError.FileCreateError;
        };
        errdefer file.close();

        const initial_size = 64 * 1024 * 1024;
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
            .vector_size = root.VECTOR_SIZE,
            .vector_count = 0,
            .data_start_offset = 4096,
            .reserved = [_]u8{0} ** 32,
        };

        var idx_path_buf: [256]u8 = undefined;
        const idx_path = try std.fmt.bufPrint(&idx_path_buf, "{s}.dridx", .{path});
        var idx_file = try std.fs.cwd().createFile(idx_path, .{ .read = true, .truncate = true });
        errdefer idx_file.close();

        const idx_initial_size = 1024 * 1024;
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
            .allocator = allocator,
            .base_path = try allocator.dupe(u8, path),
            .file = file,
            .memory = memory,
            .header = header,
            .index_file = idx_file,
            .index_memory = idx_memory,
            .index_header = idx_header,
            .lock = .{},
        };
    }

    pub fn open(allocator: std.mem.Allocator, path: []const u8) !Storage {
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
            .allocator = allocator,
            .base_path = try allocator.dupe(u8, path),
            .file = file,
            .memory = memory,
            .header = header,
            .index_file = idx_file,
            .index_memory = idx_memory,
            .index_header = idx_header,
            .lock = .{},
        };
    }

    pub fn deinit(self: *Storage) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.internal_sync() catch {};
        std.posix.munmap(self.memory);
        std.posix.munmap(self.index_memory);
        self.file.close();
        self.index_file.close();
        self.allocator.free(self.base_path);
    }

    fn internal_sync(self: *Storage) StorageError!void {
        const ms_sync = comptime blk: {
            if (@hasDecl(std.posix, "MS_SYNC")) break :blk @as(u32, std.posix.MS_SYNC);
            if (@hasDecl(std.posix, "MS")) if (@hasDecl(std.posix.MS, "SYNC")) break :blk @as(u32, std.posix.MS.SYNC);

            if (@hasDecl(std.os, "MS_SYNC")) break :blk @as(u32, std.os.MS_SYNC);
            if (@hasDecl(std.os, "MS")) if (@hasDecl(std.os.MS, "SYNC")) break :blk @as(u32, std.os.MS.SYNC);

            if (@hasDecl(std.os.linux, "MS_SYNC")) break :blk @as(u32, std.os.linux.MS_SYNC);

            const os_tag = @import("builtin").target.os.tag;
            if (os_tag == .linux) break :blk 4;
            if (os_tag == .macos or os_tag == .ios or os_tag == .tvos or os_tag == .watchos) break :blk 16;

            break :blk 0;
        };
        std.posix.msync(self.memory, ms_sync) catch return StorageError.MapError;
        std.posix.msync(self.index_memory, ms_sync) catch return StorageError.MapError;
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

    pub fn createSnapshot(self: *Storage, target_path: []const u8) !void {
        self.lock.lock();
        defer self.lock.unlock();

        try self.internal_sync();

        var idx_source_buf: [512]u8 = undefined;
        const idx_source = try std.fmt.bufPrint(&idx_source_buf, "{s}.dridx", .{self.base_path});

        var drb_target_buf: [512]u8 = undefined;
        const drb_target = try std.fmt.bufPrint(&drb_target_buf, "{s}.drb", .{target_path});

        var idx_target_buf: [512]u8 = undefined;
        const idx_target = try std.fmt.bufPrint(&idx_target_buf, "{s}.dridx", .{target_path});

        try std.fs.cwd().copyFile(self.base_path, std.fs.cwd(), drb_target, .{});
        try std.fs.cwd().copyFile(idx_source, std.fs.cwd(), idx_target, .{});
    }

    pub fn rebuildIndex(self: *Storage) !void {
        self.lock.lock();
        defer self.lock.unlock();

        self.index_header.entry_point_id = 0;
        self.index_header.max_level = -1;

        var i: u64 = 0;
        const dim = root.VECTOR_DIMENSIONS;
        while (i < self.header.vector_count) : (i += 1) {
            const data = try self.readVectorInternal(i, dim);
            try self.insertVectorHNSW(i, data);
        }
    }

    fn readVectorInternal(self: *Storage, index: u64, dim: u32) ![]const f32 {
        const header_size = @sizeOf(root.DeraineHeader);
        const vector_size = self.header.vector_size;
        const offset = header_size + (index * vector_size);
        const block = self.memory[offset .. offset + vector_size];
        const meta = @as(*root.DeraineVector, @ptrCast(@alignCast(block.ptr)));
        if (meta.status == 0x01) return StorageError.VectorDeleted;
        const data_ptr = @as([*]const f32, @ptrCast(@alignCast(block.ptr + @sizeOf(root.DeraineVector))));
        return data_ptr[0..dim];
    }

    fn getIndexNode(self: *Storage, index: u64) *root.IndexNode {
        const header_size = @sizeOf(root.IndexHeader);
        const node_size = @sizeOf(root.IndexNode);
        const offset = header_size + (index * node_size);
        if (offset + node_size > self.index_memory.len) {}
        return @as(*root.IndexNode, @ptrCast(@alignCast(&self.index_memory[offset])));
    }

    /// Uses the process-wide CSPRNG instead of reseeding a PRNG from the
    /// millisecond clock on every call. Insertions happen faster than 1ms
    /// apart under any real load, so the old code handed out identical
    /// "random" sequences to many consecutive inserts, correlating the
    /// level assignment and breaking HNSW's expected level distribution.
    fn getRandomLevel() i32 {
        var level: i32 = 0;
        const p: f32 = 0.5;
        while (std.crypto.random.float(f32) < p and level < root.HNSW_MAX_LEVEL - 1) {
            level += 1;
        }
        return level;
    }

    /// Single-best greedy descent, used only to find an entry point when
    /// tunneling through upper layers where the new node won't get any
    /// edges (standard HNSW behavior - ef=1 is intentional there).
    fn searchLayer(self: *Storage, query: []const f32, entry_id: u64, layer: i32, filter_mask: u64) u64 {
        var current_id = entry_id;
        var current_dist = self.getDistance(query, current_id) catch 999999.0;
        var changed = true;

        while (changed) {
            changed = false;
            const node = self.getIndexNode(current_id);
            const adj = &node.layers[@as(usize, @intCast(layer))];

            for (0..adj.neighbor_count) |i| {
                const neighbor_id = adj.neighbors[i];

                if (filter_mask != 0) {
                    const m = self.getMetadataMask(neighbor_id);
                    if ((m & filter_mask) == 0) continue;
                }

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

    const Candidate = struct {
        id: u64,
        dist: f32,
    };

    // Bounds for the allocation-free beam search below. ef is always
    // clamped to MAX_EF, so these arrays cover the worst case without
    // needing a heap allocator in this hot path.
    const MAX_EF: usize = 256;
    const MAX_VISITED: usize = 4096;
    const MAX_CANDIDATES: usize = 1024;

    /// Real HNSW "SEARCH-LAYER": explores the graph from entry_id and
    /// returns up to `ef` nearest candidates found (sorted closest-first),
    /// instead of just the single greedy-best node. This is what lets
    /// insertion connect a new node to several real neighbors instead of
    /// one, and what lets queries recover from a mediocre single greedy
    /// path by keeping a wider beam of options.
    fn searchLayerCandidates(
        self: *Storage,
        query: []const f32,
        entry_id: u64,
        layer: i32,
        ef: usize,
        filter_mask: u64,
        out_results: []Candidate,
    ) usize {
        const ef_clamped = @min(ef, MAX_EF);

        var visited: [MAX_VISITED]u64 = undefined;
        var visited_count: usize = 0;

        var candidates: [MAX_CANDIDATES]Candidate = undefined;
        var candidates_count: usize = 0;

        var results: [MAX_EF]Candidate = undefined;
        var results_count: usize = 0;

        const entry_dist = self.getDistance(query, entry_id) catch 999999.0;
        candidates[0] = .{ .id = entry_id, .dist = entry_dist };
        candidates_count = 1;
        visited[0] = entry_id;
        visited_count = 1;
        results[0] = .{ .id = entry_id, .dist = entry_dist };
        results_count = 1;

        while (candidates_count > 0) {
            var min_idx: usize = 0;
            for (1..candidates_count) |i| {
                if (candidates[i].dist < candidates[min_idx].dist) min_idx = i;
            }
            const current = candidates[min_idx];
            candidates[min_idx] = candidates[candidates_count - 1];
            candidates_count -= 1;

            if (results_count >= ef_clamped) {
                var worst_idx: usize = 0;
                for (1..results_count) |i| {
                    if (results[i].dist > results[worst_idx].dist) worst_idx = i;
                }
                if (current.dist > results[worst_idx].dist) break;
            }

            const node = self.getIndexNode(current.id);
            const adj = &node.layers[@as(usize, @intCast(layer))];

            for (0..adj.neighbor_count) |i| {
                const neighbor_id = adj.neighbors[i];

                var already_visited = false;
                for (0..visited_count) |v| {
                    if (visited[v] == neighbor_id) {
                        already_visited = true;
                        break;
                    }
                }
                if (already_visited) continue;
                if (visited_count < visited.len) {
                    visited[visited_count] = neighbor_id;
                    visited_count += 1;
                }

                if (filter_mask != 0) {
                    const m = self.getMetadataMask(neighbor_id);
                    if ((m & filter_mask) == 0) continue;
                }

                const d = self.getDistance(query, neighbor_id) catch 999999.0;

                var worst_idx: usize = 0;
                for (1..results_count) |ri| {
                    if (results[ri].dist > results[worst_idx].dist) worst_idx = ri;
                }
                const should_add = results_count < ef_clamped or d < results[worst_idx].dist;
                if (!should_add) continue;

                if (candidates_count < candidates.len) {
                    candidates[candidates_count] = .{ .id = neighbor_id, .dist = d };
                    candidates_count += 1;
                }

                if (results_count < ef_clamped) {
                    results[results_count] = .{ .id = neighbor_id, .dist = d };
                    results_count += 1;
                } else {
                    results[worst_idx] = .{ .id = neighbor_id, .dist = d };
                }
            }
        }

        // Small insertion sort: results_count <= ef_clamped <= MAX_EF (256).
        var i: usize = 1;
        while (i < results_count) : (i += 1) {
            const key = results[i];
            var j = i;
            while (j > 0 and results[j - 1].dist > key.dist) : (j -= 1) {
                results[j] = results[j - 1];
            }
            results[j] = key;
        }

        const n = @min(results_count, out_results.len);
        for (0..n) |idx| out_results[idx] = results[idx];
        return n;
    }

    fn getDistance(self: *Storage, query: []const f32, target_id: u64) !f32 {
        const header_size = @sizeOf(root.DeraineHeader);
        const vector_size = self.header.vector_size;
        const offset = header_size + (target_id * vector_size);
        const block = self.memory[offset .. offset + vector_size];
        const data_ptr = @as([*]const f32, @ptrCast(@alignCast(block.ptr + @sizeOf(root.DeraineVector))));
        return euclideanDistanceSIMD(query, data_ptr[0..root.VECTOR_DIMENSIONS]);
    }

    /// Bidirectionally links target_id -> new_id at `layer`, pruning the
    /// target's weakest existing edge (from the target's own point of
    /// view) if it's already at capacity. This is what the old code never
    /// did: a node's neighbor list here can hold up to HNSW_M real
    /// neighbors instead of exactly one.
    fn addNeighborWithPruning(self: *Storage, target_id: u64, new_id: u64, layer: i32) void {
        const target_node = self.getIndexNode(target_id);
        const adj = &target_node.layers[@as(usize, @intCast(layer))];

        if (adj.neighbor_count < root.HNSW_M) {
            adj.neighbors[adj.neighbor_count] = new_id;
            adj.neighbor_count += 1;
            return;
        }

        const target_vec = self.readVectorInternal(target_id, root.VECTOR_DIMENSIONS) catch return;
        const dist_new = self.getDistance(target_vec, new_id) catch return;

        var worst_idx: usize = 0;
        var worst_dist: f32 = -1;
        for (0..adj.neighbor_count) |i| {
            const d = self.getDistance(target_vec, adj.neighbors[i]) catch continue;
            if (d > worst_dist) {
                worst_dist = d;
                worst_idx = i;
            }
        }

        if (dist_new < worst_dist) {
            adj.neighbors[worst_idx] = new_id;
        }
    }

    pub fn insertVectorHNSW(self: *Storage, index: u64, query: []const f32) !void {
        const level = getRandomLevel();
        const node = self.getIndexNode(index);
        node.max_level = level;

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

        var l = current_max_level;
        while (l > level) : (l -= 1) {
            current_entry = self.searchLayer(query, current_entry, l, 0);
        }

        l = @min(level, current_max_level);
        while (true) {
            var candidates: [MAX_EF]Candidate = undefined;
            const found = self.searchLayerCandidates(query, current_entry, l, root.HNSW_EF_CONSTRUCTION, 0, &candidates);

            const num_neighbors = @min(found, root.HNSW_M);
            const my_adj = &node.layers[@as(usize, @intCast(l))];
            my_adj.neighbor_count = 0;
            for (0..num_neighbors) |i| {
                my_adj.neighbors[my_adj.neighbor_count] = candidates[i].id;
                my_adj.neighbor_count += 1;
                self.addNeighborWithPruning(candidates[i].id, index, l);
            }

            if (found > 0) current_entry = candidates[0].id;

            if (l == 0) break;
            l -= 1;
        }

        if (level > current_max_level) {
            self.index_header.max_level = level;
            self.index_header.entry_point_id = index;
        }
    }

    pub fn writeVector(self: *Storage, index: u64, metadata_mask: u64, data: []const f32) !void {
        self.lock.lock();
        defer self.lock.unlock();

        const header_size = @sizeOf(root.DeraineHeader);
        const vector_size = self.header.vector_size;
        const offset = header_size + (index * vector_size);

        if (offset + vector_size > self.memory.len) {
            var new_capacity = self.memory.len;
            while (offset + vector_size > new_capacity) {
                new_capacity *= 2;
            }
            try self.resize(new_capacity);
        }

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
        meta.metadata_mask = metadata_mask;
        meta.status = 0x00;

        const data_dest = @as([*]f32, @ptrCast(@alignCast(block.ptr + @sizeOf(root.DeraineVector))));
        @memcpy(data_dest[0..data.len], data);

        if (index >= self.header.vector_count) {
            self.header.vector_count = index + 1;
        }

        try self.insertVectorHNSW(index, data);
    }

    /// Copies the vector at `index` into `out` while the shared lock is held
    /// ("Safe-Copy"). A concurrent writeVector can trigger resize(), which
    /// munmaps and remaps self.memory; a pointer into that memory returned
    /// after the lock is released would dangle the instant that happens, so
    /// the copy must happen in this locked scope, not in the caller.
    /// Returns the number of floats copied.
    pub fn readVector(self: *Storage, index: u64, out: []f32) !usize {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        if (index >= self.header.vector_count) return StorageError.IndexOutOfBounds;

        const header_size = @sizeOf(root.DeraineHeader);
        const vector_size = self.header.vector_size;
        const offset = header_size + (index * vector_size);

        const block = self.memory[offset .. offset + vector_size];
        const meta = @as(*root.DeraineVector, @ptrCast(@alignCast(block.ptr)));

        if (meta.status == 0x01) {
            return StorageError.VectorDeleted;
        }

        const dim = root.VECTOR_DIMENSIONS;
        const data_ptr = @as([*]const f32, @ptrCast(@alignCast(block.ptr + @sizeOf(root.DeraineVector))));
        const copy_len = @min(out.len, dim);
        @memcpy(out[0..copy_len], data_ptr[0..copy_len]);
        return copy_len;
    }

    pub fn deleteVector(self: *Storage, index: u64) !void {
        self.lock.lock();
        defer self.lock.unlock();

        if (index >= self.header.vector_count) return StorageError.IndexOutOfBounds;

        const header_size = @sizeOf(root.DeraineHeader);
        const vector_size = self.header.vector_size;
        const offset = header_size + (index * vector_size);

        const block = self.memory[offset .. offset + vector_size];
        const meta = @as(*root.DeraineVector, @ptrCast(@alignCast(block.ptr)));

        meta.status = 0x01;
    }

    pub fn search(
        self: *Storage,
        query: []const f32,
        filter_mask: u64,
        k: u32,
        out_ids: [*]u64,
        out_distances: [*]f32,
        mode: root.SearchMode,
    ) !usize {
        if (mode == .Flat or self.index_header.max_level == -1) {
            return self.searchFlat(query, filter_mask, k, out_ids, out_distances);
        }
        return self.searchHNSW(query, filter_mask, k, out_ids, out_distances);
    }

    fn searchHNSW(
        self: *Storage,
        query: []const f32,
        filter_mask: u64,
        k: u32,
        out_ids: [*]u64,
        out_distances: [*]f32,
    ) !usize {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        var current_entry = self.index_header.entry_point_id;
        var l = self.index_header.max_level;
        while (l > 0) : (l -= 1) {
            current_entry = self.searchLayer(query, current_entry, l, 0);
        }

        // Use a real beam of candidates at layer 0 instead of a single
        // greedy-best node plus whatever happens to be in its direct
        // neighbor list - that's what let searches get stuck far from
        // the true nearest neighbors.
        const ef_search = @max(@as(usize, @intCast(k)), root.HNSW_EF_CONSTRUCTION);
        var results: [MAX_EF]Candidate = undefined;
        const found = self.searchLayerCandidates(query, current_entry, 0, ef_search, filter_mask, &results);

        const count = @min(@as(usize, @intCast(k)), found);
        for (0..count) |i| {
            out_ids[i] = results[i].id;
            out_distances[i] = results[i].dist;
        }

        return count;
    }

    fn getMetadataMask(self: *Storage, target_id: u64) u64 {
        const header_size = @sizeOf(root.DeraineHeader);
        const vector_size = self.header.vector_size;
        const offset = header_size + (target_id * vector_size);
        const block = self.memory[offset .. offset + vector_size];
        const meta = @as(*root.DeraineVector, @ptrCast(@alignCast(block.ptr)));
        return meta.metadata_mask;
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
        filter_mask: u64,
        k: u32,
        out_ids: [*]u64,
        out_distances: [*]f32,
    ) !usize {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        const header_size = @sizeOf(root.DeraineHeader);
        const vector_size = self.header.vector_size;
        const dim: usize = root.VECTOR_DIMENSIONS;

        var count: usize = 0;

        for (0..self.header.vector_count) |i| {
            const offset = header_size + (i * vector_size);
            const block = self.memory[offset .. offset + vector_size];
            const meta = @as(*root.DeraineVector, @ptrCast(@alignCast(block.ptr)));

            if (meta.status == 0x01) continue;

            if (filter_mask != 0 and (meta.metadata_mask & filter_mask) == 0) continue;

            const data_ptr = @as([*]const f32, @ptrCast(@alignCast(block.ptr + @sizeOf(root.DeraineVector))));
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
