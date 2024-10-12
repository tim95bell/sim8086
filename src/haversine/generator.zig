const std = @import("std");
const haversine_formula = @import("haversine_formula.zig");

const Coordinate = struct {
    x: f64,
    y: f64,

    pub fn randomize(self: *Coordinate, random: std.Random) void {
        self.x = random.float(f64) * 360;
        std.debug.assert(self.x >= 0 and self.x < 360);
        self.y = random.float(f64) * 360;
        std.debug.assert(self.y >= 0 and self.y < 360);
    }

    pub fn randomize_cluster(self: *Coordinate, random: std.Random, cluster_center: Coordinate, cluster_radius: f64) void {
        const r = cluster_radius * std.math.sqrt(random.float(f64));
        const theta = random.float(f64) * 2 * std.math.pi;

        self.x = cluster_center.x + r * std.math.cos(theta);
        std.debug.assert(self.x >= -cluster_radius and self.x < (360 + cluster_radius));
        if (self.x < 0) {
            self.x += 360;
        } else if (self.x >= 360) {
            self.x -= 360;
        }
        std.debug.assert(self.x >= 0 and self.x < 360);

        self.y = cluster_center.y + r * std.math.sin(theta);
        std.debug.assert(self.y >= -cluster_radius and self.y <= (360 + cluster_radius));
        if (self.y < 0) {
            self.y += 360;
        } else if (self.y >= 360) {
            self.y -= 360;
        }
        std.debug.assert(self.y >= 0 and self.y < 360);
    }
};

const CoordinatePair = struct {
    a: Coordinate,
    b: Coordinate,

    pub fn randomize(self: *CoordinatePair, random: std.Random) void {
        self.a.randomize(random);
        self.b.randomize(random);
    }

    pub fn randomize_cluster(self: *CoordinatePair, random: std.Random, cluster_a_center: Coordinate, cluster_b_center: Coordinate, cluster_radius: f64) void {
        self.a.randomize_cluster(random, cluster_a_center, cluster_radius);
        self.b.randomize_cluster(random, cluster_b_center, cluster_radius);
    }

    fn print(self: *CoordinatePair, writer: anytype) !void {
        try writer.print("{{\"x0\": {d}, \"y0\": {d}, \"x1\": {d}, \"y1\": {d}}}", .{ self.a.x, self.a.y, self.b.x, self.b.y });
    }
};

pub const Mode = enum { uniform, cluster };

pub fn generate(writer: std.fs.File.Writer, mode: Mode, random_seed: usize, pair_count: usize) !void {
    var prng = std.rand.DefaultPrng.init(random_seed);
    const rand = prng.random();

    var buffered_writer = std.io.bufferedWriter(writer);
    defer buffered_writer.flush() catch {
        std.debug.print("Failed to flush buffered writer\n", .{});
    };
    var buffered_writer_writer = buffered_writer.writer();

    var total: f64 = 0;
    try buffered_writer_writer.print("{{\"pairs\": [\n", .{});
    var pair: CoordinatePair = undefined;

    const cluster_count = 64;
    var cluster_group_count: usize = undefined;
    var larger_cluster_group_count: usize = undefined;
    var cluster_with_larger_size_count: usize = undefined;

    if (mode == .uniform) {
        for (0..pair_count) |i| {
            pair.randomize(rand);
            total += haversine_formula.referenceHaversine(pair.a.x, pair.a.y, pair.b.x, pair.b.y, haversine_formula.default_earth_radius);
            try buffered_writer_writer.print("\t", .{});
            try pair.print(buffered_writer_writer);
            if (i < pair_count - 1) {
                try buffered_writer_writer.print(",\n", .{});
            }
        }
    } else {
        std.debug.assert(mode == .cluster);
        const cluster_radius: f64 = 360.0 * 0.05;
        cluster_group_count = pair_count / cluster_count;
        larger_cluster_group_count = cluster_group_count + 1;
        cluster_with_larger_size_count = pair_count - (cluster_count * cluster_group_count);
        std.debug.assert(cluster_with_larger_size_count <= cluster_count);
        var cluster_a_center: Coordinate = undefined;
        var cluster_b_center: Coordinate = undefined;
        var pair_index: usize = 0;
        for (0..cluster_with_larger_size_count) |_| {
            cluster_a_center.randomize(rand);
            cluster_b_center.randomize(rand);
            for (0..larger_cluster_group_count) |_| {
                pair.randomize_cluster(rand, cluster_a_center, cluster_b_center, cluster_radius);
                total += haversine_formula.referenceHaversine(pair.a.x, pair.a.y, pair.b.x, pair.b.y, haversine_formula.default_earth_radius);
                try buffered_writer_writer.print("\t", .{});
                try pair.print(buffered_writer_writer);
                if (pair_index < pair_count - 1) {
                    try buffered_writer_writer.print(",\n", .{});
                }
                pair_index += 1;
            }
        }
        for (cluster_with_larger_size_count..cluster_count) |_| {
            cluster_a_center.randomize(rand);
            cluster_b_center.randomize(rand);
            for (0..cluster_group_count) |_| {
                pair.randomize_cluster(rand, cluster_a_center, cluster_b_center, cluster_radius);
                total += haversine_formula.referenceHaversine(pair.a.x, pair.a.y, pair.b.x, pair.b.y, haversine_formula.default_earth_radius);
                try buffered_writer_writer.print("\t", .{});
                try pair.print(buffered_writer_writer);
                if (pair_index < pair_count - 1) {
                    try buffered_writer_writer.print(",\n", .{});
                }
                pair_index += 1;
            }
        }
    }

    try buffered_writer_writer.print("\n]}}", .{});

    std.debug.print("Method: {s}\n", .{if (mode == .uniform) "uniform" else "cluster"});
    if (mode == .cluster) {
        if (cluster_with_larger_size_count == 0) {
            std.debug.print("\t{d} clusters of {d}\n", .{ cluster_count, cluster_group_count });
        } else {
            std.debug.print("\t{d} clusters of {d} AND {d} clusters of {d}\n", .{
                cluster_with_larger_size_count,
                larger_cluster_group_count,
                cluster_count - cluster_with_larger_size_count,
                cluster_group_count,
            });
        }
    }
    std.debug.print("Random seed: {d}\n", .{random_seed});
    std.debug.print("Pair count: {d}\n", .{pair_count});
    const average = total / @as(f64, @floatFromInt(pair_count));
    std.debug.print("Expected sum: {d}\n", .{average});
}
