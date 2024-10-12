const std = @import("std");

const Self = @This();

pub const HashMapContext = struct {
    pub fn eql(_: HashMapContext, a: Self, b: Self) bool {
        return Self.equal(&a, &b);
    }

    pub fn hash(_: HashMapContext, x: Self) u64 {
        return x.hash();
    }
};

type: union(enum) {
    reference_string: [*]const u8,
    small_string: [32]u8,
    large_string: [*]u8,
},
len: usize,

pub fn create(allocator: std.mem.Allocator, data: []const u8) !Self {
    var result: Self = .{
        .len = data.len,
        .type = undefined,
    };
    if (data.len < 32) {
        result.type = .{ .small_string = undefined };
        @memcpy(result.type.small_string[0..result.len], data);
    } else {
        const memory = try allocator.alloc(u8, result.len);
        result.type = .{ .large_string = memory.ptr };
        @memcpy(result.type.large_string[0..result.len], data);
    }
    return result;
}

pub fn reference(data: []const u8) Self {
    return .{
        .type = .{ .reference_string = data.ptr },
        .len = data.len,
    };
}

pub fn equal(a: *const Self, b: *const Self) bool {
    return a.len == b.len and std.mem.eql(u8, a.getBufferConst()[0..a.len], b.getBufferConst()[0..b.len]);
}

pub fn hash(self: *const Self) u64 {
    return std.hash_map.hashString(self.getBufferConst()[0..self.len]);
}

pub fn getBuffer(self: *Self) []u8 {
    return switch (self.type) {
        .small_string => |*data| data[0..self.len],
        .large_string, .reference_string => |data| data[0..self.len],
    };
}

pub fn getBufferConst(self: *const Self) []const u8 {
    return switch (self.type) {
        .small_string => |*data| data[0..self.len],
        .large_string, .reference_string => |data| data[0..self.len],
    };
}

// TODO(TB): should this be on const?
pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
    switch (self.type) {
        .large_string => |data| allocator.free(data[0..self.len]),
        else => {},
    }
}

// NOTE(TB): used to remove ownership of the data so that deinit will not do anthing
pub fn release(self: *Self) void {
    self.type = .{ .small_string = undefined };
    self.len = 0;
}
