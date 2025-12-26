pub inline fn init(database: Database) !void {
    try database.conn.exec(
        \\CREATE TABLE IF NOT EXISTS libraries (
        \\ id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\ name TEXT NOT NULL UNIQUE
        \\);
    , .{});
}

pub const Create = struct {
    const Response = struct {
        library_id: i64,
    };

    pub fn call(database: Database, name: []const u8) !Response {
        const sql =
            \\INSERT INTO libraries (name) VALUES (?1)
            \\ON CONFLICT(name) DO UPDATE SET name=excluded.name
            \\RETURNING id;
        ;
        if (try database.conn.row(sql, .{name})) |row| {
            defer row.deinit();
            return .{ .library_id = row.int(0) };
        }
        return error.CouldntCreateLibrary;
    }
};

pub const GetAll = struct {
    pub const Response = struct {
        id: i64,
        name: []const u8,

        pub fn deinit(self: Response, allocator: Allocator) void {
            allocator.free(self.name);
        }
    };

    pub fn call(allocator: Allocator, database: Database) ![]Response {
        const sql = "SELECT id, name FROM libraries";

        var rows = try database.conn.rows(sql, .{});
        defer rows.deinit();

        var results: std.ArrayList(Response) = .empty;
        errdefer {
            for (results.items) |item| allocator.free(item.name);
            results.deinit(allocator);
        }

        while (rows.next()) |row| {
            const name_copy = try allocator.dupe(u8, row.text(1));

            try results.append(allocator, .{
                .id = row.int(0),
                .name = name_copy,
            });
        }

        if (rows.err) |err| return err;

        return results.toOwnedSlice(allocator);
    }
};

const Database = @import("../database.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
