/// Absolute path
catalog_dir: []u8,
/// Absolute path
state_dir: []u8,
port: u16,
address: []u8,
/// automatic library scanning on server start
scan_on_start: bool = true,
encryption_secret: [32]u8,
ingest: Ingest,

pub const Ingest = struct {
    /// the name of the library that will be inserted into when ingesting
    default_library_to_use: []u8,
    operation_type: OperationType,

    pub const OperationType = enum { copy, move };
};

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
    encryption_secret: ?[]const u8,
    ingest: struct {
        default_library_to_use: ?[]const u8,
        operation_type: Ingest.OperationType,
    },
};

pub const InitErrors = error{
    CouldntReadFile,
    CouldntInitDataDirectory,
    CouldntInitStateDirectory,
    RequiredNullableFieldMissing,
    EncryptionSecretNotCorrectLength,
    CouldntGenerateSecret,
};

pub fn init(allocator: Allocator) InitErrors!Config {
    // WARNING: the config file is freed at the end of the scope.
    // You must guarantee that the values that leave the scope do not depend on values that will be freed.
    const config_file = readFileZon(ConfigFile, allocator, path, 1024 * 5) catch |err| {
        log.err("readFileZon failed with {}", .{err});
        return error.CouldntReadFile;
    };
    defer zon.parse.free(allocator, config_file);

    return .{
        .catalog_dir = if (config_file.catalog_dir) |dir| allocator.dupe(u8, dir) catch @panic("OOM") else {
            log.err("catalog_dir is null. Change the default configuration.", .{});
            return error.RequiredNullableFieldMissing;
        },
        .state_dir = if (config_file.state_dir) |dir| allocator.dupe(u8, dir) catch @panic("OOM") else {
            log.err("state_dir is null. Change the default configuration.", .{});
            return error.RequiredNullableFieldMissing;
        },
        .port = config_file.port,
        .address = allocator.dupe(u8, config_file.address) catch @panic("OOM"),
        .scan_on_start = config_file.scan_on_start,
        .encryption_secret = blk: {
            if (config_file.encryption_secret) |secret| {
                if (secret.len != 64) return error.EncryptionSecretNotCorrectLength;
                var encryption_secret: [32]u8 = undefined;
                _ = std.fmt.hexToBytes(&encryption_secret, secret) catch return error.CouldntGenerateSecret;
                break :blk encryption_secret;
            } else {
                log.err("encryption_secret is null. Change the default configuration.", .{});
                return error.RequiredNullableFieldMissing;
            }
        },
        .ingest = .{
            .default_library_to_use = blk: {
                if (config_file.ingest.default_library_to_use) |library| {
                    break :blk allocator.dupe(u8, library) catch @panic("OOM");
                } else {
                    log.err("Ingest's default_library_to_use is null. Change the default configuration.", .{});
                    return error.RequiredNullableFieldMissing;
                }
            },
            .operation_type = config_file.ingest.operation_type,
        },
    };
}

pub fn deinit(self: *Config, allocator: Allocator) void {
    @memset(&self.encryption_secret, 0);
    allocator.free(self.address);
    allocator.free(self.catalog_dir);
    allocator.free(self.state_dir);

    allocator.free(self.ingest.default_library_to_use);
}
const readFileZon = @import("common.zig").readFileZon;
const Catalog = @import("../catalog.zig");

const zon = std.zon;
const Allocator = std.mem.Allocator;
const std = @import("std");
