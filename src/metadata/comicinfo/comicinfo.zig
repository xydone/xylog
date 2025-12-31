version: Version,
slice: []const u8,
comic_info: ComicInfoData,

const ComicInfo = @This();

pub fn deinit(self: ComicInfo, allocator: Allocator) void {
    allocator.free(self.slice);
    switch (self.comic_info) {
        .@"1_0" => |comic_info| {
            comic_info.deinit(allocator);
        },
        .@"2_0" => |comic_info| {
            comic_info.deinit(allocator);
        },
    }
}
pub const Version = enum {
    @"1_0",
    @"2_0",
};

pub const ComicInfoData = union(Version) {
    @"1_0": ComicInfo_v1_0,
    @"2_0": ComicInfo_v2_0,
};

pub fn getComicInfo(allocator: Allocator, version: Version, slice: []u8) !ComicInfo {
    return .{
        .version = version,
        .slice = slice,
        .comic_info = switch (version) {
            .@"1_0" => .{
                .@"1_0" = try parse(ComicInfo_v1_0, allocator, slice),
            },
            .@"2_0" => .{
                .@"2_0" = try parse(ComicInfo_v2_0, allocator, slice),
            },
        },
    };
}

const parse = @import("parse.zig").parse;
const ComicInfo_v2_0 = @import("v2/comicinfo.zig");
const ComicInfo_v1_0 = @import("v1/comicinfo.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
