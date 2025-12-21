var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };

    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var config = try Config.init(allocator);
    defer config.deinit(allocator);

    var database = try Database.init(allocator, config.state_dir);
    defer database.deinit();

    var catalog = try Catalog.init(config.catalog_dir, allocator, database);
    defer catalog.deinit(allocator);
}

const Catalog = @import("catalog.zig");
const Database = @import("database.zig");
const Config = @import("config/config.zig");
const builtin = @import("builtin");
const std = @import("std");
