id: i64,
name: []const u8,
_dir: std.fs.Dir,
books: *BookMap,
// INFO: design decision explanation:
// for KOReader (possibly other applications too), we must maintain a hash of the file, which will be used to refer to it in the sync implementation.
// by storing a hash -> name hashmap inside, we opt into making two lookups per call than storing duplicated data for the same book
hash_to_chapter: *HashToChapterMap,
pub const HashToChapterMap = std.StringHashMap(struct {
    book: *Book,
    chapter_name: []const u8,
});

// name -> book
const BookMap = std.StringHashMap(*Book);

const Library = @This();

pub fn init(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    name: []const u8,
    database: Database,
) !Library {
    const books = allocator.create(BookMap) catch @panic("OOM");
    books.* = BookMap.init(allocator);

    const hash_to_chapter = allocator.create(HashToChapterMap) catch @panic("OOM");
    hash_to_chapter.* = HashToChapterMap.init(allocator);

    const response = try Create.call(database, name);

    const library: Library = .{
        .id = response.library_id,
        .name = name,
        ._dir = dir,
        .books = books,
        .hash_to_chapter = hash_to_chapter,
    };

    try library.scan(allocator, database, response.library_id);

    return library;
}

pub fn initFromDatabase(allocator: Allocator, catalog_dir: *std.fs.Dir, database: Database) ![]Library {
    const library_responses = try GetAll.call(allocator, database);
    defer {
        for (library_responses) |r| r.deinit(allocator);
        allocator.free(library_responses);
    }

    var library_lookup_table = std.AutoHashMap(i64, *Library).init(allocator);
    defer library_lookup_table.deinit();

    const libraries = try allocator.alloc(Library, library_responses.len);
    errdefer allocator.free(libraries);

    for (library_responses, 0..) |res, i| {
        const books = allocator.create(BookMap) catch @panic("OOM");
        books.* = BookMap.init(allocator);

        const hash_to_chapter = allocator.create(HashToChapterMap) catch @panic("OOM");
        hash_to_chapter.* = HashToChapterMap.init(allocator);

        libraries[i] = .{
            .id = res.id,
            .name = try allocator.dupe(u8, res.name),
            ._dir = try catalog_dir.openDir(res.name, .{ .iterate = true }),
            .books = books,
            .hash_to_chapter = hash_to_chapter,
        };
        try library_lookup_table.put(res.id, &libraries[i]);
    }

    const book_lookup_table = try Book.initManyFromDatabase(allocator, database, library_lookup_table);

    try Chapter.initFromDatabase(
        allocator,
        database,
        &library_lookup_table,
        book_lookup_table,
    );

    return libraries;
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
                    // TODO: actual author name
                    "Unknown Author",
                    database,
                    library_id,
                    self.hash_to_chapter,
                );
                const duped_name = allocator.dupe(u8, entry.name) catch @panic("OOM");
                self.books.put(duped_name, book) catch @panic("OOM");
            },
            else => {},
        }
    }
}

pub fn deinit(self: Library, allocator: std.mem.Allocator) void {
    defer {
        self.books.deinit();
        allocator.destroy(self.books);
        self.hash_to_chapter.deinit();
        allocator.destroy(self.hash_to_chapter);
    }

    var book_it = self.books.iterator();
    while (book_it.next()) |entry| {
        defer allocator.destroy(entry.value_ptr.*);
        entry.value_ptr.*.deinit(allocator);
    }
    var hash_to_chapter_it = self.hash_to_chapter.keyIterator();
    while (hash_to_chapter_it.next()) |hash| {
        // free the hash
        allocator.free(hash.*);
    }
}

pub fn getChapterByHash(self: Library, hash: []const u8) !*Chapter {
    const result = self.hash_to_chapter.get(hash) orelse return error.HashToChapterFailed;
    return result.book.chapters.get(result.chapter_name) orelse return error.ChapterNotFound;
}

const hashFile = @import("../sync/koreader/util.zig").partialMd5;

const GetAll = @import("../database/library.zig").GetAll;
const Create = @import("../database/library.zig").Create;
const Database = @import("../database.zig");

const Book = @import("book.zig");
const Chapter = @import("chapter.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
