conn: zqlite.Conn,

const Database = @This();

pub fn init(allocator: Allocator, state_dir: []const u8) !Database {
    const path = std.fmt.allocPrintSentinel(allocator, "{s}/database.xyl", .{state_dir}, 0) catch @panic("OOM");
    defer allocator.free(path);

    const flags = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode;
    const conn = try zqlite.open(path, flags);

    try conn.exec("PRAGMA foreign_keys = ON;", .{});

    const database: Database = .{
        .conn = conn,
    };

    try Library.init(database);
    try Book.init(database);
    try Chapter.init(database);

    return database;
}

pub fn deinit(self: *Database) void {
    self.conn.close();
}

const Library = @import("database/library.zig");
const Book = @import("database/book.zig");
const Chapter = @import("database/chapter.zig");

const zqlite = @import("zqlite");

const Allocator = std.mem.Allocator;
const std = @import("std");
