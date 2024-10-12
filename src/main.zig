const std = @import("std");
const sim8086 = @import("sim8086.zig");
const haversine = @import("haversine.zig");
const json = @import("json.zig");

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    if (args.len <= 1) {
        std.debug.print("Subprogram command line argument missing\n", .{});
        sim8086.cmd.printUsage();
        haversine.cmd.printUsage();
        return;
    }

    if (std.mem.eql(u8, args[1], "sim8086")) {
        try sim8086.cmd.run(args[2..]);
    } else if (std.mem.eql(u8, args[1], "haversine")) {
        try haversine.cmd.run(gpa, args[2..]);
    } else {
        std.debug.print("unknown subprogram: {s}\n", .{args[1]});
    }
}

test {
    std.testing.refAllDecls(json);
    std.testing.refAllDecls(sim8086);
    std.testing.refAllDecls(haversine);
}
