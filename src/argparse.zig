const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const logInsideTest = @import("tests.zig").logInsideTest;
usingnamespace @import("utils.zig");

// getting default values depends on https://github.com/ziglang/zig/issues/2937
// parsing doc strings depends on https://github.com/ziglang/zig/issues/2573

// TODOs:
// disallow passing the same arg twice
// add a way to allow `--` at the start of values?
// support positional arguments
// support comma-separate array values? --arrayArg=1,2,3 or --arrayArg 1,2,3

const log = if (builtin.is_test) logInsideTest else std.debug.warn;

// Use this in the struct as a value that's specifically ignored by the parser
// and gets filled with all positional arguments
pub const PositionalArguments = [][]const u8;

const AliasEntry = struct {
    fieldName: []const u8,
};
pub fn Alias(comptime fieldName: []const u8) AliasEntry {
    return AliasEntry{ .fieldName = fieldName };
}
const ArgParseError = error{
    CalledWithoutAnyArguments,
    InvalidArgs,
    MissingRequiredArgument,
    ExpectedArgument,
    CouldNotParseInteger,
    CouldNotParseFloat,
    UnexpectedArgument,
    NotEnoughArrayArguments,
    OutOfMemory,
};

const ArgParseOptions = struct {
    allocator: *std.mem.Allocator = std.heap.c_allocator,
};

/// Parse process's command line arguments subject to the passed struct's format.
pub fn parseArgs(comptime T: type) !T {
    return parseArgsOpt(T, ArgParseOptions{});
}

/// Parse process's command line arguments subject to the passed struct's format and parsing options
pub fn parseArgsOpt(comptime T: type, options: ArgParseOptions) !T {
    const args = try std.process.argsAlloc(options.allocator);
    return parseArgsListOpt(T, args, options);
}

/// Parse arbitrary string arguments subject to the passed struct's format.
pub fn parseArgsList(comptime T: type, args: []const []const u8) ArgParseError!T {
    return parseArgsListOpt(T, args, ArgParseOptions{});
}

fn Context(comptime T: type) type {
    return struct {
        args: []const []const u8,
        arg_i: usize,
        result: T,
        silent: bool = false,
    };
}

/// Parse arbitrary string arguments subject to the passed struct's format and parsing options.
pub fn parseArgsListOpt(comptime T: type, args: []const []const u8, options: ArgParseOptions) ArgParseError!T {
    if (args.len < 1) {
        log("\nFirst argument should be the program name\n");
        return error.CalledWithoutAnyArguments;
    }
    const info = @typeInfo(T).Struct;

    var ctx = Context(T){
        .args = args,
        .arg_i = 1, // skip program name
        .result = undefined,
    };

    // set all optional fields to null
    inline for (info.fields) |field| {
        const fieldInfo = @typeInfo(field.field_type);
        switch (fieldInfo) {
            .Optional => {
                if (fieldInfo.Optional.child == bool) {
                    // optional bools are just false
                    @field(ctx.result, field.name) = false;
                } else {
                    @field(ctx.result, field.name) = null;
                }
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

    while (ctx.arg_i < args.len) : (ctx.arg_i += 1) {
        const arg = args[ctx.arg_i];
        if (mem.eql(u8, arg, "--help")) {
            usage(T, args);
            return error.InvalidArgs;
        }

        if (startsWith(arg, "--")) {
            inline for (info.fields) |field| {
                const name = field.name;
                var argName = arg[2..];
                var next: ?[]const u8 = null;
                if (splitAtFirst(argName, '=')) |parts| {
                    argName = parts[0];
                    next = parts[1];
                }
                if (mem.eql(u8, argName, name)) {
                    const typeInfo = @typeInfo(NonOptional(field.field_type));
                    switch (typeInfo) {
                        .Bool => {
                            @field(ctx.result, name) = true;
                        },
                        .Array => |arrType| {
                            // TODO: split next arg on ','?
                            const len = arrType.len;

                            if (ctx.arg_i + len >= ctx.args.len) {
                                usage(T, ctx.args);
                                log("\nMust provide {} values for array argument '{}'\n", usize(len), name);
                                return error.NotEnoughArrayArguments;
                            }

                            var array_i: usize = 0;
                            while (array_i < len) : (array_i += 1) {
                                ctx.arg_i += 1;
                                const value = ctx.args[ctx.arg_i];
                                @field(ctx.result, field.name)[array_i] = try parseValueForField(T, &ctx, field.name, arrType.child, value);
                            }
                        },
                        .Pointer => |pointerType| {
                            // TODO: split next arg on ','?
                            if (builtin.TypeInfo.Pointer.Size(pointerType.size) == .One) {
                                @compileError("Pointers are not supported as argument types.");
                            }
                            handlePtrBlk: {
                                if (pointerType.is_const) {
                                    if (pointerType.child == u8) {
                                        var value = if (next) |nonNullNext| nonNullNext else blk: {
                                            ctx.arg_i += 1;
                                            if (ctx.arg_i >= ctx.args.len) {
                                                usage(T, ctx.args);
                                                return error.ExpectedArgument;
                                            }
                                            break :blk ctx.args[ctx.arg_i];
                                        };

                                        @field(ctx.result, field.name) = try parseValueForField(T, &ctx, field.name, field.field_type, value);
                                        break :handlePtrBlk;
                                    } else {
                                        @compileError("non-string slices must not be const: " ++ @typeName(T) ++ "." ++ field.name ++ " is " ++ @typeName(field.field_type));
                                    }
                                }

                                // count number of valid next args
                                var countingCtx: Context(T) = ctx; // copy context to count in
                                countingCtx.silent = true;
                                const starting_arg_i = ctx.arg_i + 1;
                                var sliceCount: usize = 0;
                                while (true) : (sliceCount += 1) {
                                    if (starting_arg_i + sliceCount >= ctx.args.len) {
                                        break;
                                    }
                                    const value = ctx.args[starting_arg_i + sliceCount];
                                    _ = parseValueForField(T, &countingCtx, field.name, pointerType.child, value) catch {
                                        break;
                                    };
                                }

                                @field(ctx.result, field.name) = try options.allocator.alloc(pointerType.child, sliceCount);

                                var array_i: usize = 0;
                                while (array_i < sliceCount) : (array_i += 1) {
                                    ctx.arg_i += 1;
                                    const value = ctx.args[ctx.arg_i];
                                    @field(ctx.result, field.name)[array_i] = try parseValueForField(T, &ctx, field.name, pointerType.child, value);
                                }
                            }
                        },
                        else => {
                            var value = if (next) |nonNullNext| nonNullNext else blk: {
                                ctx.arg_i += 1;
                                if (ctx.arg_i >= ctx.args.len) {
                                    usage(T, ctx.args);
                                    return error.ExpectedArgument;
                                }
                                break :blk ctx.args[ctx.arg_i];
                            };

                            @field(ctx.result, field.name) = try parseValueForField(T, &ctx, field.name, field.field_type, value);
                        },
                    }

                    markArgAsFound(requiredArgs.len, &requiredArgs, name);
                    break;
                }
            }
        } else {
            // TODO: Support positional args
            usage(T, args);
            log("\nUnexpected argument '{}'\n", arg);
            return error.UnexpectedArgument;
        }
    }

    for (requiredArgs) |req_arg| {
        if (req_arg) |rarg| {
            usage(T, args);
            log("\nMissing required argument '{}'\n", rarg);
            return error.MissingRequiredArgument;
        }
    }

    return ctx.result;
}

fn usage(comptime T: type, args: []const []const u8) void {
    const info = @typeInfo(T).Struct;
    log("Usage: {}\n", args[0]);
    inline for (info.fields) |field| {
        const name = field.name;
        log("--{}", name);
        if (field.field_type != ?bool) {
            log("=({})", @typeName(field.field_type));
        }
        log("\n");
    }
}

fn markArgAsFound(comptime n: usize, requiredArgs: *[n](?[]const u8), name: []const u8) void {
    for (requiredArgs) |*reqArg| {
        if (reqArg.*) |reqArgName| {
            if (mem.eql(u8, reqArgName, name)) {
                reqArg.* = null;
            }
        }
    }
}

fn parseValueForField(
    comptime T: type,
    ctx: *Context(T),
    comptime name: []const u8,
    comptime FieldType: type,
    value: []const u8,
) ArgParseError!NonOptional(FieldType) {
    comptime const FT = NonOptional(FieldType);
    if (startsWith(value, "--")) {
        if (!ctx.silent) {
            usage(T, ctx.args);
            log("\nExpected value for argument '{}', found argument '{}'\n", name, value);
        }
        return error.ExpectedArgument;
    }
    switch (FT) {
        u8, u16, u32, u64, i8, i16, i32, i64, usize => {
            return std.fmt.parseInt(FT, value, 10) catch |e| {
                if (!ctx.silent) {
                    usage(T, ctx.args);
                    log("\nExpected {} for '{}', found '{}'\n", @typeName(FT), name, value);
                }
                return error.CouldNotParseInteger;
            };
        },
        f32, f64 => {
            return std.fmt.parseFloat(FT, value) catch |e| {
                if (!ctx.silent) {
                    usage(T, ctx.args);
                    log("\nExpected {} for '{}', found '{}'\n", @typeName(FT), name, value);
                }
                return error.CouldNotParseFloat;
            };
        },
        []const u8 => {
            return value;
        },
        else => unreachable,
    }
}
