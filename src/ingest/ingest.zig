const log = std.log.scoped(.ingest);

pub fn scan(
    allocator: Allocator,
    database: Database,
    config: Config,
    catalog: *Catalog,
) void {
    const interval = config.ingest.interval * 60 * std.time.ns_per_s;
    const ingest_dir = std.fmt.allocPrint(allocator, "{s}/ingest/", .{config.state_dir}) catch @panic("OOM");
    defer allocator.free(ingest_dir);

    while (true) {
        log.debug("Starting scan...", .{});
        scanIngest(
            allocator,
            database,
            config,
            ingest_dir,
            catalog,
        ) catch |err| {
            log.err("Background scan error: {}", .{err});
        };
        log.debug("Finished scan!", .{});
        std.Thread.sleep(interval);
    }
}

fn scanIngest(
    allocator: Allocator,
    database: Database,
    config: Config,
    path: []const u8,
    catalog: *Catalog,
) !void {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
    defer dir.close();

    // TODO: replace with SelectiveWalker when 0.16 hits
    var it = dir.iterate();

    // step through the ingest folder, looking for folder name matches, which correspond to a different ingest service
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        const handler = if (std.mem.eql(u8, entry.name, "suwayomi"))
            Suwayomi.scan
        else
            continue;

        const directory_name = entry.name;
        const directory = dir.openDir(directory_name, .{ .iterate = true }) catch {
            continue;
        };

        // determine what library will be used to insert this book into
        // TODO: allow for customization and not just whatever the first library is.
        const library = catalog.libraries.getPtr(config.ingest.default_library_to_use) orelse {
            log.warn("Ingest did not find library {s} that is supposed to be used as default!", .{config.ingest.default_library_to_use});
            return error.LibraryNotFound;
        };

        handler(
            allocator,
            database,
            config,
            directory,
            library,
        ) catch |err| {
            log.err("{s} ingest scan failed! {}", .{ directory_name, err });
            return error.IngestFailed;
        };
    }
}

const Suwayomi = @import("suwayomi.zig");

const Config = @import("../config/config.zig");
const Catalog = @import("../catalog.zig");
const Database = @import("../database.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
