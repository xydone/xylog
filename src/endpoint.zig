pub const EndpointRequestType = struct {
    Body: type = void,
    Params: type = void,
    Query: type = void,
};

pub fn EndpointRequest(comptime Body: type, comptime Params: type, comptime Query: type) type {
    return struct {
        body: Body,
        params: Params,
        query: Query,
    };
}

pub const EndpointData = struct {
    Request: EndpointRequestType,
    Response: type,
    path: []const u8,
    method: httpz.Method,
    route_data: RouteData = .{},
};

pub fn Endpoint(
    comptime T: type,
) type {
    return struct {
        pub const endpoint_data: EndpointData = T.endpoint_data;
        const callImpl: fn (
            *Handler.RequestContext,
            EndpointRequest(T.endpoint_data.Request.Body, T.endpoint_data.Request.Params, T.endpoint_data.Request.Query),
            *httpz.Response,
        ) anyerror!void = T.call;

        pub fn init(router: *Router) void {
            const path = T.endpoint_data.path;
            const route_data = T.endpoint_data.route_data;
            switch (T.endpoint_data.method) {
                .GET => {
                    router.*.get(path, call, .{ .data = &route_data });
                },
                .POST => {
                    router.*.post(path, call, .{ .data = &route_data });
                },
                .PATCH => {
                    router.*.patch(path, call, .{ .data = &route_data });
                },
                .PUT => {
                    router.*.put(path, call, .{ .data = &route_data });
                },
                .OPTIONS => {
                    router.*.options(path, call, .{ .data = &route_data });
                },
                .CONNECT => {
                    router.*.connect(path, call, .{ .data = &route_data });
                },
                .DELETE => {
                    router.*.delete(path, call, .{ .data = &route_data });
                },
                .HEAD => {
                    router.*.head(path, call, .{ .data = &route_data });
                },
                // NOTE: http.zig supports non-standard http methods. For now, creating routes with a non-standard method is not supported.
                .OTHER => {
                    @compileError("Method OTHER is not supported!");
                },
            }
        }

        pub fn call(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
            const allocator = res.arena;
            const request: EndpointRequest(T.endpoint_data.Request.Body, T.endpoint_data.Request.Params, T.endpoint_data.Request.Query) = .{
                .body = blk: {
                    switch (@typeInfo(T.endpoint_data.Request.Body)) {
                        .void => break :blk {},
                        else => {
                            const body = req.body() orelse {
                                handleResponse(res, ResponseError.body_missing, null);
                                return;
                            };
                            break :blk std.json.parseFromSliceLeaky(T.endpoint_data.Request.Body, allocator, body, .{}) catch {
                                handleResponse(res, ResponseError.not_found, null);
                                return;
                            };
                        },
                    }
                },

                .params = blk: {
                    switch (@typeInfo(T.endpoint_data.Request.Params)) {
                        .void => {},
                        else => |type_info| {
                            var params: T.endpoint_data.Request.Params = undefined;
                            inline for (type_info.@"struct".fields) |field| {
                                const value = req.param(field.name) orelse {
                                    const msg = try std.fmt.allocPrint(allocator, "{s} not found inside parameters!", .{field.name});
                                    defer allocator.free(msg);
                                    return handleResponse(res, ResponseError.bad_request, msg);
                                };
                                switch (field.type) {
                                    u16, u32, u64, i16, i32, i64 => |t| @field(params, field.name) = try std.fmt.parseInt(t, value, 10),
                                    f16, f32, f64 => |t| @field(params, field.name) = try std.fmt.parseFloat(t, value),
                                    []const u8 => @field(params, field.name) = value,
                                    else => |t| {
                                        switch (@typeInfo(t)) {
                                            .@"enum" => @field(params, field.name) = std.meta.stringToEnum(t, value) orelse {
                                                const enum_name = enum_blk: {
                                                    const name = @typeName(t);
                                                    // filter out the namespace that gets included inside the @typeInfo() response
                                                    // exit early if type does not have a namespace
                                                    const i = std.mem.lastIndexOfScalar(u8, name, '.') orelse break :enum_blk name;
                                                    break :enum_blk name[i + 1 ..];
                                                };
                                                const msg = try std.fmt.allocPrint(allocator, "Incorrect value '{s}' for enum {s}", .{ value, enum_name });
                                                defer allocator.free(msg);
                                                return handleResponse(res, ResponseError.bad_request, msg);
                                            },
                                            else => @compileError(std.fmt.comptimePrint("{} not supported!", .{t})),
                                        }
                                    },
                                }
                            }
                            break :blk params;
                        },
                    }
                },

                .query = blk: {
                    switch (@typeInfo(T.endpoint_data.Request.Query)) {
                        .void => {},
                        else => |type_info| {
                            var query: T.endpoint_data.Request.Query = undefined;
                            inline for (type_info.@"struct".fields) |field| {
                                var q = try req.query();
                                const value = q.get(field.name) orelse {
                                    const msg = try std.fmt.allocPrint(allocator, "{s} not found inside query!", .{field.name});
                                    defer allocator.free(msg);
                                    return handleResponse(res, ResponseError.bad_request, msg);
                                };
                                switch (field.type) {
                                    u16, u32, u64, i16, i32, i64 => |t| @field(query, field.name) = try std.fmt.parseInt(t, value, 10),
                                    f16, f32, f64 => |t| @field(query, field.name) = try std.fmt.parseFloat(t, value),
                                    []const u8, []u8 => @field(query, field.name) = value,
                                    else => |t| {
                                        switch (@typeInfo(t)) {
                                            .@"enum" => @field(query, field.name) = std.meta.stringToEnum(t, value) orelse {
                                                const enum_name = enum_blk: {
                                                    const name = @typeName(t);
                                                    // filter out the namespace that gets included inside the @typeInfo() response
                                                    // exit early if type does not have a namespace
                                                    const i = std.mem.lastIndexOfScalar(u8, name, '.') orelse break :enum_blk name;
                                                    break :enum_blk name[i + 1 ..];
                                                };
                                                const msg = try std.fmt.allocPrint(allocator, "Incorrect value '{s}' for enum {s}", .{ value, enum_name });
                                                defer allocator.free(msg);
                                                return handleResponse(res, ResponseError.bad_request, msg);
                                            },
                                            else => @compileError(std.fmt.comptimePrint("{} not supported!", .{t})),
                                        }
                                    },
                                }
                            }

                            break :blk query;
                        },
                    }
                },
            };

            try callImpl(ctx, request, res);
        }
    };
}

pub const ResponseError = struct {
    code: u16,
    message: []const u8,
    details: ?[]const u8 = null,

    // 400
    pub const bad_request: ResponseError = .{
        .code = 400,
        .message = "Bad request.",
    };
    pub const body_missing: ResponseError = .{
        .code = 400,
        .message = "The request body is not found.",
    };
    pub const body_missing_fields: ResponseError = .{
        .code = 400,
        .message = "The request body is missing required fields.",
    };
    pub const unauthorized: ResponseError = .{
        .code = 401,
        .message = "You are not authorized to make this request.",
    };
    pub const forbidden: ResponseError = .{
        .code = 403,
        .message = "Forbidden.",
    };
    pub const not_found: ResponseError = .{
        .code = 404,
        .message = "Not found.",
    };

    // 500
    pub const internal_server_error: ResponseError = .{
        .code = 500,
        .message = "An unexpected error occurred on the server. Please try again later.",
    };
};

pub fn handleResponse(httpz_res: *httpz.Response, response_error: ResponseError, details: ?[]const u8) void {
    var response = response_error;
    response.details = details orelse null;
    httpz_res.status = response.code;
    httpz_res.json(response, .{ .emit_null_optional_fields = false }) catch @panic("Couldn't parse error response.");
    return;
}

const Handler = @import("handler.zig");
const Router = Handler.Router;
const RouteData = Handler.RouteData;

const httpz = @import("httpz");

const std = @import("std");
