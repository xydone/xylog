pub inline fn init(router: *Handler.Router) void {
    Catalog.init(router);
}

const Catalog = @import("routes/catalog.zig");

const Handler = @import("../../handler.zig");

const httpz = @import("httpz");
