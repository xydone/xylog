pub inline fn init(database: Database) !void {
    try database.conn.exec(
        \\CREATE TABLE IF NOT EXISTS chapters (
        \\ id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\ book_id INTEGER NOT NULL,
        \\ title TEXT NOT NULL,
        \\ volume INTEGER NOT NULL,
        \\ chapter INTEGER NOT NULL,
        \\ total_pages INTEGER NOT NULL,
        \\ progress INTEGER NOT NULL DEFAULT 0,
        \\ FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE,
        \\ UNIQUE(book_id, title, volume, chapter)
        \\);
    , .{});
}

pub const Create = struct {
    const Response = struct {
        chapter_id: i64,
    };

    pub fn call(
        database: Database,
        book_id: i64,
        title: []const u8,
        chapter: i32,
        volume: i32,
        total_pages: i64,
    ) !Response {
        const sql =
            \\INSERT INTO chapters (book_id, title, volume, chapter, total_pages) 
            \\VALUES (?1, ?2, ?3, ?4, ?5)
            \\ON CONFLICT(book_id, title) DO UPDATE SET title=excluded.title
            \\RETURNING id;
        ;

        if (try database.conn.row(sql, .{ book_id, title, volume, chapter, total_pages })) |row| {
            defer row.deinit();
            return .{
                .chapter_id = row.int(0),
            };
        }

        return error.ChapterCreationFailed;
    }
};

pub const CreateMany = struct {
    pub const Entry = struct {
        file_name: []const u8,
        volume: i64,
        chapter: i64,
        total_pages: i64,
    };

    const Response = struct {
        chapter_id: i64,
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
            \\INSERT INTO chapters (book_id, title, volume, chapter, total_pages) 
            \\VALUES (?1, ?2, ?3, ?4,?5)
            \\ON CONFLICT(book_id, title, volume,chapter) DO UPDATE SET title=excluded.title
            \\RETURNING id;
        ;

        for (entries, 0..) |entry, i| {
            if (try database.conn.row(sql, .{ book_id, entry.file_name, entry.volume, entry.chapter, entry.total_pages })) |row| {
                defer row.deinit();
                results[i] = .{
                    .chapter_id = row.int(0),
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

const Database = @import("../database.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
