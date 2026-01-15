const log = std.log.scoped(.suwayomi_ingest);

// Suwayomi organises it's downloads the following way
// root -> mangas -> <source> -> <book> -> all chapters

pub fn scan(
    allocator: Allocator,
    database: Database,
    config: Config,
    suwayomi_dir: std.fs.Dir,
    library: *Library,
) !void {
    var mangas_dir = try suwayomi_dir.openDir("mangas", .{ .iterate = true });
    defer mangas_dir.close();

    const library_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{
        config.catalog_dir,
        config.ingest.default_library_to_use,
    });
    defer allocator.free(library_path);

    var library_dir = try std.fs.openDirAbsolute(library_path, .{ .iterate = true });
    defer library_dir.close();

    var it = mangas_dir.iterate();
    while (try it.next()) |entry| {
        // files are not expected here, we are only expecting the source folders
        if (entry.kind != .directory) continue;

        const directory_name = entry.name;
        var source_dir = try mangas_dir.openDir(directory_name, .{ .iterate = true });
        defer source_dir.close();

        var source_it = source_dir.iterate();
        while (try source_it.next()) |source_entry| {
            const book_name = source_entry.name;

            var book_dir = try source_dir.openDir(book_name, .{ .iterate = true });
            defer book_dir.close();

            const book_path = try book_dir.realpathAlloc(allocator, ".");
            defer allocator.free(book_path);

            library.importBook(
                allocator,
                config,
                database,
                book_path,
                book_name,
                config.ingest.operation_type,
            ) catch |err| {
                log.debug("importBook failed! {}", .{err});
                return error.ImportBookFailed;
            };
        }
    }
}

const Database = @import("../database.zig");
const Config = @import("../config/config.zig");
const Library = @import("../catalog/library.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
