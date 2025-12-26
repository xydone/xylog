/// naming convention:
/// <chapter title> | c<chapter number> | v<volume number>
name: []const u8,
volume: i64,
chapter: i64,
is_read: bool,

pub const Chapter = @This();

pub fn init(
    volume: i64,
    chapter: i64,
    name: []u8,
) Chapter {
    return .{
        .name = name,
        .chapter = chapter,
        .volume = volume,
        .is_read = false,
    };
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
        // Also check uppercase for older archives
        if (std.mem.endsWith(u8, filename, ".JPG") or std.mem.endsWith(u8, filename, ".PNG")) return true;
    }
    return false;
}

const Create = @import("../database/chapter.zig").Create;
const Database = @import("../database.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
