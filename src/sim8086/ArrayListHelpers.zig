const std = @import("std");

pub fn insertSortedSetArrayList(xs: *std.ArrayList(usize), y: usize) !void {
    for (xs.items, 0..) |x, xs_index| {
        if (x < y) {
            continue;
        } else if (x > y) {
            try xs.insert(xs_index, y);
            return;
        } else if (x == y) {
            return;
        }
    }

    try xs.append(y);
}

pub fn findValueIndex(xs: std.ArrayList(usize), value: usize) ?usize {
    for (xs.items, 0..) |x, i| {
        if (x == value) {
            return i;
        }
    }
    return null;
}
