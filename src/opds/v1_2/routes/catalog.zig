pub inline fn init(router: *Handler.Router) void {
    Serve.init(router);
}

const Serve = Endpoint(struct {
    const Params = struct { path: []const u8 };

    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = void,
        .method = .GET,
        .path = "/opds/v1.2/:path",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const is_catalog_request = std.mem.eql(u8, req.params.path, "catalog");

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
            req.params.path,
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
            if (is_catalog_request) {
                for (ctx.catalog.libraries.items) |library| {
                    // WARNING: this leaks in a non arena allocator!
                    const library_address = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ opds_address, library.name });

                    try entries.append(
                        allocator,
                        .{
                            .title = library.name,
                            .updated = date_writer.written(),
                            .id = library.name,
                            .content = library.name,
                            .link = .{
                                .type = "application/atom+xml;profile=opds-catalog;kind=navigation",
                                .rel = "subsection",
                                .href = library_address,
                            },
                        },
                    );
                }
            } else {
                // handle cases in which the catalog is not requested as cases in which the library itself is requested.
                for (ctx.catalog.libraries.items, 0..) |library, i| loop: {
                    if (std.mem.eql(u8, req.params.path, library.name)) {
                        for (ctx.catalog.libraries.items[i].books.items) |book| {

                            // WARNING: this leaks in a non arena allocator!
                            const book_address = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{
                                opds_address,
                                library.name,
                                book.name,
                            });

                            try entries.append(
                                allocator,
                                .{
                                    .title = book.name,
                                    .updated = date_writer.written(),
                                    .id = book.name,
                                    .content = "",
                                    .link = .{
                                        .rel = "subsection",
                                        .href = book_address,
                                        .type = "application/atom+xml;profile=opds-catalog;kind=navigation",
                                    },
                                },
                            );
                        }
                        break :loop;
                    }
                }
            }

            break :blk .{
                .feed = .{
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

const Link = @import("../types.zig").Link;
const Catalog = @import("../catalog.zig");

const Endpoint = @import("../../../endpoint.zig").Endpoint;
const EndpointRequest = @import("../../../endpoint.zig").EndpointRequest;
const EndpointData = @import("../../../endpoint.zig").EndpointData;

const Handler = @import("../../../handler.zig");

const zdt = @import("zdt");
const httpz = @import("httpz");

const std = @import("std");
