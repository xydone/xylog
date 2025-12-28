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
        // TODO: look into storing all books across all libraries globally instead?
        var library_it = ctx.catalog.libraries.valueIterator();
        while (library_it.next()) |library| {
            const chapter = library.getChapterByHash(req.body.document) catch {
                handleResponse(res, .not_found, "Chapter not found!");
                return;
            };
            const chapter_number = std.fmt.parseInt(i64, req.body.progress, 10) catch {
                std.debug.print("Received progress of {s} when assuming it is a number\n", .{req.body.progress});
                var buf: [1024]u8 = undefined;
                const details: ?[]u8 = std.fmt.bufPrint(&buf, "Received progress of {s} when assuming it is a number", .{req.body.progress}) catch blk: {
                    break :blk null;
                };

                handleResponse(res, .bad_request, details);
                return;
            };
            chapter.updateProgress(ctx.database.*, chapter_number) catch {
                handleResponse(res, .internal_server_error, "Failed to update progress!");
                return;
            };
            break;
        }
        res.status = 200;
    }
});

const GetProgress = Endpoint(struct {
    const Params = struct { document: []const u8 };
    const Response = struct {
        progress: []const u8,
        document: []const u8,

        percentage: ?f32,
        device: ?[]const u8,
        device_id: ?[]const u8,
    };

    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = Response,
        .method = .GET,
        .path = "/koreader/syncs/progress/:document",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        // TODO: look into storing all books across all libraries globally instead?
        var library_it = ctx.catalog.libraries.valueIterator();
        while (library_it.next()) |library| {
            const chapter = library.getChapterByHash(req.params.document) catch continue;
            var buf: [16]u8 = undefined;
            const progress = try std.fmt.bufPrint(&buf, "{}", .{chapter.progress});

            const percentage: f32 = blk: {
                const total_pages_float: f32 = @floatFromInt(chapter.total_pages);
                const progress_float: f32 = @floatFromInt(chapter.progress);
                break :blk progress_float / total_pages_float;
            };

            // tracking issue: https://github.com/koreader/koreader/issues/14596
            const json_formatter = std.json.fmt(Response{
                .progress = progress,
                .document = req.params.document,
                .percentage = percentage,
                .device = null,
                .device_id = null,
            }, .{});
            try json_formatter.format(&res.buffer.writer);

            res.header("Content-Type", "application/json");
            res.status = 200;
            return;
        }

        handleResponse(res, .not_found, "Chapter not found!");
        return;
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
