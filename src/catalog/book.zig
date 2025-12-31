id: i64,
_dir: std.fs.Dir,
author: ?[]const u8,
name: []const u8,
chapters: *ChapterMap,

// name -> chapter
const ChapterMap = std.StringHashMap(*Chapter);

pub const Book = @This();

const log = std.log.scoped(.book);

pub fn init(
    allocator: Allocator,
    dir: std.fs.Dir,
    name: []const u8,
    author: ?[]const u8,
    database: Database,
    library_id: i64,
    hash_to_chapter_map: *Library.HashToChapterMap,
) !*Book {
    const chapters = allocator.create(ChapterMap) catch @panic("OOM");
    chapters.* = ChapterMap.init(allocator);

    const duped_name = allocator.dupe(u8, name) catch @panic("OOM");
    const author_slice = if (author) |slice| allocator.dupe(u8, slice) catch @panic("OOM") else null;
    const response = try Create.call(
        database,
        duped_name,
        author_slice,
        library_id,
    );

    // we need to be the ones allocating the book during the initialization process as we need to put a stable pointer in the map
    const book = allocator.create(Book) catch @panic("OOM");

    book.* = .{
        .id = response.book_id,
        .chapters = chapters,
        ._dir = dir,
        .name = duped_name,
        .author = author_slice,
    };

    try book.scan(
        allocator,
        database,
        hash_to_chapter_map,
    );

    return book;
}

pub fn initManyFromDatabase(
    allocator: Allocator,
    database: Database,
    library_lookup_table: std.AutoHashMap(i64, *Library),
) !*std.AutoHashMap(i64, *Book) {

    // NOTE: deinit() is not called on the records here, despite allocations being made, as the ownership is passed on further down the code.
    const book_records = try GetAll.call(allocator, database);
    defer allocator.free(book_records);

    const book_lookup_table = try allocator.create(std.AutoHashMap(i64, *Book));
    book_lookup_table.* = std.AutoHashMap(i64, *Book).init(allocator);

    for (book_records) |record| {
        const chapters = allocator.create(ChapterMap) catch @panic("OOM");
        chapters.* = ChapterMap.init(allocator);
        const book = allocator.create(Book) catch @panic("OOM");
        const library = library_lookup_table.get(record.library_id) orelse continue;

        const dir = try library._dir.openDir(record.title, .{ .iterate = true });

        book.* = .{
            .id = record.id,
            .chapters = chapters,
            ._dir = dir,
            .name = record.title,
            .author = record.author,
        };

        try library.books.put(record.title, book);
        try book_lookup_table.put(record.id, book);
    }

    return book_lookup_table;
}

pub fn scan(
    self: *Book,
    allocator: Allocator,
    database: Database,
    hash_to_chapter_map: *Library.HashToChapterMap,
) !void {
    var it = self._dir.iterate();

    var db_entries = std.ArrayList(CreateMany.Entry).empty;
    defer db_entries.deinit(allocator);

    var filenames = std.ArrayList([]u8).empty;
    defer filenames.deinit(allocator);

    while (try it.next()) |entry| {
        if (entry.kind == .file) {
            const duped_name = try allocator.dupe(u8, entry.name);
            const info = try Chapter.parseName(duped_name);

            var file = try self._dir.openFile(duped_name, .{ .mode = .read_only });
            defer file.close();

            const digest = try hashFile(file);
            const hash = std.fmt.allocPrint(allocator, "{x}", .{digest}) catch @panic("OOM");

            const absolute_path = try self._dir.realpathAlloc(allocator, duped_name);
            defer allocator.free(absolute_path);

            const path_c = try allocator.dupeZ(u8, absolute_path);
            defer allocator.free(path_c);

            try db_entries.append(allocator, .{
                .file_name = duped_name,
                .hash = hash,
                .volume = info.volume,
                .chapter = info.chapter,
                .total_pages = try Chapter.getPageAmount(path_c),
            });

            try filenames.append(allocator, duped_name);

            try hash_to_chapter_map.put(
                hash,
                .{
                    .book = self,
                    .chapter_name = duped_name,
                },
            );
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

    for (db_entries.items, responses, filenames.items) |entry, response, filename| {
        const chapter = allocator.create(Chapter) catch @panic("OOM");

        const comic_info = blk: {
            const absolute_path = try self._dir.realpathAlloc(allocator, filename);
            defer allocator.free(absolute_path);

            const path_c = try allocator.dupeZ(u8, absolute_path);
            defer allocator.free(path_c);
            break :blk try Chapter.getComicInfo(allocator, path_c);
        };
        defer comic_info.deinit(allocator);

        self.author = switch (comic_info.comic_info) {
            .@"1_0" => |ci| ci.Writer,
            .@"2_0" => |ci| ci.Writer,
        };

        chapter.* = Chapter.init(
            response.chapter_id,
            entry.volume,
            entry.chapter,
            filename,
            entry.total_pages,
        );

        const existing_chapter = try self.chapters.fetchPut(filename, chapter);
        // if this is a rescan of the same chapter, deinitialize memory
        if (existing_chapter != null) {
            allocator.destroy(existing_chapter.?.value);
            allocator.free(existing_chapter.?.key);
        }
    }
}

pub fn deinit(self: Book, allocator: Allocator) void {
    allocator.free(self.name);
    if (self.author) |author| allocator.free(author);
    {
        var it = self.chapters.valueIterator();
        while (it.next()) |chapter| {
            defer allocator.destroy(chapter.*);
            chapter.*.deinit(allocator);
        }
        self.chapters.deinit();
        allocator.destroy(self.chapters);
    }
}

const hashFile = @import("../routes/kosync/util.zig").partialMd5;

const ComicInfo = @import("../metadata/comicinfo/comicinfo.zig");
const Chapter = @import("chapter.zig");
const Library = @import("library.zig");

const CreateMany = @import("../database/chapter.zig").CreateMany;
const GetAll = @import("../database/book.zig").GetAll;
const Create = @import("../database/book.zig").Create;
const Database = @import("../database.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
