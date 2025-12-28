/// Absolute path
catalog_dir: []const u8,
/// Absolute path
state_dir: []const u8,
port: u16,
address: []const u8,
/// automatic library scanning on server start
scan_on_start: bool = true,

const path = "config/config.zon";
const log = std.log.scoped(.config);

const ConfigFile = @This();

pub const InitErrors = error{
    CouldntReadFile,
    CouldntInitDataDirectory,
    CouldntInitStateDirectory,
};

pub fn init(allocator: Allocator) InitErrors!ConfigFile {
    // WARNING: the config file is freed at the end of the scope.
    // You must guarantee that the values that leave the scope do not depend on values that will be freed.
    return readFileZon(ConfigFile, allocator, path, 1024 * 5) catch |err| {
        log.err("readFileZon failed with {}", .{err});
        return error.CouldntReadFile;
    };
}

pub fn deinit(self: ConfigFile, allocator: Allocator) void {
    zon.parse.free(allocator, self);
}
const readFileZon = @import("common.zig").readFileZon;
const Catalog = @import("../catalog.zig");

const zon = std.zon;
const Allocator = std.mem.Allocator;
const std = @import("std");
