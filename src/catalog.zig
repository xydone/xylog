_dir: *std.fs.Dir,
libraries: *LibraryMap,
// RESEARCH: some applications just use per call timestamps?
update_time: Datetime,

// library name -> library
const LibraryMap = std.StringHashMap(Library);

pub const Catalog = @This();

pub fn init(
    absolute_path: []const u8,
    allocator: Allocator,
    database: Database,
) !Catalog {
    const dir = allocator.create(std.fs.Dir) catch @panic("OOM");
    dir.* = try std.fs.openDirAbsolute(absolute_path, .{ .iterate = true });
    const libraries = allocator.create(LibraryMap) catch @panic("OOM");
    libraries.* = LibraryMap.init(allocator);

    const now = try zdt.Datetime.now(null);

    const catalog: Catalog = .{
        ._dir = dir,
        .libraries = libraries,
        .update_time = now,
    };

    // always scan on initialization
    try catalog.scan(
        allocator,
        database,
    );
    return catalog;
}

pub fn scan(
    catalog: Catalog,
    allocator: Allocator,
    database: Database,
) !void {
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
const Database = @import("database.zig");

const Datetime = @import("zdt").Datetime;
const zdt = @import("zdt");

const Allocator = std.mem.Allocator;
const std = @import("std");
