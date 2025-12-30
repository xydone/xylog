const log = std.log.scoped(.auth_route);
pub inline fn init(router: *Handler.Router) void {
    CreateAPIKey.init(router);
}

pub const CreateAPIKey = Endpoint(struct {
    const Body = struct {
        username: []const u8,
        password: []const u8,
    };
    const Response = struct {
        id: i64,
        key: []u8,
    };
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
        },
        .Response = void,
        .method = .POST,
        .path = "/api/auth/api-keys",
    };
    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(Body, void, void), res: *httpz.Response) anyerror!void {
        const request: CreateDB.Request = .{
            .username = req.body.username,
            .password = req.body.password,
        };
        const create_response = CreateDB.call(ctx.database.*, res.arena, request) catch {
            handleResponse(res, .internal_server_error, null);
            return;
        };
        defer create_response.deinit(res.arena);

        const response: Response = .{
            .id = create_response.id,
            .key = create_response.full_key,
        };

        res.status = 200;
        try res.json(response, .{});
    }
});

const CreateDB = @import("../../../database/api_keys.zig").Create;

const Endpoint = @import("../../../endpoint.zig").Endpoint;
const EndpointRequest = @import("../../../endpoint.zig").EndpointRequest;
const EndpointData = @import("../../../endpoint.zig").EndpointData;
const handleResponse = @import("../../../endpoint.zig").handleResponse;

const Handler = @import("../../../handler.zig");

const httpz = @import("httpz");

const std = @import("std");
