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
    pub fn call(database: Database, name: []const u8, library_id: i64) !Response {
        const sql =
            \\INSERT INTO books (library_id, title, author) 
            \\VALUES (?1, ?2, ?3)
            \\ON CONFLICT(library_id, title) DO UPDATE SET title=excluded.title
            \\RETURNING id;
        ;
        if (try database.conn.row(sql, .{ library_id, name, "Unknown" })) |row| {
            defer row.deinit();
            return .{
                .book_id = row.int(0),
            };
        }

        return error.InsertFailed;
    }
};
const Database = @import("../database.zig");
