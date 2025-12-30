pub inline fn init(router: *Handler.Router) void {
    KOSync.init(router);
    AniList.init(router);
    OPDS.init(router);
    API.init(router);
}

const AniList = @import("anilist/routes.zig");
const KOSync = @import("kosync/routes.zig");
const OPDS = @import("opds/routes.zig");
const API = @import("api/routes.zig");

const Handler = @import("../handler.zig");
const httpz = @import("httpz");
