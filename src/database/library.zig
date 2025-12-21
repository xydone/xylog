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

const Database = @import("../database.zig");
