const std = @import("std");
const json = @import("../json.zig");
const haversine_formula = @import("haversine_formula.zig");
const timer = @import("..//timer.zig");

pub const Error = error{InvalidInput};

pub fn process(allocator: std.mem.Allocator, input_file: std.fs.File, optional_answers_file: ?std.fs.File) !void {
    const start_time = timer.time();
    var read_file_duration: u64 = undefined;
    var parse_json_duration: u64 = undefined;
    var process_duration: u64 = undefined;
    var deinit_file_duration: u64 = undefined;
    var deinit_json_duration: u64 = undefined;
    defer {
        const duration = timer.time() - start_time;
        std.debug.print("haversine process time: {d}s ({d}ns)\n", .{ timer.toS(duration), timer.toNs(duration) });
        std.debug.print("\tread file: {d}s ({d}ns) ({d}%)\n", .{ timer.toS(read_file_duration), timer.toNs(read_file_duration), timer.percentage(read_file_duration, duration) });
        std.debug.print("\tparse json: {d}s ({d}ns) ({d}%)\n", .{ timer.toS(parse_json_duration), timer.toNs(parse_json_duration), timer.percentage(parse_json_duration, duration) });
        std.debug.print("\tprocess: {d}s ({d}ns) ({d}%)\n", .{ timer.toS(process_duration), timer.toNs(process_duration), timer.percentage(process_duration, duration) });
        std.debug.print("\tdeinit file: {d}s ({d}ns) ({d}%)\n", .{ timer.toS(deinit_file_duration), timer.toNs(deinit_file_duration), timer.percentage(deinit_file_duration, duration) });
        std.debug.print("\tdeinit json: {d}s ({d}ns) ({d}%)\n", .{ timer.toS(deinit_json_duration), timer.toNs(deinit_json_duration), timer.percentage(deinit_json_duration, duration) });
    }
    const read_file_start_time = timer.time();
    const input_file_data = try input_file.readToEndAlloc(allocator, 1024 * 1024 * 1024 * 1024);
    read_file_duration = timer.time() - read_file_start_time;
    defer {
        const deinit_file_start_time = timer.time();
        allocator.free(input_file_data);
        deinit_file_duration = timer.time() - deinit_file_start_time;
    }

    const parse_json_start_time = timer.time();
    var json_data = try json.Parser.parse(allocator, input_file_data);
    parse_json_duration = timer.time() - parse_json_start_time;
    defer {
        const deinit_json_start_time = timer.time();
        json_data.deinit(allocator);
        deinit_json_duration = timer.time() - deinit_json_start_time;
    }

    const process_start_time = timer.time();
    if (json_data != .t_object) {
        return Error.InvalidInput;
    }

    const pairs = json_data.t_object.get(json.String.reference("pairs")) orelse return Error.InvalidInput;

    if (pairs != .t_array) {
        return Error.InvalidInput;
    }

    var total: f64 = 0;
    const pair_count = pairs.t_array.items.len;
    for (pairs.t_array.items) |pair| {
        const pair_object = if (pair == .t_object) pair.t_object else return Error.InvalidInput;

        const x0 = try getObjectNumberForKey(pair_object, "x0");
        const y0 = try getObjectNumberForKey(pair_object, "y0");
        const x1 = try getObjectNumberForKey(pair_object, "x1");
        const y1 = try getObjectNumberForKey(pair_object, "y1");

        const result = haversine_formula.referenceHaversine(x0, y0, x1, y1, haversine_formula.default_earth_radius);
        total += result;
    }
    const average = total / @as(f64, @floatFromInt(pair_count));

    std.debug.print("Input size: {d}\nPair count: {d}\nHaversine sum: {d}\n", .{ input_file_data.len, pair_count, average });
    if (optional_answers_file) |answers_file| {
        try answers_file.seekTo(try answers_file.getEndPos() - 8);
        var reference_average: f64 = undefined;
        const bytes_read = try answers_file.read(@as([*]u8, @ptrCast(&reference_average))[0..8]);
        std.debug.assert(bytes_read == 8);
        std.debug.print("\nValidation:\nReference sum: {d}\nDifference: {d}\n", .{ reference_average, average - reference_average });
    }
    process_duration = timer.time() - process_start_time;
}

fn getObjectNumberForKey(object: json.Parser.Item.Object, key: []const u8) !f64 {
    const x = object.get(json.String.reference(key)) orelse return Error.InvalidInput;
    if (x != .t_number) {
        return Error.InvalidInput;
    }

    return x.t_number;
}
