const std = @import("std");
const sim8086 = @import("./sim8086/Cmd.zig");

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    if (args.len <= 2) {
        std.debug.print("Subprogram command line argument missing\n", .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "sim8086")) {
        try sim8086.run(args[2..]);
    } else {
        std.debug.print("unknown subprogram: {s}\n", .{args[1]});
    }
}
