version: Version,
slice: []const u8,
comic_info: ComicInfoData,

const ComicInfo = @This();

pub const Version = enum {
    @"1_0",
    @"2_0",
};

pub const ComicInfoData = union(Version) {
    @"1_0": void, // FIXME: currently void as we dont have a v1 implementation
    @"2_0": ComicInfo_v2_0,
};

pub fn getComicInfo(allocator: Allocator, version: Version, slice: []u8) !ComicInfo {
    return .{
        .version = version,
        .slice = slice,
        // this field will later be filled
        .comic_info = switch (version) {
            .@"1_0" => {
                // FIXME: currently unreachable as we dont have a v1 implementation
                unreachable;
            },
            .@"2_0" => .{
                .@"2_0" = try parse_v2_0(allocator, slice),
            },
        },
    };
}

const parse_v2_0 = @import("v2/parse.zig").parse;
const ComicInfo_v2_0 = @import("v2/comicinfo.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
