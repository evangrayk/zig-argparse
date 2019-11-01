const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;

// getting default values depends on https://github.com/ziglang/zig/issues/2937
// parsing doc strings depends on https://github.com/ziglang/zig/issues/2573

// TODOs:
// disallow passing the same arg twice
// look for '=' so `--arg=val` is the same as `--arg val`
// add a way to allow `--` at the start of values?
// support positional arguments

// Use this in the struct as a value that's specifically ignored by the parser
// and gets filled with all positional arguments
pub const PositionalArguments = [][]const u8;

fn markArgAsFound(comptime n: usize, requiredArgs: *[n](?[]const u8), name: []const u8) void {
    for (requiredArgs) |*reqArg| {
        if (reqArg.*) |reqArgName| {
            if (mem.eql(u8, reqArgName, name)) {
                reqArg.* = null;
            }
        }
    }
}

fn usage(comptime T: type, args: [][]const u8) void {
    const info = @typeInfo(T).Struct;
    warn("Usage: {}\n", args[0]);
    inline for (info.fields) |field| {
        const name = field.name;
        warn("--{}", name);
        if (field.field_type != ?bool) {
            warn("=({})", @typeName(field.field_type));
        }
        warn("\n");
    }
}

pub fn parseArgs(comptime T: type) !T {
    const args = try std.process.argsAlloc(std.heap.c_allocator);

    var arg_i: usize = 0;

    const info = @typeInfo(T).Struct;

    // set all optional fields to null
    var result: T = undefined;
    inline for (info.fields) |field| {
        switch (@typeInfo(field.field_type)) {
            .Optional => {
                @field(result, field.name) = null;
                break;
            },
            else => continue,
        }
    }

    // collect required arguments
    var requiredArgs: [info.fields.len](?[]const u8) = undefined;
    inline for (info.fields) |field, field_i| {
        switch (@typeInfo(field.field_type)) {
            .Optional => continue,
            else => {
                requiredArgs[field_i] = field.name;
            },
        }
    }

    while (arg_i < args.len) : (arg_i += 1) {
        const arg = args[arg_i];
        if (mem.eql(u8, arg, "--help")) {
            usage(T, args);
            return error.InvalidArgs;
        }

        if (startsWith(arg, "--")) {
            const argName = arg[2..];
            inline for (info.fields) |field| {
                const name = field.name;
                if (mem.eql(u8, argName, name)) {
                    if (field.field_type == ?bool) {
                        @field(result, name) = true;
                    } else {
                        arg_i += 1;
                        if (arg_i >= args.len) {
                            usage(T, args);
                            warn("\nExpected value after {}\n", name);
                            return error.ExpectedArgument;
                        }
                        const value = args[arg_i];
                        if (startsWith(value, "--")) {
                            usage(T, args);
                            warn("\nExpected value after {}, found argument '{}'\n", name, value);
                            return error.ExpectedArgument;
                        }
                        switch (field.field_type) {
                            u8, u16, u32, u64, i8, i16, i32, i64, usize => {
                                @field(result, name) = std.fmt.parseInt(field.field_type, value, 10) catch |e| {
                                    usage(T, args);
                                    warn("\nExpected {} for '{}', found '{}'\n", @typeName(field.field_type), name, value);
                                    return e;
                                };
                                markArgAsFound(requiredArgs.len, &requiredArgs, name);
                                break;
                            },
                            f32, f64 => {
                                @field(result, name) = std.fmt.parseFloat(field.field_type, value) catch |e| {
                                    usage(T, args);
                                    warn("\nExpected {} for '{}', found '{}'\n", @typeName(field.field_type), name, value);
                                    return e;
                                };
                                markArgAsFound(requiredArgs.len, &requiredArgs, name);
                                break;
                            },
                            []const u8 => {
                                @field(result, name) = value;
                                markArgAsFound(requiredArgs.len, &requiredArgs, name);
                                break;
                            },
                            else => unreachable,
                        }
                    }
                }
            }
        }
    }

    for (requiredArgs) |req_arg| {
        if (req_arg) |rarg| {
            usage(T, args);
            warn("\nMissing required argument '{}'\n", rarg);
            return error.MissingRequiredArgument;
        }
    }

    return result;
}

fn startsWith(s: []const u8, prefix: []const u8) bool {
    return s.len >= prefix.len and (mem.eql(u8, s[0..prefix.len], prefix));
}
