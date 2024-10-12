const std = @import("std");
const runner = @import("runner.zig");

pub fn printUsage() void {
    std.debug.print("sim8086 [8086 program file] [options]\n\tOptions:\n\t\t-exec\tExecute program\n\t\t-dump\tDump memory to file after execution\n\t\t-print_clocks\tPrint clocks of each instruction during execution\n", .{});
}

pub fn run(args: [][:0]u8) !void {
    var file_name: []u8 = &.{};
    var exec: bool = false;
    var dump: bool = false;
    var print_clocks: bool = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-exec")) {
            exec = true;
        } else if (std.mem.eql(u8, arg, "-dump")) {
            dump = true;
        } else if (std.mem.eql(u8, arg, "-print_clocks")) {
            print_clocks = true;
        } else {
            file_name = arg;
        }
    }

    if (file_name.len == 0) {
        printUsage();
        return;
    }

    if (dump and !exec) {
        std.debug.print("cannot dump without executing: -dump -exec\n", .{});
    }

    if (print_clocks and !exec) {
        std.debug.print("cannot print clocks without executing: -print_clocks -exec\n", .{});
    }

    if (exec) {
        try runner.run(.{
            .file_name = file_name,
            .action = .{
                .exec = .{
                    .dump = dump,
                    .print_clocks = print_clocks,
                },
            },
        });
    } else {
        try runner.run(.{
            .file_name = file_name,
            .action = .decode,
        });
    }
}
