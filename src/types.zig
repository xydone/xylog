pub const ChapterType = enum { chapter, volume };

pub const ScanOptions = struct {
    /// a deep scan will call for a scan on the nested structure too
    /// a shallow only checks for the one relevant to the caller function
    type: enum { deep, shallow },
};
