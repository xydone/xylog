pub const Link = struct {
    // https://datatracker.ietf.org/doc/html/rfc4287#section-4.2.7
    rel: []const u8,
    type: []const u8,
    href: []const u8,
};
