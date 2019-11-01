const std = @import("std");
usingnamespace @import("argparse.zig");

const MyArgs = struct {
    foo: ?bool,

    age: u32,
    weight: ?u32,
    height: f32,
    depth: f32,

    name: []const u8 = "evan",
};

pub fn main() anyerror!void {
    const parsed = parseArgs(MyArgs) catch {
        std.debug.warn("\nCould not parse args!!!\n");
        return;
    };

    std.debug.warn("\n-------------\n");
    std.debug.warn("{}\n", parsed);
}
