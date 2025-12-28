pub const XML = struct {
    pub fn printElement(writer: *std.Io.Writer, tag: []const u8, value: []const u8) !void {
        try writer.print("<{s}>", .{tag});
        try writer.writeAll(value);
        const tagName = if (std.mem.indexOf(u8, tag, " ")) |idx| tag[0..idx] else tag;
        try writer.print("</{s}>", .{tagName});
    }
};

pub const Link = struct {
    // https://datatracker.ietf.org/doc/html/rfc4287#section-4.2.7
    rel: []const u8,
    type: []const u8,
    href: []const u8,
};

pub const OpenSearchDescription = struct {
    short_name: []const u8,
    description: []const u8,
    input_encoding: []const u8,
    output_encoding: []const u8,
    url: struct {
        template: []const u8,
        type: []const u8 = "application/atom+xml;profile=opds-catalog;kind=acquisition",
    },

    pub fn writeXML(self: OpenSearchDescription, writer: *std.Io.Writer) !void {
        try writer.writeAll("<?xml version=\"1.0\"?>");
        try writer.writeAll("<OpenSearchDescription>");
        try XML.printElement(writer, "ShortName", self.short_name);
        try XML.printElement(writer, "Description", self.description);
        try XML.printElement(writer, "InputEncoding", self.input_encoding);
        try XML.printElement(writer, "OutputEncoding", self.output_encoding);
        try writer.print("<Url template=\"{s}\" type=\"{s}\"/>", .{ self.url.template, self.url.type });
        try writer.writeAll("</OpenSearchDescription>");
    }
};

const std = @import("std");
