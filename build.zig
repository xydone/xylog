const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const zqlite = b.dependency("zqlite", .{
        .target = target,
        .optimize = optimize,
    });
    module.addImport("zqlite", zqlite.module("zqlite"));

    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });
    module.addImport("httpz", httpz.module("httpz"));

    const zdt = b.dependency("zdt", .{
        .target = target,
        .optimize = optimize,
    });
    module.addImport("zdt", zdt.module("zdt"));

    const dishwasher = b.dependency("dishwasher", .{
        .target = target,
        .optimize = optimize,
    });
    module.addImport("xml", dishwasher.module("dishwasher"));

    const curl = b.dependency("curl", .{
        .target = target,
        .optimize = optimize,
        .nghttp2 = false,
        .libpsl = false,
        .libssh2 = false,
        .libidn2 = false,
        .@"disable-ldap" = true,
        .@"use-mbedtls" = true,
    });
    const libCurl = @import("curl").artifact(curl, .lib);

    module.linkLibrary(libCurl);

    const exe = b.addExecutable(.{
        .name = "xylog",
        .root_module = module,
    });
    // sqlite
    module.addCSourceFile(.{
        .file = b.path("lib/sqlite/sqlite3.c"),
        .flags = &[_][]const u8{
            "-DSQLITE_DQS=0",
            "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
            "-DSQLITE_USE_ALLOCA=1",
            "-DSQLITE_THREADSAFE=1",
            "-DSQLITE_TEMP_STORE=3",
            "-DSQLITE_ENABLE_API_ARMOR=1",
            "-DSQLITE_ENABLE_UNLOCK_NOTIFY",
            "-DSQLITE_DEFAULT_FILE_PERMISSIONS=0600",
            "-DSQLITE_OMIT_DECLTYPE=1",
            "-DSQLITE_OMIT_DEPRECATED=1",
            "-DSQLITE_OMIT_LOAD_EXTENSION=1",
            "-DSQLITE_OMIT_PROGRESS_CALLBACK=1",
            "-DSQLITE_OMIT_SHARED_CACHE",
            "-DSQLITE_OMIT_TRACE=1",
            "-DSQLITE_OMIT_UTF16=1",
            "-DHAVE_USLEEP=0",
        },
    });
    // module.linkSystemLibrary("zip", .{});
    const bzip_dependency = b.dependency("libzip", .{
        .target = target,
        .optimize = optimize,
    });
    module.linkLibrary(bzip_dependency.artifact("zip"));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const exe_check = b.addExecutable(.{
        .name = "xylog",
        .root_module = module,
    });
    const check = b.step("check", "Check if xylog compiles");
    check.dependOn(&exe_check.step);
    check.dependOn(&exe_tests.step);

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
