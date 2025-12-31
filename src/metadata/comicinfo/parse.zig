const log = std.log.scoped(.comic_info_v2_parse);

pub fn parse(T: type, allocator: Allocator, slice: []u8) !T {
    const parsed = try xml.parse.fromSlice(allocator, slice);
    defer parsed.deinit();

    const comic_info_tree = blk: {
        for (parsed.tree.children) |node| {
            switch (node) {
                .elem => |elem| {
                    if (std.mem.eql(u8, elem.tag_name, "ComicInfo")) {
                        break :blk elem.tree.?;
                    }
                },
                else => {},
            }
        }

        // if the loop is executed and there is no early exit from the block break inside elem,
        // that means that ComicInfo was not found in the children
        return error.ComicInfoMissing;
    };

    var comic_info: T = .{};
    var pages: std.ArrayList(T.ComicPageInfo) = .empty;
    defer pages.deinit(allocator);

    for (comic_info_tree.children) |node| {
        const elem = switch (node) {
            .elem => |e| e,
            else => continue,
        };

        const tree = elem.tree orelse continue;
        if (std.mem.eql(u8, elem.tag_name, "Pages")) {
            for (tree.children) |child_node| {
                if (child_node == .elem and std.mem.eql(u8, child_node.elem.tag_name, "Page")) {
                    const page_elem = child_node.elem;
                    var page_info: T.ComicPageInfo = .{ .Image = -1 };

                    for (page_elem.attributes) |attr| {
                        if (attr.value) |val| {
                            try populateField(T.ComicPageInfo, allocator, &page_info, attr.name, val);
                        }
                    }
                    if (page_info.Image == -1) {
                        log.warn("Image was not found inside ComicPageInfo!", .{});
                    }
                    try pages.append(allocator, page_info);
                }
            }
        } else {
            // simple types
            for (tree.children) |inner_node| {
                if (inner_node == .text) {
                    const content = inner_node.text.trimmed();
                    try populateField(T, allocator, &comic_info, elem.tag_name, content);
                }
            }
        }
    }

    comic_info.Pages = try pages.toOwnedSlice(allocator);
    return comic_info;
}

fn populateField(comptime T: type, allocator: Allocator, obj: *T, field_name: []const u8, value: []const u8) !void {
    inline for (std.meta.fields(T)) |field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            if (field.type == []const u8 or field.type == ?[]const u8) {
                @field(obj, field.name) = try allocator.dupe(u8, value);
                return;
            }

            const info = @typeInfo(field.type);
            const BaseType = if (info == .optional) info.optional.child else field.type;

            switch (@typeInfo(BaseType)) {
                .int => {
                    @field(obj, field.name) = try std.fmt.parseInt(BaseType, value, 10);
                },
                .float => {
                    @field(obj, field.name) = try std.fmt.parseFloat(BaseType, value);
                },
                .bool => {
                    if (std.ascii.eqlIgnoreCase(value, "yes") or std.ascii.eqlIgnoreCase(value, "true")) {
                        @field(obj, field.name) = true;
                    } else {
                        @field(obj, field.name) = false;
                    }
                },
                .@"enum" => {
                    if (std.meta.stringToEnum(BaseType, value)) |enum_val| {
                        @field(obj, field.name) = enum_val;
                    }
                },
                else => {},
            }
            return;
        }
    }
}

const xml = @import("xml");

const Allocator = std.mem.Allocator;
const std = @import("std");
