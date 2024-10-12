const std = @import("std");
const generator = @import("generator.zig");
const processor = @import("processor.zig");

fn printGeneratorUsage() void {
    std.debug.print("haversine generate [output.json] [answers.f64] [uniform/cluster] [random seed] [number of coordinate pairs to generate]\n", .{});
}

fn printProcessorUsage() void {
    std.debug.print("haversine process [input.json] [answers.f64]\n", .{});
    std.debug.print("haversine process [input.json]\n", .{});
}

pub fn printUsage() void {
    printGeneratorUsage();
    printProcessorUsage();
}

pub fn run(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    if (args.len < 1) {
        printUsage();
        return;
    }

    if (std.mem.eql(u8, args[0], "generate")) {
        if (args.len != 6) {
            printGeneratorUsage();
            return;
        }

        const json_file = std.fs.cwd().createFile(args[1], .{}) catch {
            std.debug.print("Failed to open file: \"{s}\"\n", .{args[1]});
            printGeneratorUsage();
            return;
        };
        defer json_file.close();

        const answers_file = std.fs.cwd().createFile(args[2], .{}) catch {
            std.debug.print("Failed to open file: \"{s}\"\n", .{args[2]});
            printGeneratorUsage();
            return;
        };
        defer answers_file.close();

        const mode: generator.Mode =
            if (std.mem.eql(u8, args[3], "uniform")) .uniform else if (std.mem.eql(u8, args[3], "cluster")) .cluster else {
            std.debug.print("Unknown mode \"{s}\", must be \"uniform\" or \"cluster\"\n", .{args[3]});
            printUsage();
            return;
        };

        const random_seed: usize = std.fmt.parseInt(usize, args[4], 10) catch {
            std.debug.print("Invalid random seed: \"{s}\"\n", .{args[4]});
            printGeneratorUsage();
            return;
        };

        const pair_count: usize = std.fmt.parseInt(usize, args[5], 10) catch {
            std.debug.print("Invalid number of coordinate pairs to generate: \"{s}\"\n", .{args[5]});
            printGeneratorUsage();
            return;
        };

        var json_buffered_writer = std.io.bufferedWriter(json_file.writer());
        defer json_buffered_writer.flush() catch {
            std.debug.print("Failed to flush buffered writer\n", .{});
        };

        var answers_buffered_writer = std.io.bufferedWriter(answers_file.writer());
        defer answers_buffered_writer.flush() catch {
            std.debug.print("Failed to flush buffered writer\n", .{});
        };

        try generator.generate(json_buffered_writer.writer(), answers_buffered_writer.writer(), mode, random_seed, pair_count);
    } else if (std.mem.eql(u8, args[0], "process")) {
        if (args.len < 2 or args.len > 3) {
            printProcessorUsage();
            return;
        }

        const json_file = std.fs.cwd().openFile(args[1], .{}) catch {
            std.debug.print("Failed to open json input file: \"{s}\"\n", .{args[1]});
            printProcessorUsage();
            return;
        };
        defer json_file.close();

        const answers_file: ?std.fs.File = if (args.len > 2) std.fs.cwd().openFile(args[2], .{}) catch {
            std.debug.print("Failed to open answers file: \"{s}\"\n", .{args[2]});
            printProcessorUsage();
            return;
        } else null;
        defer if (answers_file) |x| {
            x.close();
        };

        try processor.process(allocator, json_file, answers_file);
    } else {
        printUsage();
        return;
    }
}
