const std = @import("std");
const builtin = @import("builtin");
usingnamespace @import("argparse.zig");
usingnamespace std.testing;

/// function that replaces std.debug.warn when testing
pub fn logInsideTest(comptime fmt: []const u8, args: ...) void {
    const allocator = std.heap.c_allocator;
    var size: usize = 0;
    std.fmt.format(&size, error{}, countSize, fmt, args) catch |err| switch (err) {};
    const buf = allocator.alloc(u8, size) catch return;
    const printed = std.fmt.bufPrint(buf, fmt, args) catch |err| switch (err) {
        error.BufferTooSmall => unreachable, // we just counted the size above
    };

    std.debug.warn("\x1B[32m{}\x1B[0m", printed);
}

fn countSize(size: *usize, bytes: []const u8) (error{}!void) {
    size.* += bytes.len;
}

/////////////////////////////////////////////////////////////

test "argparse.optionals" {
    const result = try parseArgsList(struct {
        foo: ?u32,
    }, [_][]const u8{"./a"});
    expectEqual(result.foo, null);
}
test "argparse.specifyOptional" {
    const result = try parseArgsList(struct {
        foo: ?u32,
    }, [_][]const u8{ "./a", "--foo", "42" });
    std.debug.warn("{}\n", result);
    expectEqual(result.foo, 42);
}

test "argparse.missingRequired" {
    expectError(error.MissingRequiredArgument, parseArgsList(struct {
        required: u32,
    }, [_][]const u8{"./a"}));
}

test "argparse.string" {
    const result = try parseArgsList(struct {
        str: []const u8,
    }, [_][]const u8{ "./a", "--str", "Hello" });
    expectEqualSlices(u8, result.str, "Hello");
}

test "argparse.boolGiven" {
    const result = try parseArgsList(struct {
        foo: ?bool,
    }, [_][]const u8{ "./a", "--foo" });
    expectEqual(result.foo, true);
}

test "argparse.boolDefault" {
    const result = try parseArgsList(struct {
        foo: ?bool,
    }, [_][]const u8{"./a"});
    expectEqual(result.foo, false);
}

test "argparse.uintMin" {
    expectError(error.CouldNotParseInteger, parseArgsList(struct {
        foo: u8,
    }, [_][]const u8{ "./a", "--foo", "-42" }));
}

test "argparse.signed" {
    const result = try parseArgsList(struct {
        foo: i8,
    }, [_][]const u8{ "./a", "--foo", "-42" });
    expectEqual(result.foo, -42);
}

test "argparse.uintMax" {
    expectError(error.CouldNotParseInteger, parseArgsList(struct {
        foo: u8,
    }, [_][]const u8{ "./a", "--foo", "256" }));
}

test "argparse.notInt" {
    expectError(error.CouldNotParseInteger, parseArgsList(struct {
        foo: u8,
    }, [_][]const u8{ "./a", "--foo", "hi" }));
}

test "argparse.floatInInt" {
    expectError(error.CouldNotParseInteger, parseArgsList(struct {
        foo: u32,
    }, [_][]const u8{ "./a", "--foo", "123.45" }));
}

test "argparse.nonFloat" {
    expectError(error.CouldNotParseFloat, parseArgsList(struct {
        foo: f32,
    }, [_][]const u8{ "./a", "--foo", "hi" }));
}

test "argparse.float" {
    const result = try parseArgsList(struct {
        foo: f64,
    }, [_][]const u8{ "./a", "--foo", "123.456" });
    expectEqual(result.foo, 123.456);
}

test "argparse.key=value" {
    const result = try parseArgsList(struct {
        foo: u32,
    }, [_][]const u8{ "./a", "--foo=123" });
    expectEqual(result.foo, 123);
}

test "argparse.expectedValueFoundArgument" {
    expectError(error.ExpectedArgument, parseArgsList(struct {
        foo: ?u32,
        bar: ?bool,
    }, [_][]const u8{ "./a", "--foo", "--bar" }));
}

test "argparse.array.u32" {
    const result = try parseArgsList(struct {
        dim: [2]u32,
    }, [_][]const u8{ "./a", "--dim", "2", "3" });
    expectEqual(result.dim[0], 2);
    expectEqual(result.dim[1], 3);
}

test "argparse.array.string" {
    const result = try parseArgsList(struct {
        names: [3][]const u8,
    }, [_][]const u8{ "./a", "--names", "Alice", "Bob", "Carol" });
    expectEqualSlices(u8, result.names[0], "Alice");
    expectEqualSlices(u8, result.names[1], "Bob");
    expectEqualSlices(u8, result.names[2], "Carol");
}

test "argparse.array.notEnough" {
    expectError(error.NotEnoughArrayArguments, parseArgsList(struct {
        dim: [2]u32,
    }, [_][]const u8{ "./a", "--dim", "2" }));
}

test "argparse.array.tooMany" {
    expectError(error.UnexpectedArgument, parseArgsList(struct {
        dim: [2]u32,
    }, [_][]const u8{ "./a", "--dim", "2", "3", "4" }));
}

test "argparse.array.typeSafe" {
    expectError(error.CouldNotParseInteger, parseArgsList(struct {
        dim: [2]u32,
    }, [_][]const u8{ "./a", "--dim", "2", "blah" }));
}

test "argparse.slice.u32" {
    const result = try parseArgsList(struct {
        dim: []u32,
    }, [_][]const u8{ "./a", "--dim", "2", "3", "4" });
    expectEqual(result.dim[0], 2);
    expectEqual(result.dim[1], 3);
    expectEqual(result.dim[2], 4);
}

test "argparse.slice.empty" {
    const result = try parseArgsList(struct {
        dim: []u32,
    }, [_][]const u8{ "./a", "--dim" });
    expectEqual(result.dim.len, 0);
}

test "argparse.slice.untilNextArg" {
    const result = try parseArgsList(struct {
        dim: []u32,
        foo: u32,
    }, [_][]const u8{ "./a", "--dim", "2", "3", "--foo", "4" });
    expectEqual(result.dim[0], 2);
    expectEqual(result.dim[1], 3);
    expectEqual(result.dim.len, 2);
    expectEqual(result.foo, 4);
}

test "argparse.slice.typeSafe" {
    expectError(error.UnexpectedArgument, parseArgsList(struct {
        dim: []u32,
        foo: u32,
    }, [_][]const u8{ "./a", "--dim", "2", "blah", "--foo", "4" }));
    expectError(error.UnexpectedArgument, parseArgsList(struct {
        dim: []u8,
        foo: u32,
    }, [_][]const u8{ "./a", "--dim", "2", "1000", "--foo", "4" }));
}
