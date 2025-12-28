pub inline fn init(router: *Handler.Router) void {
    GetCatalog.init(router);
    GetBook.init(router);
    GetChapter.init(router);
    GetSearchTerms.init(router);
    GetMultiDownloadFeed.init(router);
    GetMultiDownload.init(router);
}

const GetCatalog = Endpoint(struct {
    const Params = struct { library: []const u8 };

    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = void,
        .method = .GET,
        .path = "/opds/v1.2/:library",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const is_catalog_request = std.mem.eql(u8, req.params.library, "catalog");

        const writer = res.writer();
        res.header("Content-Type", "application/xml");

        var date_writer = std.Io.Writer.Allocating.init(allocator);
        defer date_writer.deinit();
        try ctx.catalog.update_time.toString("%T", &date_writer.writer);

        var links = std.ArrayList(Link).empty;
        defer links.deinit(allocator);

        const opds_address = try std.fmt.allocPrint(
            allocator,
            "http://{s}:{d}/opds/v1.2",
            .{ ctx.config.address, ctx.config.port },
        );
        defer allocator.free(opds_address);

        const start_address = try std.fmt.allocPrint(allocator, "{s}/catalog", .{opds_address});
        defer allocator.free(start_address);

        const self_address = try std.fmt.allocPrint(allocator, "{s}/{s}", .{
            opds_address,
            req.params.library,
        });
        defer allocator.free(self_address);

        var root_links = [_]Link{
            .{
                .type = "application/atom+xml;profile=opds-catalog;kind=navigation",
                .rel = "self",
                .href = self_address,
            },
            .{
                .type = "application/atom+xml;profile=opds-catalog;kind=navigation",
                .rel = "start",
                .href = start_address,
            },
        };

        try links.appendSlice(allocator, &root_links);

        var entries = std.ArrayList(Catalog.Entry).empty;
        defer entries.deinit(allocator);

        const catalog: Catalog = blk: {
            var library_it = ctx.catalog.libraries.iterator();
            if (is_catalog_request) {
                while (library_it.next()) |entry| {
                    const library_name = entry.key_ptr.*;
                    // WARNING: this leaks in a non arena allocator!
                    const library_address = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ opds_address, library_name });

                    try entries.append(
                        allocator,
                        .{
                            .title = library_name,
                            .updated = date_writer.written(),
                            .id = library_name,
                            .content = library_name,
                            .link = .{
                                .type = "application/atom+xml;profile=opds-catalog;kind=navigation",
                                .rel = "subsection",
                                .href = library_address,
                            },
                        },
                    );
                }
            } else {
                const library = ctx.catalog.libraries.get(req.params.library) orelse {
                    handleResponse(res, .not_found, "Library not found!");
                    return;
                };
                // handle cases in which the catalog is not requested as cases in which the library itself is requested.
                var book_it = library.books.valueIterator();
                while (book_it.next()) |book| {
                    // WARNING: this leaks in a non arena allocator!
                    const book_address = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{
                        opds_address,
                        req.params.library,
                        book.*.name,
                    });

                    try entries.append(
                        allocator,
                        .{
                            .title = book.*.name,
                            .updated = date_writer.written(),
                            .id = book.*.name,
                            .content = "",
                            .link = .{
                                .rel = "subsection",
                                .href = book_address,
                                .type = "application/atom+xml;profile=opds-catalog;kind=navigation",
                            },
                        },
                    );
                }
            }

            break :blk .{
                .feed = .{
                    .id = "root",
                    .title = "Xylog OPDS catalog",
                    .updated = date_writer.written(),
                    .author = .{},
                    .links = try links.toOwnedSlice(allocator),
                    .entries = try entries.toOwnedSlice(allocator),
                },
            };
        };
        try catalog.writeXML(writer);
    }
});

const GetBook = Endpoint(struct {
    const Params = struct {
        library: []const u8,
        book: []const u8,
    };

    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = void,
        .method = .GET,
        .path = "/opds/v1.2/:library/:book",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;

        const writer = res.writer();
        res.header("Content-Type", "application/xml");

        var date_writer = std.Io.Writer.Allocating.init(allocator);
        defer date_writer.deinit();
        try ctx.catalog.update_time.toString("%T", &date_writer.writer);

        var links = std.ArrayList(Link).empty;
        defer links.deinit(allocator);

        const opds_address = try std.fmt.allocPrint(
            allocator,
            "http://{s}:{d}/opds/v1.2",
            .{ ctx.config.address, ctx.config.port },
        );
        defer allocator.free(opds_address);

        const start_address = try std.fmt.allocPrint(allocator, "{s}/catalog", .{opds_address});
        defer allocator.free(start_address);

        const self_address = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{
            opds_address,
            req.params.library,
            req.params.book,
        });
        defer allocator.free(self_address);

        const download_multiple_address = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}/search", .{
            opds_address,
            req.params.library,
            req.params.book,
        });
        defer allocator.free(download_multiple_address);

        var root_links = [_]Link{
            .{
                .type = "application/atom+xml;profile=opds-catalog;kind=navigation",
                .rel = "self",
                .href = self_address,
            },
            .{
                .type = "application/atom+xml;profile=opds-catalog;kind=navigation",
                .rel = "start",
                .href = start_address,
            },
            .{
                .type = "application/opensearchdescription+xml",
                .rel = "search",
                .href = download_multiple_address,
            },
        };

        try links.appendSlice(allocator, &root_links);

        var entries = std.ArrayList(Catalog.Entry).empty;
        defer entries.deinit(allocator);

        const catalog: Catalog = blk: {
            const library = ctx.catalog.libraries.get(req.params.library) orelse {
                handleResponse(res, .not_found, "Library not found!");
                return;
            };
            const book = library.books.get(req.params.book) orelse {
                handleResponse(res, .not_found, "Library not found!");
                return;
            };
            var chapter_it = book.chapters.valueIterator();
            while (chapter_it.next()) |chapter| {
                const encoded_chapter_name = std.Uri.Component{ .raw = chapter.*.name };
                // WARNING: this leaks in a non arena allocator!
                const book_address = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}/{f}", .{
                    opds_address,
                    req.params.library,
                    req.params.book,
                    std.fmt.alt(encoded_chapter_name, .formatEscaped),
                });
                try entries.append(allocator, .{
                    .title = chapter.*.name,
                    .id = chapter.*.name,
                    .updated = date_writer.written(),
                    .content = "",
                    .link = .{
                        .href = book_address,
                        .rel = "http://opds-spec.org/acquisition",
                        .type = "application/zip",
                    },
                });
            }
            break :blk .{
                .feed = .{
                    .id = req.params.book,
                    .title = req.params.book,
                    .updated = date_writer.written(),
                    .author = .{},
                    .links = try links.toOwnedSlice(allocator),
                    .entries = try entries.toOwnedSlice(allocator),
                },
            };
        };
        try catalog.writeXML(writer);
    }
});

const GetChapter = Endpoint(struct {
    const Params = struct {
        library: []const u8,
        book: []const u8,
        chapter: []const u8,
    };

    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = void,
        .method = .GET,
        .path = "/opds/v1.2/:library/:book/:chapter",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;

        const duped_chapter = try allocator.dupe(u8, req.params.chapter);
        defer allocator.free(duped_chapter);

        const decoded_name = std.Uri.percentDecodeInPlace(duped_chapter);

        const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}/{s}", .{
            ctx.config.catalog_dir,
            req.params.library,
            req.params.book,
            decoded_name,
        });
        defer allocator.free(file_path);

        const file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();

        // hardcoded 20mb
        // NOTE: this is not freed on purpose. the arena will clean it up but freeing it manually will send garbage to the client.
        const file_contents = try file.readToEndAlloc(allocator, 1024 * 1024 * 20);

        res.status = 200;
        res.header("Content-Type", "application/zip");

        // NOTE: this is not freed on purpose. the arena will clean it up but freeing it manually will send garbage to the client.
        const header_value = try std.fmt.allocPrint(
            allocator,
            "attachment; filename=\"{s}\"; filename*=UTF-8''{s}",
            .{ decoded_name, duped_chapter },
        );

        res.header("Content-Disposition", header_value);
        res.body = file_contents;
    }
});

const GetSearchTerms = Endpoint(struct {
    pub const Params = struct {
        library: []const u8,
        book: []const u8,
    };
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = void,
        .method = .GET,
        .path = "/opds/v1.2/:library/:book/search",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const template_url = try std.fmt.allocPrint(
            allocator,
            "http://{s}:{d}/opds/v1.2/{s}/{s}/multidownload?download={{searchTerms}}",
            .{
                ctx.config.address, ctx.config.port,
                req.params.library, req.params.book,
            },
        );
        defer allocator.free(template_url);

        const response: OpenSearchDescription = .{
            .short_name = "Download multiple",
            .description = "Download multiple chapters at once",
            .input_encoding = "UTF-8",
            .output_encoding = "UTF-8",
            .url = .{
                .template = template_url,
            },
        };
        try response.writeXML(res.writer());
        res.status = 200;
    }
});

const GetMultiDownloadFeed = Endpoint(struct {
    const Params = struct {
        library: []const u8,
        book: []const u8,
    };
    const Query = struct {
        /// this must be a range formatted like
        /// <start>-<end>
        download: []const u8,
    };
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Query = Query,
            .Params = Params,
        },
        .Response = void,
        .method = .GET,
        .path = "/opds/v1.2/:library/:book/multidownload",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(void, Params, Query), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        var download_it = std.mem.tokenizeSequence(u8, req.query.download, "-");

        const start = blk: {
            const slice = download_it.next() orelse {
                handleResponse(res, .bad_request, "Start is missing from the download query.");
                return;
            };
            break :blk std.fmt.parseInt(i64, slice, 10) catch {
                handleResponse(res, .bad_request, "Start is not a valid integer.");
                return;
            };
        };

        const end = blk: {
            const slice = download_it.next() orelse {
                handleResponse(res, .bad_request, "End is missing from the download query.");
                return;
            };
            break :blk std.fmt.parseInt(i64, slice, 10) catch {
                handleResponse(res, .bad_request, "End is not a valid integer.");
                return;
            };
        };
        var date_writer = std.Io.Writer.Allocating.init(allocator);
        defer date_writer.deinit();
        try ctx.catalog.update_time.toString("%T", &date_writer.writer);

        var entries = std.ArrayList(Catalog.Entry).empty;
        defer entries.deinit(allocator);

        const download_address = try std.fmt.allocPrint(
            allocator,
            "http://{s}:{d}/opds/v1.2/{s}/{s}/{d}/{d}/download",
            .{ ctx.config.address, ctx.config.port, req.params.library, req.params.book, start, end },
        );
        defer allocator.free(download_address);

        const title = try std.fmt.allocPrint(allocator, "{s} - Chapters {} -> {}", .{ req.params.book, start, end });
        defer allocator.free(title);

        try entries.append(allocator, .{
            .id = title,
            .title = title,
            .updated = date_writer.written(),
            .content = "",
            .link = .{
                .rel = "http://opds-spec.org/acquisition",
                .type = "application/zip",
                .href = download_address,
            },
        });

        const response: Catalog = .{
            .feed = .{
                .id = title,
                .title = title,
                .updated = date_writer.written(),
                .author = .{},
                .links = &.{},
                .entries = entries.items,
            },
        };

        try response.writeXML(res.writer());
        res.status = 200;
    }
});

const GetMultiDownload = Endpoint(struct {
    const Params = struct {
        library: []const u8,
        book: []const u8,
        start: u64,
        end: u64,
    };

    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = void,
        .method = .GET,
        .path = "/opds/v1.2/:library/:book/:start/:end/download",
    };

    pub fn call(ctx: *Handler.RequestContext, req: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;

        const start = req.params.start;
        const end = req.params.end;

        const library = ctx.catalog.libraries.get(req.params.library) orelse {
            handleResponse(res, .not_found, "Library not found!");
            return;
        };

        const book = library.books.get(req.params.book) orelse {
            handleResponse(res, .not_found, "Book not found!");
            return;
        };

        var chapter_it = book.chapters.valueIterator();

        var chapter_list = try std.ArrayList(*Chapter).initCapacity(allocator, @intCast((end - start) + 1));
        defer chapter_list.deinit(allocator);

        while (chapter_it.next()) |chapter| {
            if (start <= chapter.*.chapter and chapter.*.chapter <= end) {
                chapter_list.appendAssumeCapacity(chapter.*);
            }
        }

        std.mem.sort(*Chapter, chapter_list.items, {}, struct {
            fn lessThan(_: void, a: *Chapter, b: *Chapter) bool {
                if (a.volume != b.volume) return a.volume < b.volume;
                return a.chapter < b.chapter;
            }
        }.lessThan);

        const dir_path = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{
            ctx.config.catalog_dir,
            req.params.library,
            req.params.book,
        });
        defer allocator.free(dir_path);

        // archive all chapters into a zip
        var error_ptr: zip.zip_error_t = undefined;
        zip.zip_error_init(&error_ptr);
        defer zip.zip_error_fini(&error_ptr);

        // store the zip in memory
        const archive_source = zip.zip_source_buffer_create(null, 0, 0, &error_ptr) orelse {
            handleResponse(res, .internal_server_error, "Failed to create memory source");
            return;
        };
        zip.zip_source_keep(archive_source);
        defer zip.zip_source_free(archive_source);

        // open the source as an archive
        const za = zip.zip_open_from_source(archive_source, zip.ZIP_CREATE | zip.ZIP_TRUNCATE, &error_ptr) orelse {
            handleResponse(res, .internal_server_error, "Failed to open archive from source");
            return;
        };

        for (chapter_list.items, 0..) |chapter, i| {
            const entry_name_z = try allocator.dupeZ(u8, chapter.name);
            defer allocator.free(entry_name_z);

            const full_path = try std.fs.path.joinZ(allocator, &.{ dir_path, chapter.name });
            defer allocator.free(full_path);

            const file_source = zip.zip_source_file(za, full_path.ptr, 0, 0) orelse continue;

            if (zip.zip_file_add(za, entry_name_z, file_source, zip.ZIP_FL_OVERWRITE) < 0) {
                zip.zip_source_free(file_source);
                continue;
            }
            // do not compress. compressing leads to timeouts
            _ = zip.zip_set_file_compression(za, @intCast(i), zip.ZIP_CM_STORE, 0);
        }
        if (zip.zip_close(za) < 0) {
            const err = zip.zip_get_error(za);
            std.debug.print("Zip close error: {s}\n", .{zip.zip_error_strerror(err)});
            handleResponse(res, .internal_server_error, "Failed to finalize zip archive");
            return;
        }

        if (zip.zip_source_open(archive_source) < 0) {
            const err = zip.zip_source_error(archive_source);
            std.debug.print("Source open error: {s}\n", .{zip.zip_error_strerror(err)});
            handleResponse(res, .internal_server_error, "Failed to read memory source");
            return;
        }
        defer _ = zip.zip_source_close(archive_source);

        var stat: zip.zip_stat_t = undefined;
        _ = zip.zip_source_stat(archive_source, &stat);
        const zip_size: usize = @intCast(stat.size);

        const result = try allocator.alloc(u8, zip_size);
        // make sure the buffer is not empty
        const read_bytes = zip.zip_source_read(archive_source, result.ptr, zip_size);

        if (read_bytes < 0) {
            handleResponse(res, .internal_server_error, "Failed to extract bytes from memory source");
            return;
        }

        res.status = 200;

        const file_name = try std.fmt.allocPrint(allocator, "{s} - Chapters {} -> {}", .{ book.name, start, end });
        defer allocator.free(file_name);

        // NOTE: this is not freed on purpose. the arena will clean it up but freeing it manually will send garbage to the client.
        const header_value = try std.fmt.allocPrint(
            allocator,
            "attachment; filename=\"{s}\"; filename*=UTF-8''{s}",
            .{ book.name, file_name },
        );

        res.header("Content-Disposition", header_value);
        res.body = result;
    }
});

const Chapter = @import("../../../catalog/chapter.zig");

const OpenSearchDescription = @import("../types.zig").OpenSearchDescription;
const Link = @import("../types.zig").Link;
const Catalog = @import("../catalog.zig");

const Endpoint = @import("../../../endpoint.zig").Endpoint;
const EndpointRequest = @import("../../../endpoint.zig").EndpointRequest;
const EndpointData = @import("../../../endpoint.zig").EndpointData;
const handleResponse = @import("../../../endpoint.zig").handleResponse;

const Handler = @import("../../../handler.zig");

const zip = @cImport({
    @cInclude("zip.h");
});
const zdt = @import("zdt");
const httpz = @import("httpz");

const std = @import("std");
