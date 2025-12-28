pub inline fn init(router: *Handler.Router) void {
    Library.init(router);
}

const Library = @import("library.zig");

const Handler = @import("../../handler.zig");
const httpz = @import("httpz");
