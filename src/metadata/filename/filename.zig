/// naming convention:
/// <chapter title> | c<chapter number> | v<volume number>
pub const Metadata = struct {
    title: []const u8,
    volume: i64,
    chapter: i64,
};

pub fn parse(full_name: []const u8) !Metadata {
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

const std = @import("std");
