catalog: *Catalog,
config: *Config,

const Handler = @This();
const log = std.log.scoped(.handler);

pub const Router = httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void);

pub const RequestContext = struct {
    catalog: *Catalog,
    config: *Config,
};

pub fn dispatch(self: *Handler, action: httpz.Action(*RequestContext), req: *httpz.Request, res: *httpz.Response) !void {
    var timer = try std.time.Timer.start();

    var ctx = RequestContext{
        .catalog = self.catalog,
        .config = self.config,
    };

    try action(&ctx, req, res);

    try Logging.print(Logging{
        .allocator = req.arena,
        .req = req.*,
        .res = res.*,
        .timer = &timer,
        .url_path = req.url.path,
    });
}

const zdt = @import("zdt");

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

const Catalog = @import("catalog.zig");
const Config = @import("config/config.zig");

const types = @import("types.zig");

const httpz = @import("httpz");

const Allocator = std.mem.Allocator;
const std = @import("std");
