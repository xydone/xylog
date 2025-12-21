id: i64,
_dir: std.fs.Dir,
name: []const u8,
chapters: *std.ArrayList(Chapter),

pub const Book = @This();

pub fn init(
    allocator: Allocator,
    dir: std.fs.Dir,
    name: []const u8,
    database: Database,
    library_id: i64,
) !Book {
    const chapters = allocator.create(std.ArrayList(Chapter)) catch @panic("OOM");
    chapters.* = std.ArrayList(Chapter).empty;

    const duped_name = allocator.dupe(u8, name) catch @panic("OOM");

    const response = try Create.call(
        database,
        duped_name,
        library_id,
    );

    const book: Book = .{
        .id = response.book_id,
        .chapters = chapters,
        ._dir = dir,
        .name = duped_name,
    };

    try book.scan(
        allocator,
        database,
    );

    return book;
}

pub fn scan(self: Book, allocator: Allocator, database: Database) !void {
    var it = self._dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .file => {
                const chapter = try Chapter.init(allocator, database, self.id, entry.name);
                self.chapters.append(allocator, chapter) catch @panic("OOM");
            },
            else => {},
        }
    }
}

pub fn deinit(self: Book, allocator: Allocator) void {
    allocator.free(self.name);
    {
        for (self.chapters.items) |*chapter| {
            chapter.deinit(allocator);
        }
        self.chapters.deinit(allocator);
        allocator.destroy(self.chapters);
    }
}

const Chapter = @import("chapter.zig");

const Create = @import("../database/book.zig").Create;
const Database = @import("../database.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
