pub inline fn init(router: *Handler.Router) void {
    v1_2.init(router);
}

const v1_2 = @import("v1_2/routes.zig");

const Handler = @import("../handler.zig");
const httpz = @import("httpz");
