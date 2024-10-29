const std = @import("std");
const mach_time = @cImport({
    @cInclude("mach/mach_time.h");
});

pub const ns_in_s = 1_000_000_000;

pub const Block = struct {
    // name is not owned by Block
    name: []const u8,
    start_time: u64,
    end_time: u64,
    children: std.ArrayList(@This()),

    pub fn init(self: *Block, allocator: std.mem.Allocator) void {
        self.name = "";
        self.start_time = 0;
        self.end_time = 0;
        self.children = @TypeOf(self.children).init(allocator);
    }

    pub fn initWithNameAndNow(self: *Block, allocator: std.mem.Allocator, name: []const u8) void {
        self.name = name;
        self.end_time = 0;
        self.children = @TypeOf(self.children).init(allocator);
        self.start_time = time();
    }

    pub fn deinit(self: *Block) void {
        for (self.children.items) |*child| {
            child.deinit();
        }
        self.children.deinit();
    }

    pub fn start(self: *Block) void {
        std.debug.assert(self.start_time == 0);
        self.start_time = time();
        std.debug.assert(self.start_time != 0);
    }

    pub fn end(self: *Block) void {
        std.debug.assert(self.end_time == 0);
        self.end_time = time();
        std.debug.assert(self.end_time != 0);
    }

    pub fn print(self: *const Block) void {
        std.debug.assert(self.start_time != 0);
        std.debug.assert(self.end_time != 0);
        std.debug.assert(self.name.len == 0);
        const duration = self.end_time - self.start_time;
        const ns = toNs(duration);
        const s = nsToS(ns);
        std.debug.print("profiling total time: {d}s ({d}ns)\n", .{s, ns});
        self.printChildren(duration, 0);
    }

    fn printChildren(self: *const Block, duration: u64, nested: u8) void {
        const children_nested = nested + 1;
        for (self.children.items) |*child| {
            child.printNested(duration, children_nested);
        }
    }

    fn printNested(self: *const Block, parent_duration: u64, nested: u8) void {
        std.debug.assert(self.end_time != 0);
        for (0..nested) |_| {
            std.debug.print("\t", .{});
        }
        const duration = self.end_time - self.start_time;
        const ns = toNs(duration);
        const s = nsToS(ns);
        std.debug.print("{s}: {d}s ({d}ns) ({d}%)\n", .{self.name, s, ns, percentage(duration, parent_duration)});
        self.printChildren(duration, nested);
    }
};

var root_block: Block = .{
    // TODO(TB): don't need a name
    .name = "",
    .start_time = 0,
    .end_time = 0,
    .children = undefined,
};

var blocks: std.ArrayList(*Block) = undefined;

pub fn deinit() void {
    blocks.deinit();
    root_block.deinit();
}

pub fn init(allocator: std.mem.Allocator) !void {
    std.debug.assert(root_block.start_time == 0);
    std.debug.assert(root_block.children.items.len == 0);
    std.debug.assert(blocks.items.len == 0);
    blocks = @TypeOf(blocks).init(allocator);
    const new_block: **Block = try blocks.addOne();
    new_block.* = &root_block;
    root_block.init(allocator);
    std.debug.assert(blocks.items.len == 1);
}

pub fn start() void {
    std.debug.assert(root_block.start_time == 0);
    std.debug.assert(root_block.children.items.len == 0);
    std.debug.assert(blocks.items.len == 1);
    std.debug.assert(blocks.getLast() == &root_block);
    root_block.start();
    std.debug.assert(root_block.start_time != 0);
}

pub fn startBlock(name: []const u8) void {
    std.debug.assert(blocks.items.len > 0);
    var new_block: *Block = blocks.getLast().children.addOne() catch unreachable;
    {
        const new_block_in_blocks: **Block = blocks.addOne() catch unreachable;
        new_block_in_blocks.* = new_block;
    }
    new_block.initWithNameAndNow(blocks.allocator, name);
}

pub fn endBlock() void {
    std.debug.assert(blocks.items.len > 1);
    blocks.getLast().end();
    _ = blocks.pop();
}

pub fn end() void {
    std.debug.assert(blocks.items.len == 1);
    root_block.end();
    _ = blocks.pop();
}

pub fn print() void {
    std.debug.assert(blocks.items.len == 0);
    root_block.print();
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
