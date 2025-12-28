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

const Config = @This();

// this is the contract the config file must fulfill.
// it is different from the root level struct as it allows us to enforce better safety against misconfigurations.
const ConfigFile = struct {
    /// will be null if the user did not change it from the default file
    catalog_dir: ?[]const u8,
    /// will be null if the user did not change it from the default file
    state_dir: ?[]const u8,
    port: u16,
    address: []const u8,
    scan_on_start: bool = true,
};

pub const InitErrors = error{
    CouldntReadFile,
    CouldntInitDataDirectory,
    CouldntInitStateDirectory,
    CatalogDirMissing,
    StateDirMissing,
};

pub fn init(allocator: Allocator) InitErrors!Config {
    // WARNING: the config file is freed at the end of the scope.
    // You must guarantee that the values that leave the scope do not depend on values that will be freed.
    const config_file = readFileZon(ConfigFile, allocator, path, 1024 * 5) catch |err| {
        log.err("readFileZon failed with {}", .{err});
        return error.CouldntReadFile;
    };

    return .{
        .catalog_dir = if (config_file.catalog_dir) |dir| dir else {
            log.err("catalog_dir is null. Change the default configuration.", .{});
            return error.CatalogDirMissing;
        },
        .state_dir = if (config_file.state_dir) |dir| dir else {
            log.err("state_dir is null. Change the default configuration.", .{});
            return error.CatalogDirMissing;
        },
        .port = config_file.port,
        .address = config_file.address,
        .scan_on_start = config_file.scan_on_start,
    };
}

pub fn deinit(self: Config, allocator: Allocator) void {
    zon.parse.free(allocator, self);
}
const readFileZon = @import("common.zig").readFileZon;
const Catalog = @import("../catalog.zig");

const zon = std.zon;
const Allocator = std.mem.Allocator;
const std = @import("std");
