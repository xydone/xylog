// INFO: Schema: https://github.com/anansi-project/comicinfo/blob/main/schema/v1.0/ComicInfo.xsd
Title: ?[]const u8 = null,
Series: ?[]const u8 = null,
Number: ?[]const u8 = null,
Count: i32 = -1,
Volume: i32 = -1,
AlternateSeries: ?[]const u8 = null,
AlternateNumber: ?[]const u8 = null,
AlternateCount: i32 = -1,
Summary: ?[]const u8 = null,
Notes: ?[]const u8 = null,
Year: i32 = -1,
Month: i32 = -1,
// Day: i32 = -1,
Writer: ?[]const u8 = null,
Penciller: ?[]const u8 = null,
Inker: ?[]const u8 = null,
Colorist: ?[]const u8 = null,
Letterer: ?[]const u8 = null,
CoverArtist: ?[]const u8 = null,
Editor: ?[]const u8 = null,
Publisher: ?[]const u8 = null,
Imprint: ?[]const u8 = null,
Genre: ?[]const u8 = null,
Web: ?[]const u8 = null,
PageCount: i32 = 0,
LanguageISO: ?[]const u8 = null,
Format: ?[]const u8 = null,
BlackAndWhite: YesNo = .Unknown,
Manga: YesNo = .Unknown,
Pages: ?[]ComicPageInfo = null,

pub fn deinit(self: @This(), allocator: Allocator) void {
    if (self.Title) |title| allocator.free(title);
    if (self.Series) |series| allocator.free(series);
    if (self.Number) |number| allocator.free(number);
    if (self.AlternateSeries) |alternateSeries| allocator.free(alternateSeries);
    if (self.AlternateNumber) |alternateNumber| allocator.free(alternateNumber);
    if (self.Summary) |summary| allocator.free(summary);
    if (self.Notes) |notes| allocator.free(notes);
    if (self.Writer) |writer| allocator.free(writer);
    if (self.Penciller) |penciller| allocator.free(penciller);
    if (self.Inker) |inker| allocator.free(inker);
    if (self.Colorist) |colorist| allocator.free(colorist);
    if (self.Letterer) |letterer| allocator.free(letterer);
    if (self.CoverArtist) |coverArtist| allocator.free(coverArtist);
    if (self.Editor) |editor| allocator.free(editor);
    if (self.Publisher) |publisher| allocator.free(publisher);
    if (self.Imprint) |imprint| allocator.free(imprint);
    if (self.Genre) |genre| allocator.free(genre);
    if (self.Web) |web| allocator.free(web);
    if (self.Format) |format| allocator.free(format);

    if (self.Pages) |pages| {
        defer allocator.free(pages);
        for (pages) |page| {
            page.deinit(allocator);
        }
    }
}

pub const YesNo = enum {
    Unknown,
    No,
    Yes,

    pub fn fromString(str: []const u8) YesNo {
        return std.meta.stringToEnum(YesNo, str) orelse .Unknown;
    }
};

pub const AgeRatingType = enum {
    unknown,
    adults_only_18_plus,
    early_childhood,
    everyone,
    everyone_10_plus,
    g,
    kids_to_adults,
    m,
    ma15_plus,
    mature_17_plus,
    pg,
    r18_plus,
    rating_pending,
    teen,
    x18_plus,
};

pub const ComicPageInfo = struct {
    Image: i32,
    Type: ComicPageType = .Story,
    DoublePage: bool = false,
    ImageSize: i64 = 0,
    Key: ?[]const u8 = null,
    ImageWidth: i32 = -1,
    ImageHeight: i32 = -1,

    pub fn deinit(self: ComicPageInfo, allocator: Allocator) void {
        if (self.Key) |key| allocator.free(key);
    }
};

pub const ComicPageType = enum {
    FrontCover,
    InnerCover,
    Roundup,
    Story,
    Advertisement,
    Editorial,
    Letters,
    Preview,
    BackCover,
    Other,
    Deleted,

    pub fn fromString(str: []const u8) ?ComicPageType {
        return std.meta.stringToEnum(ComicPageType, str);
    }
};

const Allocator = std.mem.Allocator;
const std = @import("std");
