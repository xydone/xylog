catalog: *Catalog,
config: *Config,
database: *Database,
one_time_token_map: *OneTimeTokenMap,

const Handler = @This();

/// one time, short lived token -> user id
///
/// meant to be used with tracker authentication which requires a callback url
pub const OneTimeTokenMap = std.StringHashMap(i64);

pub fn init(allocator: Allocator, parameters: struct {
    catalog: *Catalog,
    config: *Config,
    database: *Database,
}) !Handler {
    const one_time_token_map = try allocator.create(OneTimeTokenMap);
    one_time_token_map.* = OneTimeTokenMap.init(allocator);
    return .{
        .catalog = parameters.catalog,
        .config = parameters.config,
        .database = parameters.database,
        .one_time_token_map = one_time_token_map,
    };
}

pub fn deinit(self: *Handler, allocator: Allocator) void {
    {
        defer allocator.destroy(self.one_time_token_map);
        var it = self.one_time_token_map.keyIterator();
        while (it.next()) |token| {
            allocator.free(token.*);
        }
        self.one_time_token_map.deinit();
    }
}

const log = std.log.scoped(.handler);

pub const Router = httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void);

pub const RouteData = struct {
    restricted: bool = false,
};

pub const RequestContext = struct {
    user_id: ?i64,
    catalog: *Catalog,
    config: *Config,
    database: *Database,
    one_time_token_map: *OneTimeTokenMap,
};

pub fn dispatch(self: *Handler, action: httpz.Action(*RequestContext), req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    var timer = try std.time.Timer.start();

    var ctx = RequestContext{
        .user_id = null,
        .catalog = self.catalog,
        .config = self.config,
        .database = self.database,
        .one_time_token_map = self.one_time_token_map,
    };

    authenticateRequest(allocator, &ctx, req, res) catch {
        return try Logging.print(Logging{
            .allocator = allocator,
            .req = req.*,
            .res = res.*,
            .timer = &timer,
            .url_path = req.url.path,
        });
    };

    try action(&ctx, req, res);

    try Logging.print(Logging{
        .allocator = allocator,
        .req = req.*,
        .res = res.*,
        .timer = &timer,
        .url_path = req.url.path,
    });
}

fn authenticateRequest(allocator: Allocator, ctx: *RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    const api_key = req.header("x-api-key");
    if (req.route_data) |rd| {
        const route_data: *const RouteData = @ptrCast(@alignCast(rd));
        if (route_data.restricted) {
            if (api_key) |key| {
                verifyAPIKey(allocator, ctx, key) catch {
                    handleResponse(res, .unauthorized, "Permission denied!");
                    return error.AuthenticationFailed;
                };
            } else {
                handleResponse(res, .unauthorized, "Permission denied!");
                return error.AuthenticationFailed;
            }
        }
    }
}

fn verifyAPIKey(allocator: Allocator, ctx: *RequestContext, api_key: []const u8) error{CannotGet}!void {
    const response = GetByAPIKey.call(allocator, ctx.database.*, api_key) catch return error.CannotGet;
    ctx.user_id = response.id;
}

const Logging = struct {
    allocator: std.mem.Allocator,
    timer: *std.time.Timer,
    req: httpz.Request,
    res: httpz.Response,
    url_path: []const u8,
    pub fn print(self: Logging) !void {
        const time = self.timer.read();
        const locale = try zdt.Timezone.tzLocal(self.allocator);
        const now = try zdt.Datetime.now(.{ .tz = &locale });

        var writer = std.Io.Writer.Allocating.init(self.allocator);
        defer writer.deinit();
        // https://github.com/FObersteiner/zdt/wiki/String-parsing-and-formatting-directives
        try now.toString("[%Y-%m-%d %H:%M:%S]", &writer.writer);
        const datetime = try writer.toOwnedSlice();
        std.debug.print("{s} {s} {s} {s}{d}\x1b[0m in {d:.2}ms ({d}ns)\n", .{
            datetime,
            @tagName(self.req.method),
            self.url_path,
            //ansi coloring (https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797)
            switch (self.res.status / 100) {
                //green
                2 => "\x1b[32m",
                //red
                4 => "\x1b[31m",
                // if its not a 2XX or 3XX, yellow
                else => "\x1b[33m",
            },
            self.res.status,
            //in ms
            @as(f64, @floatFromInt(time)) / std.time.ns_per_ms,
            //in nanoseconds
            time,
        });
    }
};

const GetByAPIKey = @import("database/user.zig").GetByAPIKey;

const handleResponse = @import("endpoint.zig").handleResponse;

const Auth = @import("auth/util.zig");
const Catalog = @import("catalog.zig");
const Database = @import("database.zig");
const Config = @import("config/config.zig");

const types = @import("types.zig");

const zdt = @import("zdt");
const httpz = @import("httpz");

const Allocator = std.mem.Allocator;
const std = @import("std");
