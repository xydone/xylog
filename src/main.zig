var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

const log = std.log.scoped(.main);
pub fn main() !void {
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };

    defer if (is_debug) {
        // _ = debug_allocator.deinit();
    };

    var config = try Config.init(allocator);
    defer config.deinit(allocator);

    var database = try Database.init(allocator, config.state_dir);
    defer database.deinit();

    var catalog = try Catalog.init(config, allocator, database);
    defer catalog.deinit(allocator);

    var handler: Handler = .{
        .catalog = &catalog,
        .config = &config,
        .database = &database,
    };
    var server = try httpz.Server(*Handler).init(allocator, .{
        .port = config.port,
        .address = config.address,
    }, &handler);
    defer {
        server.deinit();
        server.stop();
    }

    const router = try server.router(.{});

    OPDS.init(router);
    KOSync.init(router);

    log.info("Listening on http://{s}:{d}/", .{ config.address, config.port });
    try server.listen();
}

const OPDS = @import("routes/opds/routes.zig");
const KOSync = @import("routes/kosync/routes.zig");

const Catalog = @import("catalog.zig");
const Database = @import("database.zig");
const Config = @import("config/config.zig");

const Handler = @import("handler.zig");

const httpz = @import("httpz");

const builtin = @import("builtin");
const std = @import("std");
