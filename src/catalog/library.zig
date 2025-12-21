_dir: std.fs.Dir,
name: []const u8,
books: *std.ArrayList(Book),

const Library = @This();

pub fn init(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    name: []const u8,
    database: Database,
) !Library {
    const books = allocator.create(std.ArrayList(Book)) catch @panic("OOM");
    books.* = std.ArrayList(Book).empty;

    const duped_name = allocator.dupe(u8, name) catch @panic("OOM");

    const response = try Create.call(database, duped_name);

    const library: Library = .{
        .name = duped_name,
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
                self.books.append(allocator, book) catch @panic("OOM");
            },
            else => {},
        }
    }
}

pub fn deinit(self: Library, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    for (self.books.items) |*book| {
        book.deinit(allocator);
    }
    self.books.deinit(allocator);
    allocator.destroy(self.books);
}

const Create = @import("../database/library.zig").Create;
const Database = @import("../database.zig");

const Book = @import("book.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
