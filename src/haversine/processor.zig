const std = @import("std");
const json = @import("../json.zig");
const haversine_formula = @import("haversine_formula.zig");

pub const Error = error{InvalidInput};

pub fn process(allocator: std.mem.Allocator, input_file: std.fs.File, optional_answers_file: ?std.fs.File) !void {
    const input_file_data = try input_file.readToEndAlloc(allocator, 1024 * 1024 * 1024);
    defer allocator.free(input_file_data);

    var json_data = try json.Parser.parse(allocator, input_file_data);
    defer json_data.deinit(allocator);
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
}

fn getObjectNumberForKey(object: json.Parser.Item.Object, key: []const u8) !f64 {
    const x = object.get(json.String.reference(key)) orelse return Error.InvalidInput;
    if (x != .t_number) {
        return Error.InvalidInput;
    }

    return x.t_number;
}
