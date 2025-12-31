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
pub fn getPageAmount(path: [:0]const u8) !u32 {
    var err: c_int = 0;
    const archive = zip.zip_open(path.ptr, zip.ZIP_RDONLY, &err);
    if (archive == null) return error.ZipOpenFailed;
    defer _ = zip.zip_close(archive);

    const num_entries = zip.zip_get_num_entries(archive, 0);
    var count: u32 = 0;

    var i: i64 = 0;
    while (i < num_entries) : (i += 1) {
        const name_ptr = zip.zip_get_name(archive, @intCast(i), 0);
        if (name_ptr == null) continue;

        if (isImageFile(std.mem.span(name_ptr))) {
            count += 1;
        }
    }
    return count;
}

/// Caller owns memory
pub fn getComicInfo(allocator: std.mem.Allocator, path: [:0]const u8) !ComicInfo {
    var err: c_int = 0;
    const archive = zip.zip_open(path.ptr, zip.ZIP_RDONLY, &err);
    if (archive == null) return error.ZipOpenFailed;
    defer _ = zip.zip_close(archive);

    var version: ?ComicInfo.Version = null;

    const index = blk: {
        const targets = [_]struct { name: [:0]const u8, ver: ComicInfo.Version }{
            .{ .name = "ComicInfo.xml", .ver = .@"1_0" },
            .{ .name = "ComicInfo2.xml", .ver = .@"2_0" },
        };
        for (targets) |target| {
            const i = zip.zip_name_locate(archive, target.name, 0);
            if (i >= 0) {
                version = target.ver;
                break :blk i;
            }
        }
        // if we are here, no version was found
        // what we return does not matter as long as we verify that the version variable is null
        break :blk 0;
    };

    if (version == null) return error.NotFound;

    var stat: zip.zip_stat_t = undefined;
    _ = zip.zip_stat_init(&stat);
    if (zip.zip_stat_index(archive, @intCast(index), 0, &stat) != 0) {
        return error.ZipStatFailed;
    }

    const buffer = try allocator.alloc(u8, @intCast(stat.size));
    errdefer allocator.free(buffer);

    const file = zip.zip_fopen_index(archive, @intCast(index), 0);
    if (file == null) return error.FileOpenFailed;
    defer _ = zip.zip_fclose(file);

    const read_bytes = zip.zip_fread(file, buffer.ptr, @intCast(stat.size));
    if (read_bytes < 0 or read_bytes != stat.size) {
        return error.ReadFailed;
    }

    return ComicInfo.getComicInfo(allocator, version.?, buffer);
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

const ComicInfo = @import("../metadata/comicinfo/comicinfo.zig");
const Library = @import("library.zig");
const Book = @import("book.zig");

const zip = @cImport({
    @cInclude("zip.h");
});

const Allocator = std.mem.Allocator;
const std = @import("std");
