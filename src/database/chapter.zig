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
        \\ UNIQUE(book_id, title)
        \\);
    , .{});
}

pub const Create = struct {
    const Response = struct {
        chapter_id: i64,
        number: i64,
        is_read: bool,
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
                .is_read = row.int(1) == 1,
                .number = row.int(3),
            };
        }

        return error.ChapterCreationFailed;
    }
};

const ChapterType = @import("../types.zig").ChapterType;
const Database = @import("../database.zig");
