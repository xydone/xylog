pub inline fn init(router: *Handler.Router) void {
    GetCatalog.init(router);
    GetBook.init(router);
    GetChapter.init(router);
}

const GetCatalog = Endpoint(struct {
    const Params = struct { library: []const u8 };

    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = void,
        .method = .GET,
        .path = "/opds/v1.2/:library",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const is_catalog_request = std.mem.eql(u8, req.params.library, "catalog");

        const writer = res.writer();
        res.header("Content-Type", "application/xml");

        var date_writer = std.Io.Writer.Allocating.init(allocator);
        defer date_writer.deinit();
        try ctx.catalog.update_time.toString("%T", &date_writer.writer);

        var links = std.ArrayList(Link).empty;
        defer links.deinit(allocator);

        const opds_address = try std.fmt.allocPrint(
            allocator,
            "http://{s}:{d}/opds/v1.2",
            .{ ctx.config.address, ctx.config.port },
        );
        defer allocator.free(opds_address);

        const start_address = try std.fmt.allocPrint(allocator, "{s}/catalog", .{opds_address});
        defer allocator.free(start_address);

        const self_address = try std.fmt.allocPrint(allocator, "{s}/{s}", .{
            opds_address,
            req.params.library,
        });
        defer allocator.free(self_address);

        var root_links = [_]Link{
            .{
                .type = "application/atom+xml;profile=opds-catalog;kind=navigation",
                .rel = "self",
                .href = self_address,
            },
            .{
                .type = "application/atom+xml;profile=opds-catalog;kind=navigation",
                .rel = "start",
                .href = start_address,
            },
        };

        try links.appendSlice(allocator, &root_links);

        var entries = std.ArrayList(Catalog.Entry).empty;
        defer entries.deinit(allocator);

        const catalog: Catalog = blk: {
            var library_it = ctx.catalog.libraries.iterator();
            if (is_catalog_request) {
                while (library_it.next()) |entry| {
                    const library_name = entry.key_ptr.*;
                    // WARNING: this leaks in a non arena allocator!
                    const library_address = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ opds_address, library_name });

                    try entries.append(
                        allocator,
                        .{
                            .title = library_name,
                            .updated = date_writer.written(),
                            .id = library_name,
                            .content = library_name,
                            .link = .{
                                .type = "application/atom+xml;profile=opds-catalog;kind=navigation",
                                .rel = "subsection",
                                .href = library_address,
                            },
                        },
                    );
                }
            } else {
                //TODO: handle missing library
                const library = ctx.catalog.libraries.get(req.params.library) orelse return error.NoLibrary;
                // handle cases in which the catalog is not requested as cases in which the library itself is requested.
                var book_it = library.books.valueIterator();
                while (book_it.next()) |book| {
                    // WARNING: this leaks in a non arena allocator!
                    const book_address = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{
                        opds_address,
                        req.params.library,
                        book.*.name,
                    });

                    try entries.append(
                        allocator,
                        .{
                            .title = book.*.name,
                            .updated = date_writer.written(),
                            .id = book.*.name,
                            .content = "",
                            .link = .{
                                .rel = "subsection",
                                .href = book_address,
                                .type = "application/atom+xml;profile=opds-catalog;kind=navigation",
                            },
                        },
                    );
                }
            }

            break :blk .{
                .feed = .{
                    .id = "root",
                    .title = "Xylog OPDS catalog",
                    .updated = date_writer.written(),
                    .author = .{},
                    .links = try links.toOwnedSlice(allocator),
                    .entries = try entries.toOwnedSlice(allocator),
                },
            };
        };
        try catalog.writeXML(writer);
    }
});

const GetBook = Endpoint(struct {
    const Params = struct {
        library: []const u8,
        book: []const u8,
    };

    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = void,
        .method = .GET,
        .path = "/opds/v1.2/:library/:book",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;

        const writer = res.writer();
        res.header("Content-Type", "application/xml");

        var date_writer = std.Io.Writer.Allocating.init(allocator);
        defer date_writer.deinit();
        try ctx.catalog.update_time.toString("%T", &date_writer.writer);

        var links = std.ArrayList(Link).empty;
        defer links.deinit(allocator);

        const opds_address = try std.fmt.allocPrint(
            allocator,
            "http://{s}:{d}/opds/v1.2",
            .{ ctx.config.address, ctx.config.port },
        );
        defer allocator.free(opds_address);

        const start_address = try std.fmt.allocPrint(allocator, "{s}/catalog", .{opds_address});
        defer allocator.free(start_address);

        const self_address = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{
            opds_address,
            req.params.library,
            req.params.book,
        });
        defer allocator.free(self_address);

        var root_links = [_]Link{
            .{
                .type = "application/atom+xml;profile=opds-catalog;kind=navigation",
                .rel = "self",
                .href = self_address,
            },
            .{
                .type = "application/atom+xml;profile=opds-catalog;kind=navigation",
                .rel = "start",
                .href = start_address,
            },
        };

        try links.appendSlice(allocator, &root_links);

        var entries = std.ArrayList(Catalog.Entry).empty;
        defer entries.deinit(allocator);

        const catalog: Catalog = blk: {
            // TODO: handle no library
            const library = ctx.catalog.libraries.get(req.params.library) orelse return error.NoLibrary;
            // TODO: handle no book
            const book = library.books.get(req.params.book) orelse return error.NoBook;
            var chapter_it = book.chapters.valueIterator();
            while (chapter_it.next()) |chapter| {
                const encoded_chapter_name = std.Uri.Component{ .raw = chapter.*.name };
                // WARNING: this leaks in a non arena allocator!
                const book_address = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}/{f}", .{
                    opds_address,
                    req.params.library,
                    req.params.book,
                    std.fmt.alt(encoded_chapter_name, .formatEscaped),
                });
                try entries.append(allocator, .{
                    .title = chapter.*.name,
                    .id = chapter.*.name,
                    .updated = date_writer.written(),
                    .content = "",
                    .link = .{
                        .href = book_address,
                        .rel = "http://opds-spec.org/acquisition",
                        .type = "application/zip",
                    },
                });
            }
            break :blk .{
                .feed = .{
                    .id = req.params.book,
                    .title = req.params.book,
                    .updated = date_writer.written(),
                    .author = .{},
                    .links = try links.toOwnedSlice(allocator),
                    .entries = try entries.toOwnedSlice(allocator),
                },
            };
        };
        try catalog.writeXML(writer);
    }
});

const GetChapter = Endpoint(struct {
    const Params = struct {
        library: []const u8,
        book: []const u8,
        chapter: []const u8,
    };

    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = void,
        .method = .GET,
        .path = "/opds/v1.2/:library/:book/:chapter",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;

        const duped_chapter = try allocator.dupe(u8, req.params.chapter);
        defer allocator.free(duped_chapter);

        const decoded_name = std.Uri.percentDecodeInPlace(duped_chapter);

        const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}/{s}", .{
            ctx.config.catalog_dir,
            req.params.library,
            req.params.book,
            decoded_name,
        });
        defer allocator.free(file_path);

        const file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();

        // hardcoded 20mb
        // NOTE: this is not freed on purpose. the arena will clean it up but freeing it manually will send garbage to the client.
        const file_contents = try file.readToEndAlloc(allocator, 1024 * 1024 * 20);

        res.status = 200;
        res.header("Content-Type", "application/zip");

        // NOTE: this is not freed on purpose. the arena will clean it up but freeing it manually will send garbage to the client.
        const header_value = try std.fmt.allocPrint(
            allocator,
            "attachment; filename=\"{s}\"; filename*=UTF-8''{s}",
            .{ decoded_name, duped_chapter },
        );

        res.header("Content-Disposition", header_value);
        res.body = file_contents;
    }
});

const Link = @import("../types.zig").Link;
const Catalog = @import("../catalog.zig");

const Endpoint = @import("../../../endpoint.zig").Endpoint;
const EndpointRequest = @import("../../../endpoint.zig").EndpointRequest;
const EndpointData = @import("../../../endpoint.zig").EndpointData;

const Handler = @import("../../../handler.zig");

const zdt = @import("zdt");
const httpz = @import("httpz");

const std = @import("std");
