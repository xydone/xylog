id: i64,
_dir: std.fs.Dir,
name: []const u8,
chapters: *ChapterMap,

// name -> chapter
const ChapterMap = std.StringHashMap(Chapter);

pub const Book = @This();

pub fn init(
    allocator: Allocator,
    dir: std.fs.Dir,
    name: []const u8,
    database: Database,
    library_id: i64,
) !Book {
    const chapters = allocator.create(ChapterMap) catch @panic("OOM");
    chapters.* = ChapterMap.init(allocator);

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

    var db_entries = std.ArrayList(CreateMany.Entry).empty;
    defer db_entries.deinit(allocator);

    var filenames = std.ArrayList([]u8).empty;
    defer filenames.deinit(allocator);

    while (try it.next()) |entry| {
        if (entry.kind == .file) {
            const duped_name = try allocator.dupe(u8, entry.name);
            const info = Chapter.parseName(duped_name);

            try db_entries.append(allocator, .{
                .file_name = duped_name,
                .kind = info.kind,
                .number = @intCast(info.number),
            });

            try filenames.append(allocator, duped_name);
        }
    }

    if (db_entries.items.len == 0) return;

    const responses = try CreateMany.call(
        allocator,
        database,
        self.id,
        db_entries.items,
    );
    defer allocator.free(responses);

    for (responses, filenames.items) |res, filename| {
        const chapter = Chapter.init(res.number, filename);
        try self.chapters.put(filename, chapter);
    }
}

pub fn deinit(self: Book, allocator: Allocator) void {
    allocator.free(self.name);
    {
        var it = self.chapters.valueIterator();
        while (it.next()) |chapter| {
            chapter.deinit(allocator);
        }
        self.chapters.deinit();
        allocator.destroy(self.chapters);
    }
}

const Chapter = @import("chapter.zig");

const CreateMany = @import("../database/chapter.zig").CreateMany;
const Create = @import("../database/book.zig").Create;
const Database = @import("../database.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
