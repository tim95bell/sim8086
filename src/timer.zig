const std = @import("std");
const ProfilerConfig = @import("root").ProfilerConfig;
const mach_time = @cImport({
    @cInclude("mach/mach_time.h");
});

const enable = ProfilerConfig.enable;
const ProfileTag = if (enable) ProfilerConfig.ProfileTag else enum{};
const profile_tag_count = @typeInfo(ProfileTag).Enum.fields.len;
const getProfileTagName = if (enable) ProfilerConfig.getProfileTagName else void;

const State = struct {
    // TODO(TB): will this memory always be zero initialized?
    blocks: [profile_tag_count]Block,
    stack: std.ArrayList(Anchor),
};

pub const Block = struct {
    duration: u64,
    child_duration: u64,
};

pub const Anchor = struct {
    start_time: u64,
    tag: ProfileTag,
};

var state: if (enable) State else void = undefined;

pub const ns_in_s = 1_000_000_000;

pub fn init(allocator: std.mem.Allocator) void {
    if (comptime enable) {
        state.stack = @TypeOf(state.stack).initCapacity(allocator, 32) catch {
            std.debug.print("ERROR: Profiler failed to initialise\n", .{});
            return;
        };
    }
}

pub fn deinit() void {
    if (comptime enable) {
        state.stack.deinit();
    }
}

pub fn startBlock(tag: ProfileTag) void {
    if (comptime !enable) {
        return;
    }

    if (comptime std.debug.runtime_safety) {
        if (tag == .root) {
            if (state.stack.items.len == 0) {
                // TODO(TB): do this with std.mem.eql
                for (0..state.blocks.len) |i| {
                    std.debug.assert(state.blocks[i].duration == 0);
                    std.debug.assert(state.blocks[i].child_duration == 0);
                }
            }
        } else {
            std.debug.assert(state.stack.items.len > 0);
        }
    }
    const new_block = state.stack.addOne() catch {
        std.debug.print("ERROR: Profiler failed to add block \"{s}\"\n", .{getProfileTagName(tag)});
        return;
    };
    new_block.tag = tag;
    new_block.start_time = time();
}

pub fn endBlock() void {
    if (comptime !enable) {
        return;
    }

    std.debug.assert(state.stack.items.len > 0);
    const anchor = state.stack.pop();
    // if this was at the bottom of the stack, it must be root tag
    std.debug.assert(state.stack.items.len > 0 or anchor.tag == .root);
    const duration = time() - anchor.start_time;
    state.blocks[@intFromEnum(anchor.tag)].duration += duration;
    if (state.stack.items.len > 0) {
        const parent_anchor = state.stack.getLast();
        state.blocks[@intFromEnum(parent_anchor.tag)].child_duration += duration;
    }
}

pub fn print() void {
    if (comptime !enable) {
        return;
    }

    const root_duration = state.blocks[0].duration;
    {
        const name = getProfileTagName(@enumFromInt(0));
        const ns = toNs(root_duration);
        const s = nsToS(ns);
        std.debug.print("{s} time: {d}s ({d}ns)\n", .{name, s, ns});
    }
    for (1..state.blocks.len) |i| {
        const name = getProfileTagName(@enumFromInt(i));
        const duration = state.blocks[i].duration;
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
