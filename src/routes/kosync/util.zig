/// Caller is responsible for formatting into the respective required hex format.
pub fn partialMd5(file: std.fs.File) ![16]u8 {
    var hasher = Md5.init(.{});
    const size: usize = 1024;
    var buffer: [size]u8 = undefined;

    var i: i8 = -1;
    while (i <= 10) : (i += 1) {
        // INFO: LuaJIT bit.lshift()
        const offset: u64 = if (i == -1)
            0
        else
            @as(u64, 1) << @intCast(10 + (2 * i));

        file.seekTo(offset) catch break;

        const bytes_read = try file.read(&buffer);

        if (bytes_read > 0) {
            hasher.update(buffer[0..bytes_read]);
        } else {
            break;
        }
    }

    var digest: [16]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

const Md5 = std.crypto.hash.Md5;
const std = @import("std");
