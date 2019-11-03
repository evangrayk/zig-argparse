# zig argparse
## Easy declarative argument parsing in zig

```zig
const parseArgs = @import("argparse.zig").parseArgs;

/// All you need to provide is a type defining what arguments you expect / support.
const MyArgs = struct {
    // Any field of this struct is an argument. Optional args will be `null` if not provided by the user.
    name: ?[]const u8,

    // `--foo` sets this to `true`, otherwise it's set to `false`
    foo: ?bool,

    // required because type is not optional, parsing will fail if not provided.
    // This gets parsed as a number, with bounds checks.
    age: u32,
};

pub fn main() void {
    const parsed = parseArgs(MyArgs) catch return;

    std.debug.warn("{}\n", parsed.age);
    if (parsed.name) |name| {
        std.debug.warn("{}\n", name);
    }
}
```

Note that you can catch errors instead of just returning. You could `return -1` for example.

If you want to support subcommands or otherwise preprocess arguments, you could use `parseArgsList` and provide a slice of strings.

# Features

## Parse with = or additional arguments
```
./a --foo 123
```
is the same as 
```
./a --foo=123
```

## Array types
```zig
const MyArgs = struct {
    resoultion: [2]u32,
};
// ./a --resolution 1920 1080
```

## Number bounds checks
Since numbers are parsed with zig's std lib, they get bounds checked
```zig
const MyArgs = struct {
    age: ?u32,
    small: ?i8,
};
// ./a --number -42
// Expected u32 for 'age', found '-42'

// ./a --small 10000
// Expected i8 for 'small', found '10000'
```

## Float parsing when expected
If you declare your arg as an int, it won't validate floats.
If you declare your arg as a float, it will allow floats or integers.
```zig
const MyArgs = struct {
    height: ?f32,
    age: ?u32,
};
// ./a --height 1.85
// ./a --age 1.85       Expected u32 for 'age', found '1.85'     
```

# Future...

## Default values
If [#2937](https://github.com/ziglang/zig/issues/2937) is done,
arguments can provide default values as part of the struct!
```zig
const MyArgs = struct {
    foo: i32 = 20,
};
// foo is 20 if not provided, instead of null. Type doesn't need to be optional if a default is given.
```

Unimplemented Workaround idea:  provide a constant declaration value
that matches argument name
```zig
const MyArgs = struct {
    foo: i32,
    const foo__DEFAULT = 33;
};
```


## Documentation
If [#2573](https://github.com/ziglang/zig/issues/2573) is done,
doc strings can be shown when `--help` is used!
```zig
const MyArgs = struct {
    /// This comment would show up if on `--help` or when used incorrectly
    foo: i32 = 20,
};
```

Unimplemented Workaround idea:  provide a constant declaration string
that matches argument name
```zig
const MyArgs = struct {
    foo: i32,
    const foo__DOC = "This string would show in `--help`";
};
```

## Support arbitrary length arguments
(TODO)
This would parse any number of values for an argument until the next argument is found

```zig
const MyArgs = struct {
    names: [][]const u8,
    foo: bool,
};
// ./a --names Alice Bob Carol --foo
```

## Collect extra arguments
(TODO)
Any arguments not starting with `--` are errors right now, but these could be accumulated and put somewhere. There could be a special signal value:

```zig
const MyArgs = struct {
    foo: bool,

    files: PositionalArguments,
};
// ./a file1.txt file2.txt
```
Where `PositionalArguments` would be a type provided by the library, which is basically just an array of string in some form.


## Positional arguments
(TODO)
Add a syntax to say that an argument is not specified by name, but is instead positional. A type wrapper seems like a nice way to do this.

```zig
const MyArgs = struct {
    age: Positional(u32),
    height: Positional(f32),

    foo: bool,
};
// ./a file1.txt file2.txt
```

## Aliases
(TODO)
Add a syntax to say that an argument is an alias for another one, so you can provide duplicate functionality without thinking about it in your usage code. This would also let you define "short" versions of commands.

```zig
const MyArgs = struct {
    file: []const u8,
    fileName: Alias("file"),
    f: Alias("file"),
};
// All these are equivalent:
// ./a --file foo.txt
// ./a --fileName foo.txt
// ./a -f foo.txt
```