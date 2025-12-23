_dir: std.fs.Dir,
books: *BookMap,

// name -> book
const BookMap = std.StringHashMap(Book);

const Library = @This();

pub fn init(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    name: []const u8,
    database: Database,
) !Library {
    const books = allocator.create(BookMap) catch @panic("OOM");
    books.* = BookMap.init(allocator);

    const response = try Create.call(database, name);

    const library: Library = .{
        ._dir = dir,
        .books = books,
    };

    try library.scan(allocator, database, response.library_id);

    return library;
}

pub fn scan(
    self: Library,
    allocator: Allocator,
    database: Database,
    library_id: i64,
) !void {
    var it = self._dir.iterate();

    while (try it.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                const book_dir = try self._dir.openDir(entry.name, .{ .iterate = true });
                const book = try Book.init(
                    allocator,
                    book_dir,
                    entry.name,
                    database,
                    library_id,
                );
                const duped_name = allocator.dupe(u8, entry.name) catch @panic("OOM");
                self.books.put(duped_name, book) catch @panic("OOM");
            },
            else => {},
        }
    }
}

pub fn deinit(self: Library, allocator: std.mem.Allocator) void {
    var book_it = self.books.iterator();
    while (book_it.next()) |entry| {
        entry.value_ptr.deinit(allocator);
        allocator.free(entry.key_ptr.*);
    }
    self.books.deinit();
    allocator.destroy(self.books);
}

const Create = @import("../database/library.zig").Create;
const Database = @import("../database.zig");

const Book = @import("book.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
