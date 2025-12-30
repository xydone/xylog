const log = std.log.scoped(.trackers_api_keys_db);
pub inline fn init(database: Database) !void {
    try database.conn.exec(
        \\CREATE TABLE IF NOT EXISTS trackers_api_keys (
        \\ id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\ user_id INTEGER NOT NULL,
        \\ service_name TEXT NOT NULL, 
        \\ ciphertext BLOB NOT NULL,
        \\ nonce BLOB(12) NOT NULL,
        \\ tag BLOB(16) NOT NULL,
        \\ FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        \\ UNIQUE(user_id, service_name)
        \\);
    , .{});
}

pub const Create = struct {
    pub const Request = struct {
        user_id: i64,
        service_name: []const u8,
        plaintext_api_key: []const u8,
    };
    pub fn call(allocator: Allocator, database: Database, encryption_secret: [32]u8, request: Request) !void {
        const api_key = APIKey.encrypt(allocator, request.plaintext_api_key, encryption_secret) catch return error.CouldntEncryptSecret;

        database.conn.exec(SQL_STRING, .{
            request.user_id,
            request.service_name,
            api_key.ciphertext,
            &api_key.nonce,
            &api_key.tag,
        }) catch {
            log.err("Create failed! Error is {s}", .{database.conn.lastError()});
            return error.CreateFailed;
        };
    }

    const SQL_STRING =
        \\INSERT INTO trackers_api_keys (user_id, service_name, ciphertext, nonce, tag)
        \\VALUES (?,?,?,?,?)
        \\ON CONFLICT(user_id, service_name) DO UPDATE SET
        \\  ciphertext = excluded.ciphertext,
        \\  nonce = excluded.nonce,
        \\  tag = excluded.tag
    ;
};

pub const APIKey = struct {
    pub fn encrypt(
        allocator: Allocator,
        plaintext: []const u8,
        key: [32]u8,
    ) !struct { ciphertext: []u8, nonce: [Aes256Gcm.nonce_length]u8, tag: [Aes256Gcm.tag_length]u8 } {
        // generate random nonce
        var nonce: [Aes256Gcm.nonce_length]u8 = undefined;
        crypto.random.bytes(&nonce);

        const ciphertext = try allocator.alloc(u8, plaintext.len);

        var tag: [Aes256Gcm.tag_length]u8 = undefined;
        Aes256Gcm.encrypt(ciphertext, &tag, plaintext, "", nonce, key);

        return .{
            .ciphertext = ciphertext,
            .nonce = nonce,
            .tag = tag,
        };
    }
    pub fn decrypt(
        allocator: std.mem.Allocator,
        ciphertext: []const u8,
        nonce: [Aes256Gcm.nonce_length]u8,
        tag: [Aes256Gcm.tag_length]u8,
        key: [32]u8,
    ) ![]u8 {
        const plaintext = try allocator.alloc(u8, ciphertext.len);

        // if the tag or the key are wrong, this will error
        try Aes256Gcm.decrypt(plaintext, ciphertext, tag, "", nonce, key);

        return plaintext;
    }
};

const Database = @import("../database.zig");

const Aes256Gcm = std.crypto.aead.aes_gcm.Aes256Gcm;
const crypto = std.crypto;
const Allocator = std.mem.Allocator;
const std = @import("std");
