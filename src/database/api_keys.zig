const log = std.log.scoped(.api_keys_db);
pub inline fn init(database: Database) !void {
    try database.conn.exec(
        \\CREATE TABLE IF NOT EXISTS api_keys (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  user_id INTEGER NOT NULL,
        \\  public_id TEXT NOT NULL UNIQUE,
        \\  secret_hash BLOB NOT NULL,
        \\  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
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
        full_key: []u8,

        pub fn deinit(self: Response, allocator: Allocator) void {
            allocator.free(self.full_key);
        }
    };

    pub fn call(database: Database, allocator: Allocator, request: Request) !Response {
        // 1. Fetch the user's ID and Password Hash from the database
        const user_row = try database.conn.row(
            "SELECT id, password FROM users WHERE username = ? LIMIT 1",
            .{request.username},
        ) orelse return error.UserNotFound;
        defer user_row.deinit();

        const user_id = user_row.int(0);
        const stored_hash = user_row.get([]const u8, 1);

        const is_valid = try verifyPassword(allocator, stored_hash, request.password);
        if (!is_valid) {
            log.warn("Failed API key creation attempt for user: {s} (Invalid Password)", .{request.username});
            return error.AuthenticationFailed;
        }

        const key_result = try createAPIKey(allocator);
        defer key_result.deinit(allocator);

        const row = database.conn.row(SQL_STRING, .{
            user_id,
            key_result.public_id,
            key_result.secret_hash,
        }) catch {
            log.err("Create API Key DB insertion failed! Error: {s}", .{database.conn.lastError()});
            return error.CreateFailed;
        } orelse return error.CreateFailed;
        defer row.deinit();

        const response_key = try allocator.dupe(u8, key_result.full_key);

        return .{
            .id = row.int(0),
            .full_key = response_key,
        };
    }

    const SQL_STRING =
        \\INSERT INTO api_keys (user_id, public_id, secret_hash)
        \\VALUES (?, ?, ?)
        \\RETURNING id;
    ;
};

const createAPIKey = @import("../auth/util.zig").createAPIKey;
const verifyPassword = @import("../auth/util.zig").verifyPassword;

const Database = @import("../database.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
