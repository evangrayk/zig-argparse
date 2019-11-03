const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;

pub fn startsWith(s: []const u8, prefix: []const u8) bool {
    return s.len >= prefix.len and (mem.eql(u8, s[0..prefix.len], prefix));
}

test "startsWith" {
    std.debug.assert(startsWith("hello", "he"));
    std.debug.assert(startsWith("hello", "hello"));
    std.debug.assert(!startsWith("hello", "nope"));
    std.debug.assert(startsWith("hello", ""));
    std.debug.assert(!startsWith("", "hi"));
    std.debug.assert(!startsWith("h", "hi"));
    std.debug.assert(!startsWith("ho", "hi"));
}

/// ("key=value", '=')  -> {"key", "value"}
pub fn splitAtFirst(s: []const u8, sep: u8) ?[2][]const u8 {
    for (s) |c, i| {
        if (c == sep) {
            return [2][]const u8{ s[0..i], s[i + 1 ..] };
        }
    }
    return null;
}

test "splitAtFirst" {
    {
        const vals = splitAtFirst("key=value", '=');
        std.debug.assert(vals != null);
        std.testing.expectEqualSlices(u8, vals.?[0], "key");
        std.testing.expectEqualSlices(u8, vals.?[1], "value");
    }

    {
        const vals = splitAtFirst("=value", '=');
        std.debug.assert(vals != null);
        std.testing.expectEqualSlices(u8, vals.?[0], "");
        std.testing.expectEqualSlices(u8, vals.?[1], "value");
    }
    {
        const vals = splitAtFirst("key=", '=');
        std.debug.assert(vals != null);
        std.testing.expectEqualSlices(u8, vals.?[0], "key");
        std.testing.expectEqualSlices(u8, vals.?[1], "");
    }
}

pub fn isArray(comptime T: type) ?builtin.TypeInfo.Array {
    const info = @typeInfo(T);
    return switch (info) {
        .Array => info.Array,
        else => null,
    };
}

pub fn NonOptional(comptime T: type) type {
    comptime var info = @typeInfo(T);
    return switch (info) {
        .Optional => info.Optional.child,
        else => T,
    };
}

pub fn isOptional(comptime T: type) bool {
    comptime var info = @typeInfo(T);
    return switch (info) {
        .Optional => true,
        else => false,
    };
}
