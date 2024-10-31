const std = @import("std");
const timer = @import("timer.zig");
const ProfilerConfig = @import("root").ProfilerConfig;

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
    new_block.start_time = timer.time();
}

pub fn endBlock() void {
    if (comptime !enable) {
        return;
    }

    std.debug.assert(state.stack.items.len > 0);
    const anchor = state.stack.pop();
    // if this was at the bottom of the stack, it must be root tag
    std.debug.assert(state.stack.items.len > 0 or anchor.tag == .root);
    const duration = timer.time() - anchor.start_time;
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
        const ns = timer.toNs(root_duration);
        const s = timer.nsToS(ns);
        std.debug.print("{s} time: {d}s ({d}ns)\n", .{name, s, ns});
    }
    for (1..state.blocks.len) |i| {
        const name = getProfileTagName(@enumFromInt(i));
        const duration = state.blocks[i].duration;
        const ns = timer.toNs(duration);
        const s = timer.nsToS(ns);
        std.debug.print("{s} time: {d}s ({d}ns) ({d}%)\n", .{name, s, ns, timer.percentage(duration, root_duration)});
    }
}
