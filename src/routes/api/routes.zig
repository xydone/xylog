pub inline fn init(router: *Handler.Router) void {
    Library.init(router);
    User.init(router);
    Auth.init(router);
}

const Library = @import("library/routes.zig");
const User = @import("user/routes.zig");
const Auth = @import("auth/routes.zig");

const Handler = @import("../../handler.zig");
const httpz = @import("httpz");
