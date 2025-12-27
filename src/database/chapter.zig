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
        \\ hash TEXT NOT NULL,
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
        hash: []const u8,
        chapter: i32,
        volume: i32,
        total_pages: i64,
    ) !Response {
        if (try database.conn.row(SQL_STRING, .{ book_id, title, volume, chapter, total_pages, hash })) |row| {
            defer row.deinit();
            return .{
                .chapter_id = row.int(0),
            };
        }

        return error.ChapterCreationFailed;
    }
    const SQL_STRING =
        \\INSERT INTO chapters (book_id, title, volume, chapter, total_pages, hash) 
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        \\ON CONFLICT(book_id, title, volume,chapter) DO UPDATE SET title=excluded.title
        \\RETURNING id;
    ;
};

pub const CreateMany = struct {
    pub const Entry = struct {
        file_name: []const u8,
        hash: []const u8,
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
        for (entries, 0..) |entry, i| {
            if (try database.conn.row(SQL_STRING, .{
                book_id,
                entry.file_name,
                entry.volume,
                entry.chapter,
                entry.total_pages,
                entry.hash,
            })) |row| {
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

    const SQL_STRING =
        \\INSERT INTO chapters (book_id, title, volume, chapter, total_pages, hash) 
        \\VALUES (?1, ?2, ?3, ?4,?5, ?6)
        \\ON CONFLICT(book_id, title, volume,chapter) DO UPDATE SET title=excluded.title
        \\RETURNING id;
    ;
};

pub const GetAll = struct {
    pub const Response = struct {
        id: i64,
        book_id: i64,
        title: []const u8,
        volume: i64,
        chapter: i64,
        total_pages: i64,
        progress: i64,
        library_id: i64,
        hash: []const u8,

        pub fn deinit(self: Response, allocator: Allocator) void {
            allocator.free(self.title);
            allocator.free(self.hash);
        }
    };

    pub fn call(allocator: Allocator, database: Database) ![]Response {
        var rows = try database.conn.rows(SQL_STRING, .{});
        defer rows.deinit();
        var results: std.ArrayList(Response) = .empty;
        errdefer {
            for (results.items) |item| {
                allocator.free(item.title);
                allocator.free(item.hash);
            }
            results.deinit(allocator);
        }

        while (rows.next()) |row| {
            const title_copy = try allocator.dupe(u8, row.text(2));
            const hash_copy = try allocator.dupe(u8, row.text(7));

            try results.append(allocator, .{
                .id = row.int(0),
                .book_id = row.int(1),
                .title = title_copy,
                .volume = row.int(3),
                .chapter = row.int(4),
                .total_pages = row.int(5),
                .progress = row.int(6),
                .hash = hash_copy,
                .library_id = row.int(8),
            });
        }

        if (rows.err) |err| return err;

        return results.toOwnedSlice(allocator);
    }

    const SQL_STRING =
        \\ SELECT 
        \\ c.id,
        \\ c.book_id,
        \\ c.title,
        \\ c.volume,
        \\ c.chapter,
        \\ c.total_pages,
        \\ c.progress, 
        \\ c.hash,
        \\ b.library_id
        \\ FROM chapters c JOIN books b ON c.book_id = b.id;
    ;
};

pub const UpdateProgress = struct {
    pub fn call(database: Database, chapter_id: i64, progress: i64) !void {
        try database.conn.exec(SQL_STRING, .{ progress, chapter_id });
    }
    const SQL_STRING = "UPDATE chapters SET progress = ?1 WHERE id = ?2";
};

const Database = @import("../database.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
