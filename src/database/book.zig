pub inline fn init(database: Database) !void {
    try database.conn.exec(
        \\CREATE TABLE IF NOT EXISTS books (
        \\ id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\ library_id INTEGER NOT NULL,
        \\ title TEXT NOT NULL,
        \\ author TEXT,
        \\ FOREIGN KEY (library_id) REFERENCES libraries(id) ON DELETE CASCADE,
        \\ UNIQUE(library_id, title) 
        \\);
    , .{});
}

pub const Create = struct {
    pub const Response = struct {
        book_id: i64,
    };
    pub fn call(database: Database, name: []const u8, author: ?[]const u8, library_id: i64) !Response {
        const sql =
            \\INSERT INTO books (library_id, title, author) 
            \\VALUES (?1, ?2, ?3)
            \\ON CONFLICT(library_id, title) DO UPDATE SET title=excluded.title
            \\RETURNING id;
        ;

        if (try database.conn.row(sql, .{ library_id, name, author })) |row| {
            defer row.deinit();
            return .{
                .book_id = row.int(0),
            };
        }

        return error.InsertFailed;
    }
};

pub const GetAll = struct {
    pub const Response = struct {
        id: i64,
        library_id: i64,
        title: []const u8,
        author: []const u8,

        pub fn deinit(self: Response, allocator: Allocator) void {
            allocator.free(self.title);
            allocator.free(self.author);
        }
    };

    pub fn call(allocator: Allocator, database: Database) ![]Response {
        var rows = try database.conn.rows(SQL_STRING, .{});
        defer rows.deinit();

        var results: std.ArrayList(Response) = .empty;
        errdefer {
            for (results.items) |item| {
                allocator.free(item.title);
                allocator.free(item.author);
            }
            results.deinit(allocator);
        }

        while (rows.next()) |row| {
            const title_copy = try allocator.dupe(u8, row.text(2));
            const author_copy = try allocator.dupe(u8, row.text(3));

            try results.append(allocator, .{
                .id = row.int(0),
                .library_id = row.int(1),
                .title = title_copy,
                .author = author_copy,
            });
        }

        if (rows.err) |err| return err;

        return results.toOwnedSlice(allocator);
    }

    const SQL_STRING = "SELECT id, library_id, title, author FROM books";
};

pub const Delete = struct {
    pub fn call(database: Database, id: i64) !void {
        try database.conn.exec(SQL_STRING, .{id});
    }
    const SQL_STRING = "DELETE FROM books WHERE id = ?1";
};

const Database = @import("../database.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
