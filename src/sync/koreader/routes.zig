// INFO: API spec for KOReader client:
// https://github.com/koreader/koreader/blob/6ee248d8009f7861df468ab9dc46d828c453a125/plugins/kosync.koplugin/api.json

// INFO: Server implementation in KOSync:
// https://github.com/koreader/koreader-sync-server/blob/a6b538b7de225d753d64e5a65a442f0d8b4e92c1/app/controllers/1/syncs_controller.lua

pub inline fn init(router: *Handler.Router) void {
    CreateUser.init(router);
    GetAuth.init(router);
    UpdateProgress.init(router);
    GetProgress.init(router);
}

// TODO: authentication?
const CreateUser = Endpoint(struct {
    const Body = struct {
        username: []const u8,
        password: []const u8,
    };
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
        },
        .Response = void,
        .method = .POST,
        .path = "/koreader/users/create",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(Body, void, void), res: *httpz.Response) anyerror!void {
        _ = ctx;
        _ = req;
        handleResponse(res, .forbidden, "User creation is not supported!");
    }
});

// TODO: authentication?
const GetAuth = Endpoint(struct {
    pub const endpoint_data: EndpointData = .{
        .Request = .{},
        .Response = void,
        .method = .GET,
        .path = "/koreader/users/auth",
    };

    pub fn call(ctx: *Handler.RequestContext, _: EndpointRequest(void, void, void), res: *httpz.Response) anyerror!void {
        _ = ctx;
        res.status = 200;
        res.body = "Authorized.";
    }
});

const UpdateProgress = Endpoint(struct {
    const Body = struct {
        /// book hash
        document: []const u8,
        /// in CBZs, PDFs, etc, this is the page.
        /// NOTE: research how it interacts with epubs?
        progress: []const u8,
        /// 0-1
        percentage: f32,
        /// device name
        device: []const u8,
        /// device unique id
        device_id: []const u8,
    };
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
        },
        .Response = void,
        .method = .PUT,
        .path = "/koreader/syncs/progress",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(Body, void, void), res: *httpz.Response) anyerror!void {
        // const allocator = res.arena;
        std.debug.print("document: {s}\n", .{req.body.document});
        std.debug.print("progress: {s}\n", .{req.body.progress});
        std.debug.print("percentage: {}\n", .{req.body.percentage});
        std.debug.print("device: {s}\n", .{req.body.device});
        std.debug.print("device id: {s}\n", .{req.body.device_id});
        // TODO: look into storing all books across all libraries globally instead?
        var library_it = ctx.catalog.libraries.valueIterator();
        while (library_it.next()) |library| {
            // TODO: handle missing books gracefully
            const book = library.getChapterByHash(req.body.document) catch |err| {
                std.debug.print("err: {}\n", .{err});
                return error.NotFound;
            };
            std.debug.print("book: {s}\n", .{book.name});
            break;
        }
        _ = res;
    }
});

const GetProgress = Endpoint(struct {
    const Params = struct { document: []const u8 };

    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = void,
        .method = .GET,
        .path = "/koreader/syncs/progress/:document",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        _ = ctx;
        _ = req;
        _ = res;
        @panic("not implemented!");
    }
});

const partialMd5 = @import("util.zig").partialMd5;

const Endpoint = @import("../../endpoint.zig").Endpoint;
const EndpointRequest = @import("../../endpoint.zig").EndpointRequest;
const EndpointData = @import("../../endpoint.zig").EndpointData;
const handleResponse = @import("../../endpoint.zig").handleResponse;

const Handler = @import("../../handler.zig");

const zdt = @import("zdt");
const httpz = @import("httpz");

const std = @import("std");
