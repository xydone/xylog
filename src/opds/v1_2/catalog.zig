// https://specs.opds.io/opds-1.2.html#2-opds-catalog-feed-documents
feed: Feed,

pub const Feed = struct {
    id: []const u8,
    title: []const u8,
    updated: []const u8,
    author: Author,
    // OPDS Catalog Feed Documents should contain one atom:link element with a rel attribute value of self.
    // This is the preferred URI for retrieving the atom:feed representing this OPDS Catalog Feed Document.
    links: []Link,
    entries: []Entry,
};

pub const Author = struct {
    name: []const u8 = "Xylog",
    uri: []const u8 = "https://github.com/xydone/xylog",
};

pub const Entry = struct {
    title: []const u8,
    updated: []const u8,
    id: []const u8,
    content: []const u8,
    link: Link,
};

pub fn writeXML(self: @This(), writer: *std.Io.Writer) !void {
    try writer.writeAll("<?xml version=\"1.0\"?>");
    try writer.writeAll("<feed xmlns=\"http://www.w3.org/2005/Atom\">");

    try printElement(writer, "id", self.feed.id);
    try printElement(writer, "title", self.feed.title);
    try printElement(writer, "updated", self.feed.updated);

    try writer.writeAll("  <author>");
    try printElement(writer, "name", self.feed.author.name);
    try printElement(writer, "uri", self.feed.author.uri);
    try writer.writeAll("  </author>");

    for (self.feed.links) |link| {
        try writer.print("<link rel=\"{s}\" href=\"{s}\" type=\"{s}\" />", .{
            link.rel, link.href, link.type,
        });
    }

    for (self.feed.entries) |entry| {
        try writer.writeAll("<entry>");
        try printElement(writer, "title", entry.title);
        try printElement(writer, "id", entry.id);
        try printElement(writer, "updated", entry.updated);
        try printElement(writer, "content type=\"text\"", entry.content);
        try writer.print("<link rel=\"{s}\" href=\"{s}\" type=\"{s}\"/>", .{ entry.link.rel, entry.link.href, entry.link.type });
        try writer.writeAll("  </entry>");
    }

    try writer.writeAll("</feed>");
}

fn printElement(writer: *std.Io.Writer, tag: []const u8, value: []const u8) !void {
    try writer.print("<{s}>", .{tag});
    try writer.writeAll(value);
    const tagName = if (std.mem.indexOf(u8, tag, " ")) |idx| tag[0..idx] else tag;
    try writer.print("</{s}>", .{tagName});
}

const Catalog = @import("../../catalog.zig");
const Config = @import("../../config/config.zig");

const Link = @import("types.zig").Link;

const Allocator = std.mem.Allocator;
const std = @import("std");
