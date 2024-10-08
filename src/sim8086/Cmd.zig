const std = @import("std");
const Runner = @import("Runner.zig");

pub fn run(args: [][:0]u8) !void {
    var file_name: []u8 = &.{};
    var decode: bool = false;
    var exec: bool = false;
    var dump: bool = false;
    var print_clocks: bool = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-exec")) {
            exec = true;
        } else if (std.mem.eql(u8, arg, "-dump")) {
            dump = true;
        } else if (std.mem.eql(u8, arg, "-decode")) {
            decode = true;
        } else if (std.mem.eql(u8, arg, "-print_clocks")) {
            print_clocks = true;
        } else {
            file_name = arg;
        }
    }
    if (file_name.len == 0) {
        @panic("you must provide a file to decode as a command line argument");
    }
    std.debug.assert(!(dump and !exec));
    std.debug.assert(!(print_clocks and !exec));

    if (exec) {
        std.debug.assert(!decode);
        try Runner.run(.{
            .file_name = file_name,
            .action = .{
                .exec = .{
                    .dump = dump,
                    .print_clocks = print_clocks,
                },
            },
        });
    } else {
        std.debug.assert(exec);
        try Runner.run(.{
            .file_name = file_name,
            .action = .decode,
        });
    }
}
