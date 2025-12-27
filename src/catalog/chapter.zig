id: i64,
/// naming convention:
/// <chapter title> | c<chapter number> | v<volume number>
name: []const u8,
volume: i64,
chapter: i64,
/// represents the latest read chapter
progress: i64,
total_pages: i64,

pub const Chapter = @This();

pub fn init(
    id: i64,
    volume: i64,
    chapter: i64,
    name: []u8,
    total_pages: i64,
) Chapter {
    return .{
        .id = id,
        .name = name,
        .chapter = chapter,
        .volume = volume,
        .progress = 0,
        .total_pages = total_pages,
    };
}

pub fn initFromDatabase(
    allocator: Allocator,
    database: Database,
    library_lookup_table: *std.AutoHashMap(i64, *Library),
    book_lookup_table: *std.AutoHashMap(i64, *Book),
) !void {

    // NOTE: deinit() is not called on the records here, despite allocations being made, as the ownership is passed on further down the code.
    const chapter_records = try GetAll.call(allocator, database);
    defer allocator.free(chapter_records);

    for (chapter_records) |record| {
        const target_book = book_lookup_table.get(record.book_id) orelse continue;
        const target_lib = library_lookup_table.get(record.library_id) orelse continue;

        const chapter = allocator.create(Chapter) catch @panic("OOM");

        chapter.* = .{
            .id = record.id,
            .name = record.title,
            .volume = record.volume,
            .chapter = record.chapter,
            .progress = record.progress,
            .total_pages = record.total_pages,
        };

        try target_book.chapters.put(record.title, chapter);

        try target_lib.hash_to_chapter.put(record.hash, .{
            .book = target_book,
            .chapter_name = record.title,
        });
    }
}

pub fn deinit(self: Chapter, allocator: Allocator) void {
    allocator.free(self.name);
}

pub const ParsedInfo = struct {
    title: []const u8,
    volume: i64,
    chapter: i64,
};

pub fn parseName(full_name: []const u8) !ParsedInfo {
    var it = std.mem.splitScalar(u8, full_name, '|');
    const title = std.mem.trim(u8, it.next() orelse return error.MissingTitle, " ");
    const volume = std.mem.trim(u8, it.next() orelse return error.MissingVolume, " ");
    const chapter = std.mem.trim(u8, it.next() orelse return error.MissingChapter, " ");

    return .{
        .title = title,
        .volume = try std.fmt.parseInt(i64, volume[1..], 10),
        .chapter = try std.fmt.parseInt(i64, chapter[1..], 10),
    };
}

/// get total amount of pages in a chapter for archive based formats
pub fn getPageAmount(file: *std.fs.File) !i64 {
    var buffer: [1024]u8 = undefined;

    var file_reader = file.reader(&buffer);
    var zip_iterator = try std.zip.Iterator.init(&file_reader);

    var name_buf: [1024]u8 = undefined;
    var page_amount: u32 = 0;

    while (try zip_iterator.next()) |entry| {
        try file.seekTo(entry.header_zip_offset + @sizeOf(std.zip.CentralDirectoryFileHeader));
        const filename = name_buf[0..entry.filename_len];
        _ = try file.read(filename);
        if (isImageFile(filename)) page_amount += 1;
    }
    return page_amount;
}

fn isImageFile(filename: []const u8) bool {
    // TODO: is this enough?
    const extensions = [_][]const u8{
        ".jpg",
        ".jpeg",
        ".png",
        ".webp",
    };
    for (extensions) |ext| {
        if (std.mem.endsWith(u8, filename, ext)) return true;
    }
    return false;
}

pub fn updateProgress(self: *Chapter, database: Database, chapter_number: i64) !void {
    try UpdateProgressDB.call(database, self.id, chapter_number);

    self.progress = chapter_number;
}

const UpdateProgressDB = @import("../database/chapter.zig").UpdateProgress;
const GetAll = @import("../database/chapter.zig").GetAll;
const Create = @import("../database/chapter.zig").Create;
const Database = @import("../database.zig");

const Library = @import("library.zig");
const Book = @import("book.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
