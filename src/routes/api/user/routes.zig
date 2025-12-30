const log = std.log.scoped(.user_route);
pub inline fn init(router: *Handler.Router) void {
    Create.init(router);
}

const Create = Endpoint(struct {
    const Body = struct {
        username: []const u8,
        password: []const u8,
    };
    const Response = struct {
        id: i64,
    };
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
        },
        .Response = Response,
        .method = .POST,
        .path = "/api/user",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(Body, void, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const request: CreateDB.Request = .{
            .username = req.body.username,
            .password = req.body.password,
        };
        const create_response = CreateDB.call(allocator, ctx.database.*, request) catch |err| {
            log.err("Create database call failed! Error is {}", .{err});
            handleResponse(res, .internal_server_error, "Couldn't create user.");
            return;
        };
        const response: Response = .{
            .id = create_response.id,
        };
        res.status = 200;
        try res.json(response, .{});
    }
});

const CreateDB = @import("../../../database/user.zig").Create;

const Endpoint = @import("../../../endpoint.zig").Endpoint;
const EndpointRequest = @import("../../../endpoint.zig").EndpointRequest;
const EndpointData = @import("../../../endpoint.zig").EndpointData;
const handleResponse = @import("../../../endpoint.zig").handleResponse;

const Handler = @import("../../../handler.zig");

const httpz = @import("httpz");

const std = @import("std");
