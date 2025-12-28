_dir: *std.fs.Dir,
libraries: *LibraryMap,
// RESEARCH: some applications just use per call timestamps?
update_time: Datetime,

// library name -> library
const LibraryMap = std.StringHashMap(Library);

pub const Catalog = @This();
const log = std.log.scoped(.catalog);

pub fn init(
    config: Config,
    allocator: Allocator,
    database: Database,
) !Catalog {
    const dir = allocator.create(std.fs.Dir) catch @panic("OOM");
    dir.* = try std.fs.openDirAbsolute(config.catalog_dir, .{ .iterate = true });
    const libraries = allocator.create(LibraryMap) catch @panic("OOM");
    libraries.* = LibraryMap.init(allocator);

    const now = try zdt.Datetime.now(null);

    const catalog: Catalog = .{
        ._dir = dir,
        .libraries = libraries,
        .update_time = now,
    };

    // always scan if the database was previously uninitialized
    // and if the user has configured it that way
    if (config.scan_on_start or database.is_first_time_initializing == true) {
        try catalog.scan(
            allocator,
            database,
        );
    } else {
        try catalog.initFromDatabase(allocator, database);
    }
    return catalog;
}

pub fn scan(
    catalog: Catalog,
    allocator: Allocator,
    database: Database,
) !void {
    log.debug("Scanning catalog from disk...", .{});
    var it = catalog._dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                const library_dir = try catalog._dir.openDir(entry.name, .{ .iterate = true });
                const library = try Library.init(
                    allocator,
                    library_dir,
                    entry.name,
                    database,
                );
                const duped_name = allocator.dupe(u8, entry.name) catch @panic("OOM");
                catalog.libraries.put(duped_name, library) catch @panic("OOM");
            },
            else => {},
        }
    }
    log.debug("Catalog disk scan complete!", .{});
}

pub fn initFromDatabase(catalog: Catalog, allocator: Allocator, database: Database) !void {
    log.debug("Scanning catalog from database...", .{});
    const libraries = try Library.initFromDatabase(allocator, catalog._dir, database);
    for (libraries) |library| {
        try catalog.libraries.put(library.name, library);
    }
    log.debug("Catalog database scan complete!", .{});
}

pub fn deinit(self: *Catalog, allocator: Allocator) void {
    var library_it = self.libraries.iterator();
    {
        self._dir.close();
        allocator.destroy(self._dir);
    }
    {
        while (library_it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
            allocator.free(entry.key_ptr.*);
        }
        self.libraries.deinit();
        allocator.destroy(self.libraries);
    }
}

const Library = @import("catalog/library.zig");
const Config = @import("config/config.zig");
const Database = @import("database.zig");

const Datetime = @import("zdt").Datetime;
const zdt = @import("zdt");

const Allocator = std.mem.Allocator;
const std = @import("std");
