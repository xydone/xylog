_dir: *std.fs.Dir,
libraries: *std.ArrayList(Library),
// RESEARCH: some applications just use per call timestamps?
update_time: Datetime,

pub const Catalog = @This();

pub fn init(
    absolute_path: []const u8,
    allocator: Allocator,
    database: Database,
) !Catalog {
    const dir = allocator.create(std.fs.Dir) catch @panic("OOM");
    dir.* = try std.fs.openDirAbsolute(absolute_path, .{ .iterate = true });
    const libraries = allocator.create(std.ArrayList(Library)) catch @panic("OOM");
    libraries.* = std.ArrayList(Library).empty;

    const locale = try zdt.Timezone.tzLocal(allocator);
    const now = try zdt.Datetime.now(.{ .tz = &locale });

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
                catalog.libraries.append(allocator, library) catch @panic("OOM");
            },
            else => {},
        }
    }
}

pub fn deinit(self: *Catalog, allocator: Allocator) void {
    {
        self._dir.close();
        allocator.destroy(self._dir);
    }
    {
        for (self.libraries.items) |*library| {
            library.deinit(allocator);
        }
        self.libraries.deinit(allocator);
        allocator.destroy(self.libraries);
    }
}

const Library = @import("catalog/library.zig");
const Database = @import("database.zig");

const Datetime = @import("zdt").Datetime;
const zdt = @import("zdt");

const Allocator = std.mem.Allocator;
const std = @import("std");
