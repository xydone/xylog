/// naming convention:
/// <title> <c + <chapter> | v + <volume>
name: []const u8,
number: i64,
is_read: bool,

pub const Chapter = @This();

pub fn init(allocator: Allocator, database: Database, book_id: i64, name: []const u8) !Chapter {
    const duped_name = allocator.dupe(u8, name) catch @panic("OOM");

    const parsed_info = parseName(duped_name);

    const response = try Create.call(
        database,
        book_id,
        duped_name,
        parsed_info.kind,
        0,
    );

    return .{
        .name = duped_name,
        .number = response.number,
        .is_read = false,
    };
}

pub fn deinit(self: Chapter, allocator: Allocator) void {
    allocator.free(self.name);
}

pub const ParsedInfo = struct {
    title: []const u8,
    kind: ChapterType,
    number: i64,
    excess: []const u8,
};

pub fn parseName(full_name: []const u8) ParsedInfo {
    const markers = [_]struct {
        s: []const u8,
        king: ChapterType,
    }{
        .{ .s = " c", .king = .chapter },
        .{ .s = " v", .king = .volume },
    };

    var best_marker_idx: ?usize = null;
    var kind: ?ChapterType = null;
    var marker_len: usize = 0;

    // searches for last occurance for "c" or "v"
    for (markers) |m| {
        if (std.mem.lastIndexOf(u8, full_name, m.s)) |idx| {
            if (best_marker_idx == null or idx > best_marker_idx.?) {
                best_marker_idx = idx;
                kind = m.king;
                marker_len = m.s.len;
            }
        }
    }

    const idx = best_marker_idx orelse {
        return .{
            .title = full_name,
            .kind = .chapter,
            .number = 0,
            .excess = "",
        };
    };

    const title = full_name[0..idx];
    const after_marker = full_name[idx + marker_len ..];

    var num_end: usize = 0;
    while (num_end < after_marker.len and std.ascii.isDigit(after_marker[num_end])) : (num_end += 1) {}

    const number_str = after_marker[0..num_end];
    const excess = std.mem.trim(u8, after_marker[num_end..], " ");

    const number = std.fmt.parseInt(i64, number_str, 10) catch 0;

    return .{
        .title = title,
        .kind = kind orelse .chapter,
        .number = number,
        .excess = excess,
    };
}

const ChapterType = @import("../types.zig").ChapterType;

const Create = @import("../database/chapter.zig").Create;
const Database = @import("../database.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
