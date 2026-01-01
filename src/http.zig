url: []const u8,
headers: []const u8,

const Self = @This();

const log = std.log.scoped(.http);

const WriteContext = struct {
    buffer: *std.ArrayList(u8),
    allocator: Allocator,
};

fn writeCallback(contents: [*]u8, size: usize, nmemb: usize, userp: *anyopaque) callconv(.c) usize {
    const realsize = size * nmemb;
    const ctx = @as(*WriteContext, @ptrCast(@alignCast(userp)));

    ctx.buffer.appendSlice(ctx.allocator, contents[0..realsize]) catch return 0;

    return realsize;
}

pub fn post(
    self: Self,
    allocator: Allocator,
    payload: anytype,
    comptime T: type,
    options: std.json.ParseOptions,
) !std.json.Parsed(T) {
    _ = c.curl_global_init(c.CURL_GLOBAL_ALL);
    defer c.curl_global_cleanup();

    var json_payload = std.Io.Writer.Allocating.init(allocator);
    defer json_payload.deinit();

    const json_formatter = std.json.fmt(payload, .{});
    try json_formatter.format(&json_payload.writer);

    // 2. Initialize Curl
    _ = c.curl_global_init(c.CURL_GLOBAL_ALL);
    defer c.curl_global_cleanup();

    const curl = c.curl_easy_init() orelse return error.CurlInitFailed;
    defer c.curl_easy_cleanup(curl);

    var response_buffer = std.ArrayList(u8).empty;
    errdefer response_buffer.deinit(allocator);

    var head: ?*c.struct_curl_slist = null;
    defer c.curl_slist_free_all(head);

    head = c.curl_slist_append(head, "Content-Type: application/json");

    var it = std.mem.tokenizeSequence(u8, self.headers, "\r\n");
    while (it.next()) |h| {
        const h_z = try allocator.dupeZ(u8, h);
        defer allocator.free(h_z);
        head = c.curl_slist_append(head, h_z);
    }

    const written = json_payload.written();

    _ = c.curl_easy_setopt(curl, c.CURLOPT_URL, self.url.ptr);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_HTTPHEADER, head);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_POST, @as(c_long, 1));
    _ = c.curl_easy_setopt(curl, c.CURLOPT_POSTFIELDS, written.ptr);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(written.len)));

    var write_ctx = WriteContext{
        .buffer = &response_buffer,
        .allocator = allocator,
    };
    _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEFUNCTION, writeCallback);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEDATA, &write_ctx);

    const res = c.curl_easy_perform(curl);

    if (res != c.CURLE_OK) {
        log.err("curl error: {s}\n", .{c.curl_easy_strerror(res)});
        return error.CurlRequestFailed;
    }

    var response_code: c_long = 0;
    _ = c.curl_easy_getinfo(curl, c.CURLINFO_RESPONSE_CODE, &response_code);
    if (response_code >= 400) {
        log.err("HTTP Error: {d}\nBody: {s}", .{ response_code, response_buffer.items });
        return error.HttpError;
    }

    return std.json.parseFromSlice(T, allocator, response_buffer.items, options);
}

const c = @cImport({
    @cInclude("curl/curl.h");
});

const Allocator = std.mem.Allocator;
const std = @import("std");
