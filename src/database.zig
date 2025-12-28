conn: zqlite.Conn,
/// is this initialization when the database file was created
is_first_time_initializing: bool,

const Database = @This();
const log = std.log.scoped(.database);

pub fn init(allocator: Allocator, state_dir: []const u8) !Database {
    const path = std.fmt.allocPrintSentinel(allocator, "{s}/database.xyl", .{state_dir}, 0) catch @panic("OOM");
    defer allocator.free(path);

    var is_first_time_initializing = false;

    const flags = zqlite.OpenFlags.EXResCode;
    const conn = zqlite.open(path, flags) catch |err| blk: {
        switch (err) {
            // assume that if the database cannot be opened, that it does not exist and retry
            error.CantOpen => {
                log.debug("First time initializing database, creating database.xyl", .{});
                is_first_time_initializing = true;
                break :blk try zqlite.open(path, zqlite.OpenFlags.Create | flags);
            },
            else => return err,
        }
    };

    try conn.exec("PRAGMA foreign_keys = ON;", .{});

    const database: Database = .{
        .conn = conn,
        .is_first_time_initializing = is_first_time_initializing,
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
