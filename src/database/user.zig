const log = std.log.scoped(.user_db);
pub inline fn init(database: Database) !void {
    try database.conn.exec(
        \\CREATE TABLE IF NOT EXISTS users (
        \\ id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\ username TEXT NOT NULL,
        \\ password TEXT NOT NULL
        \\);
    , .{});
}

pub const Create = struct {
    pub const Request = struct {
        username: []const u8,
        password: []const u8,
    };
    pub const Response = struct {
        id: i64,
    };
    pub fn call(allocator: Allocator, database: Database, request: Request) !Response {
        const hashed_password = hashPassword(allocator, request.password) catch return error.HashingError;
        defer allocator.free(hashed_password);

        const row = database.conn.row(SQL_STRING, .{
            request.username,
            hashed_password,
        }) catch {
            log.err("Create failed! Error is {s}", .{database.conn.lastError()});
            return error.CreateFailed;
        } orelse return error.CreateFailed;

        defer row.deinit();

        return .{
            .id = row.int(0),
        };
    }

    const SQL_STRING =
        \\INSERT INTO users (username, password)
        \\VALUES (?,?)
        \\RETURNING id;
    ;
};

pub const GetByAPIKey = struct {
    pub const Response = struct {
        id: i64,
        username: []const u8,
        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            allocator.free(self.username);
        }
    };

    pub fn call(allocator: std.mem.Allocator, database: Database, full_key: []const u8) !Response {
        if (!std.mem.startsWith(u8, full_key, "xylog_")) return error.InvalidAPIKeyFormat;

        // skip the prefix
        var it = std.mem.splitScalar(u8, full_key[6..], '_');

        const public_id = it.next() orelse return error.InvalidAPIKeyFormat;
        const secret = it.next() orelse return error.InvalidAPIKeyFormat;

        const row = database.conn.row(SQL_STRING, .{public_id}) catch {
            log.err("GetByAPIKey failed! Error is {s}", .{database.conn.lastError()});
            return error.DatabaseError;
        } orelse return error.DatabaseError;
        defer row.deinit();

        const user_id = row.int(0);
        const username_raw = row.get([]const u8, 1);

        const hash = row.get([]const u8, 2);
        std.debug.assert(hash.len == 32);

        if (!verifyAPIKey(hash[0..32].*, secret)) {
            log.warn("Invalid API key secret provided for public_id: {s}", .{public_id});
            return error.AuthenticationFailed;
        }

        return Response{
            .id = user_id,
            .username = try allocator.dupe(u8, username_raw),
        };
    }

    const SQL_STRING =
        \\SELECT u.id, u.username, ak.secret_hash 
        \\FROM users u 
        \\JOIN api_keys ak ON u.id = ak.user_id 
        \\WHERE ak.public_id = ? LIMIT 1;
    ;
};

const verifyAPIKey = @import("../auth/util.zig").verifyAPIKey;
const hashPassword = @import("../auth/util.zig").hashPassword;

const Database = @import("../database.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
