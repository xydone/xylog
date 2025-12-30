const log = std.log.scoped(.anilist_route);

pub inline fn init(router: *Handler.Router) void {
    GetCallback.init(router);
    HandleCallback.init(router);
}

const GetCallback = Endpoint(struct {
    const Params = struct {
        anilist_client_id: u64,
    };
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = void,
        .method = .GET,
        .path = "/anilist/:anilist_client_id/callback",
        .route_data = .{
            .restricted = true,
        },
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const config = ctx.config;
        const one_time_token = try createOneTimeToken(allocator);

        try ctx.one_time_token_map.put(one_time_token, ctx.user_id.?);

        const redirect_url = try std.fmt.allocPrint(
            allocator,
            "http://{s}:{d}/{s}/anilist",
            .{
                config.address,
                config.port,
                one_time_token,
            },
        );
        defer allocator.free(redirect_url);

        const authorization_url = try std.fmt.allocPrint(
            allocator,
            "https://anilist.co/api/v2/oauth/authorize?client_id={d}&redirect_uri={s}&response_type=code",
            .{ req.params.anilist_client_id, redirect_url },
        );

        const response: struct {
            create_application_url: []const u8,
            redirect_url: []const u8,
            authorization_url: []const u8,
        } = .{
            .create_application_url = "https://anilist.co/settings/developer",
            .redirect_url = redirect_url,
            .authorization_url = authorization_url,
        };
        res.status = 200;
        try res.json(response, .{});
    }
});

const HandleCallback = Endpoint(struct {
    const Params = struct {
        authentication: []const u8,
    };
    const Query = struct {
        code: []const u8,
    };
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Query = Query,
            .Params = Params,
        },
        .Response = void,
        .method = .GET,
        .path = "/:authentication/anilist",
        // INFO: the reason why this endpoint handles authentication manually is because AniList cannot send us the request with the required API key
        // This means we have to append the authentication element into the request path itself
        .route_data = .{},
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(void, Params, Query), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;

        // manually handle authentication
        const user_id = ctx.one_time_token_map.get(req.params.authentication) orelse {
            log.warn("One time token couldn't be found inside map.", .{});
            handleResponse(res, .forbidden, "No such one time token found!");
            return;
        };
        // make sure to remove and deinitialize the one time token from the map when we are done with it
        const pair = ctx.one_time_token_map.fetchRemove(req.params.authentication).?;
        allocator.free(pair.key);

        const request: CreateDB.Request = .{
            .user_id = user_id,
            .service_name = "anilist",
            .plaintext_api_key = req.query.code,
        };
        _ = CreateDB.call(
            allocator,
            ctx.database.*,
            ctx.config.encryption_secret,
            request,
        ) catch |err| {
            log.err("API Key database create call failed with: {}", .{err});
            handleResponse(res, .internal_server_error, "Couldn't save API key into database.");
            return;
        };
        res.status = 200;
        res.body = "Success! You may close this tab now.";
    }
});

const CreateDB = @import("../../database/trackers_api_keys.zig").Create;

const Endpoint = @import("../../endpoint.zig").Endpoint;
const EndpointRequest = @import("../../endpoint.zig").EndpointRequest;
const EndpointData = @import("../../endpoint.zig").EndpointData;
const handleResponse = @import("../../endpoint.zig").handleResponse;

const createOneTimeToken = @import("../../auth/util.zig").createOneTimeToken;

const Handler = @import("../../handler.zig");
const httpz = @import("httpz");

const Allocator = std.mem.Allocator;
const std = @import("std");
