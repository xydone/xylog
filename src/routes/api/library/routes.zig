const log = std.log.scoped(.library_route);
pub inline fn init(router: *Handler.Router) void {
    Scan.init(router);
}

const Scan = Endpoint(struct {
    pub const endpoint_data: EndpointData = .{
        .Request = .{},
        .Response = void,
        .method = .POST,
        .path = "/koreader/users/create",
    };

    pub fn call(ctx: *Handler.RequestContext, _: EndpointRequest(void, void, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        ctx.catalog.scan(allocator, ctx.database.*) catch |err| {
            log.err("Library scan failed: {}\n", .{err});
            handleResponse(res, .internal_server_error, "Couldn't scan library.");
            return;
        };

        res.status = 200;
    }
});

const Book = @import("../../../catalog/book.zig");

const Endpoint = @import("../../../endpoint.zig").Endpoint;
const EndpointRequest = @import("../../../endpoint.zig").EndpointRequest;
const EndpointData = @import("../../../endpoint.zig").EndpointData;
const handleResponse = @import("../../../endpoint.zig").handleResponse;

const Handler = @import("../../../handler.zig");

const httpz = @import("httpz");

const std = @import("std");
