pub inline fn init(database: Database) !void {
    try database.conn.exec(
        \\CREATE TABLE IF NOT EXISTS chapters (
        \\ id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\ book_id INTEGER NOT NULL,
        \\ title TEXT NOT NULL,
        \\ kind INTEGER NOT NULL,
        \\ number INTEGER,
        \\ is_read INTEGER DEFAULT 0,
        \\ FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
        \\ UNIQUE(book_id, title, kind)
        \\);
    , .{});
}

pub const Create = struct {
    const Response = struct {
        chapter_id: i64,
        number: i64,
    };

    pub fn call(
        database: Database,
        book_id: i64,
        title: []const u8,
        kind: ChapterType,
        number: i32,
    ) !Response {
        const sql =
            \\INSERT INTO chapters (book_id, title, kind, number) 
            \\VALUES (?1, ?2, ?3, ?4)
            \\ON CONFLICT(book_id, title) DO UPDATE SET title=excluded.title
            \\RETURNING id, is_read,number;
        ;

        const kind_integer: i32 = @intFromEnum(kind);

        if (try database.conn.row(sql, .{ book_id, title, kind_integer, number })) |row| {
            defer row.deinit();
            return .{
                .chapter_id = row.int(0),
                .number = row.int(3),
            };
        }

        return error.ChapterCreationFailed;
    }
};

pub const CreateMany = struct {
    pub const Entry = struct {
        file_name: []const u8,
        kind: ChapterType,
        number: i32,
    };

    const Response = struct {
        chapter_id: i64,
        number: i64,
    };
    pub fn call(
        allocator: Allocator,
        database: Database,
        book_id: i64,
        entries: []const Entry,
    ) ![]Response {
        var results = try allocator.alloc(Response, entries.len);
        errdefer allocator.free(results);

        try database.conn.exec("BEGIN TRANSACTION", .{});

        const sql =
            \\INSERT INTO chapters (book_id, title, kind, number) 
            \\VALUES (?1, ?2, ?3, ?4)
            \\ON CONFLICT(book_id, title, kind) DO UPDATE SET title=excluded.title
            \\RETURNING id, is_read, number;
        ;

        for (entries, 0..) |entry, i| {
            const kind_int: i32 = @intFromEnum(entry.kind);

            if (try database.conn.row(sql, .{ book_id, entry.file_name, kind_int, entry.number })) |row| {
                defer row.deinit();
                results[i] = .{
                    .chapter_id = row.int(0),
                    .number = row.int(2),
                };
            } else {
                try database.conn.exec("ROLLBACK", .{});
                return error.ChapterCreationFailed;
            }
        }

        try database.conn.exec("COMMIT", .{});

        return results;
    }
};

const ChapterType = @import("../types.zig").ChapterType;
const Database = @import("../database.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
