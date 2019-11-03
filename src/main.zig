const std = @import("std");
usingnamespace @import("argparse.zig");

const MyArgs = struct {
    foo: ?bool,

    weight: ?u32,
    height: f32,

    depth: f32,
    const depth__SHORT = "d";
    const depth__DEFAULT = "100";
    const depth__DOC = "Depth of the thing, in meters.";

    /// Age of the user in years.
    age: u32 = 100,
    // a: Alias("age"),

    name: []const u8 = "evan",

    values: []u32, // --values 1 2 3
};

pub fn main() anyerror!void {
    const parsed = parseArgs(MyArgs) catch {
        std.debug.warn("\nCould not parse args!!!\n");
        return;
    };

    std.debug.warn("\n-------------\n");
    std.debug.warn("{}\n", parsed);
}
