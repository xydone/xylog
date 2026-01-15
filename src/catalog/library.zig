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

const log = std.log.scoped(.library);

// name -> book
const BookMap = std.StringHashMap(*Book);

const Library = @This();

pub fn init(
    allocator: std.mem.Allocator,
    config: Config,
    dir: std.fs.Dir,
    name: []const u8,
    database: Database,
) !Library {
    const books = allocator.create(BookMap) catch @panic("OOM");
    books.* = BookMap.init(allocator);

    const hash_to_chapter = allocator.create(HashToChapterMap) catch @panic("OOM");
    hash_to_chapter.* = HashToChapterMap.init(allocator);

    const response = try Create.call(database, name);

    var library: Library = .{
        .id = response.library_id,
        .name = name,
        ._dir = dir,
        .books = books,
        .hash_to_chapter = hash_to_chapter,
    };

    try library.scan(allocator, config, database);

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
    self: *Library,
    allocator: Allocator,
    config: Config,
    database: Database,
) !void {
    var it = self._dir.iterate();

    while (try it.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                try self.addBook(
                    allocator,
                    config,
                    database,
                    entry.name,
                );
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
        allocator.free(entry.key_ptr.*);
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

/// Adds book that is inside the data directory to the library, without the need for a full rescan.
pub fn addBook(
    self: *Library,
    allocator: Allocator,
    config: Config,
    database: Database,
    book_folder_name: []const u8,
) !void {
    // guarantee that book name is unique in library
    if (self.books.contains(book_folder_name)) {
        return error.BookAlreadyExists;
    }

    // assume that the book already exists in the directory
    const book_dir = self._dir.openDir(book_folder_name, .{ .iterate = true }) catch |err| {
        log.err("addBook failed to open book_dir! {}", .{err});
        return error.BookNotFoundInDirectory;
    };

    const book = try Book.init(
        allocator,
        config,
        book_dir,
        book_folder_name,
        null, // TODO: use an actual author
        database,
        self.id,
        self.hash_to_chapter,
    );

    const duped_name = try allocator.dupe(u8, book_folder_name);

    try self.books.put(duped_name, book);
}

/// Copies or moves a book from a given directory to the data directory and adds it to the library.
pub fn importBook(
    self: *Library,
    allocator: Allocator,
    config: Config,
    database: Database,
    source_path: []const u8,
    book_folder_name: []const u8,
    operation_type: Config.Ingest.OperationType,
) !void {
    if (self.books.contains(book_folder_name)) return error.BookAlreadyExists;

    switch (operation_type) {
        .move => {
            std.fs.cwd().rename(source_path, book_folder_name) catch |err| {
                log.err("importBook: move failed! {}", .{err});
                return error.MoveFailed;
            };

            try self.addBook(allocator, config, database, book_folder_name);
        },
        .copy => {
            try self._dir.makeDir(book_folder_name);

            // cleanup if copy fails midway
            errdefer {
                log.warn("importBook: ran into error. Deleting tree...", .{});
                self._dir.deleteTree(book_folder_name) catch |err| {
                    log.warn("importBook: deleting the tree during cleanup failed! {}", .{err});
                };
            }

            var src_dir = std.fs.openDirAbsolute(source_path, .{ .iterate = true }) catch |err| {
                log.err("importBook: copy failed to open src_dir! {}", .{err});
                return error.CopyFailed;
            };
            defer src_dir.close();

            var dest_dir = self._dir.openDir(book_folder_name, .{}) catch |err| {
                log.err("importBook: copy failed to open dest_dir! {}", .{err});
                return error.CopyFailed;
            };

            defer dest_dir.close();
            copyDirRecursive(src_dir, dest_dir) catch |err| {
                log.err("importBook: copyDirRecursive failed! {}", .{err});
                return error.CopyFailed;
            };

            // INFO: the calls to addBook are identical across both operations, but are called separately.
            // This is done so we can cleanly leverage the errdefer for cleanup.
            try self.addBook(allocator, config, database, book_folder_name);
        },
    }

    log.debug("importBook: imported {s} from {s}", .{ book_folder_name, source_path });
}

fn copyDirRecursive(src_dir: std.fs.Dir, dest_dir: std.fs.Dir) !void {
    var it = src_dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .file => {
                try src_dir.copyFile(entry.name, dest_dir, entry.name, .{});
            },
            .directory => {
                try dest_dir.makeDir(entry.name);
                var sub_src = try src_dir.openDir(entry.name, .{ .iterate = true });
                defer sub_src.close();
                var sub_dest = try dest_dir.openDir(entry.name, .{});
                defer sub_dest.close();
                try copyDirRecursive(sub_src, sub_dest);
            },
            else => continue,
        }
    }
}

const hashFile = @import("../routes/kosync/util.zig").partialMd5;

const GetAll = @import("../database/library.zig").GetAll;
const Create = @import("../database/library.zig").Create;
const Database = @import("../database.zig");

const Book = @import("book.zig");
const Chapter = @import("chapter.zig");
const Config = @import("../config/config.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
