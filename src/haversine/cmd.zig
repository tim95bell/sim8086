const std = @import("std");
const generator = @import("generator.zig");

fn printUsage() void {
    std.debug.print("generator [file path] [uniform/cluster] [random seed] [number of coordinate pairs to generate]\n", .{});
}

pub fn run(args: [][:0]u8) !void {
    if (args.len != 4) {
        printUsage();
        return;
    }

    const file = std.fs.cwd().createFile(args[0], .{}) catch {
        std.debug.print("Failed to open file: \"{s}\"\n", .{args[0]});
        printUsage();
        return;
    };
    defer file.close();

    const mode: generator.Mode =
        if (std.mem.eql(u8, args[1], "uniform")) .uniform else if (std.mem.eql(u8, args[1], "cluster")) .cluster else {
        std.debug.print("Unknown mode \"{s}\", must be \"uniform\" or \"cluster\"\n", .{args[1]});
        printUsage();
        return;
    };

    const random_seed: usize = std.fmt.parseInt(usize, args[2], 10) catch {
        std.debug.print("Invalid random seed: \"{s}\"\n", .{args[2]});
        printUsage();
        return;
    };

    const pair_count: usize = std.fmt.parseInt(usize, args[3], 10) catch {
        std.debug.print("Invalid number of coordinate pairs to generate: \"{s}\"\n", .{args[3]});
        printUsage();
        return;
    };

    try generator.generate(file.writer(), mode, random_seed, pair_count);
}
