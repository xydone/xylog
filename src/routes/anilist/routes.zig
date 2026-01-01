const log = std.log.scoped(.anilist_route);

pub inline fn init(router: *Handler.Router) void {
    GetCallback.init(router);
    HandleCallback.init(router);
}

const GetCallback = Endpoint(struct {
    const Params = struct {
        client_id: u64,
        secret: []const u8,
    };
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = void,
        .method = .GET,
        .path = "/anilist/:client_id/:secret/callback",
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
            "http://{s}:{d}/anilist/{s}/{s}/{d}",
            .{
                config.address,
                config.port,
                req.params.secret,
                one_time_token,
                req.params.client_id,
            },
        );
        defer allocator.free(redirect_url);

        const authorization_url = try std.fmt.allocPrint(
            allocator,
            "https://anilist.co/api/v2/oauth/authorize?client_id={d}&redirect_uri={s}&response_type=code",
            .{ req.params.client_id, redirect_url },
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
        client_secret: []const u8,
        authentication: []const u8,
        client_id: u64,
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
        .path = "/anilist/:client_secret/:authentication/:client_id",
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

        // after having grabbed the code, we need to convert it to an access token
        // INFO: https://docs.anilist.co/guide/auth/authorization-code#converting-codes-to-tokens
        const http = HTTP{
            .url = "https://anilist.co/api/v2/oauth/token",
            .headers = "Content-Type: application/json\r\nAccept: application/json\r\n",
        };

        const TokenRequest = struct {
            grant_type: []const u8,
            client_id: u64,
            client_secret: []const u8,
            redirect_uri: []const u8,
            code: []const u8,
        };

        const redirect_uri = try std.fmt.allocPrint(
            allocator,
            "http://{s}:{d}/anilist/{s}/{s}/{d}",
            .{
                ctx.config.address,
                ctx.config.port,
                req.params.client_secret,
                req.params.authentication,
                req.params.client_id,
            },
        );
        defer allocator.free(redirect_uri);

        const payload = TokenRequest{
            .grant_type = "authorization_code",
            .client_id = req.params.client_id,
            .client_secret = req.params.client_secret,
            .redirect_uri = redirect_uri,
            .code = req.query.code,
        };
        const TokenResponse = struct {
            access_token: []const u8,
            token_type: []const u8,
            expires_in: i64,
        };

        var parsed_response = try http.post(allocator, payload, TokenResponse, .{ .ignore_unknown_fields = true });
        defer parsed_response.deinit();

        const access_token = parsed_response.value.access_token;
        std.debug.print("access token: {s}\n", .{access_token});

        const request: CreateDB.Request = .{
            .user_id = user_id,
            .service_name = "anilist",
            .plaintext_api_key = access_token,
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

const HTTP = @import("../../http.zig");
const Handler = @import("../../handler.zig");
const httpz = @import("httpz");

const Allocator = std.mem.Allocator;
const std = @import("std");
