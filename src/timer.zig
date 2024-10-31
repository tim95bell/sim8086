const std = @import("std");
const mach_time = @cImport({
    @cInclude("mach/mach_time.h");
});

pub const ProfileTag = enum {
    root,
    haversine_process,
    read_file,
    parse_json,
    process,
    deinit_json,
    deinit_file,

    const count = @typeInfo(ProfileTag).Enum.fields.len;
};

pub const Block = struct {
    duration: u64,
    child_duration: u64,
};

pub const Anchor = struct {
    start_time: u64,
    tag: ProfileTag,
};

pub const profile_tag_to_name: [ProfileTag.count][]const u8 = .{
    "total",
    "haversine process",
    "read file",
    "parse json",
    "process",
    "deinit json",
    "deinit file",
};

pub const ns_in_s = 1_000_000_000;

// TODO(TB): will this memory always be zero initialized?
var blocks: [ProfileTag.count]Block = undefined;
var stack: std.ArrayList(Anchor) = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    stack = @TypeOf(stack).initCapacity(allocator, 32) catch {
        std.debug.print("ERROR: Profiler failed to initialise\n", .{});
        return;
    };
}

pub fn deinit() void {
    stack.deinit();
}

pub fn startBlock(tag: ProfileTag) void {
    if (comptime std.debug.runtime_safety) {
        if (tag == .root) {
            if (stack.items.len == 0) {
                // TODO(TB): do this with std.mem.eql
                for (0..blocks.len) |i| {
                    std.debug.assert(blocks[i].duration == 0);
                    std.debug.assert(blocks[i].child_duration == 0);
                }
            }
        } else {
            std.debug.assert(stack.items.len > 0);
        }
    }
    const new_block = stack.addOne() catch {
        std.debug.print("ERROR: Profiler failed to add block \"{s}\"\n", .{profile_tag_to_name[@intFromEnum(tag)]});
        return;
    };
    new_block.tag = tag;
    new_block.start_time = time();
}

pub fn endBlock() void {
    std.debug.assert(stack.items.len > 0);
    const anchor = stack.pop();
    // if this was at the bottom of the stack, it must be root tag
    std.debug.assert(stack.items.len > 0 or anchor.tag == .root);
    const duration = time() - anchor.start_time;
    blocks[@intFromEnum(anchor.tag)].duration += duration;
    if (stack.items.len > 0) {
        const parent_anchor = stack.getLast();
        blocks[@intFromEnum(parent_anchor.tag)].child_duration += duration;
    }
}

pub fn print() void {
    const root_duration = blocks[0].duration;
    {
        const name = profile_tag_to_name[0];
        const ns = toNs(root_duration);
        const s = nsToS(ns);
        std.debug.print("{s} time: {d}s ({d}ns)\n", .{name, s, ns});
    }
    for (1..blocks.len) |i| {
        const name = profile_tag_to_name[i];
        const duration = blocks[i].duration;
        const ns = toNs(duration);
        const s = nsToS(ns);
        std.debug.print("{s} time: {d}s ({d}ns) ({d}%)\n", .{name, s, ns, percentage(duration, root_duration)});
    }
}

pub fn percentage(a: u64, b: u64) f64 {
    return (@as(f64, @floatFromInt(a)) / @as(f64, @floatFromInt(b))) * 100;
}

pub fn toNsRatio() f64 {
    var info: mach_time.mach_timebase_info_data_t = undefined;
    _ = mach_time.mach_timebase_info(&info);
    return @as(f64, @floatFromInt(info.numer)) / @as(f64, @floatFromInt(info.denom));
}

pub fn toSRatio() f64 {
    return toNsRatio() / ns_in_s;
}

pub fn time() u64 {
    return mach_time.mach_absolute_time();
}

pub fn toNs(x: u64) f64 {
    return @as(f64, @floatFromInt(x)) * toNsRatio();
}

pub fn nsToS(x: f64) f64 {
    return x / ns_in_s;
}

pub fn toS(x: u64) f64 {
    return @as(f64, @floatFromInt(x)) * toSRatio();
}

pub fn estimateCpuFrequency() usize {
    const start_time = time();
    var diff: u64 = 0;
    while (toNs(diff) < ns_in_s) {
        diff = time() - start_time;
    }
    return diff;
}
