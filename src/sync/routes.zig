pub inline fn init(router: *Handler.Router) void {
    KOReader.init(router);
}

const KOReader = @import("koreader/routes.zig");

const Handler = @import("../handler.zig");
const httpz = @import("httpz");
