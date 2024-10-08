const std = @import("std");
const Simulator = @import("Simulator.zig");
const Instruction = @import("Instruction.zig");
const Decoder = @import("Decoder.zig");
const ArrayListHelpers = @import("ArrayListHelpers.zig");
const Context = @import("Context.zig");

fn printLabel(writer: std.fs.File.Writer, byte_index: usize, next_label_index: *usize, labels: std.ArrayList(usize)) !void {
    if (next_label_index.* < labels.items.len) {
        const label_bytes = labels.items[next_label_index.*];
        std.debug.assert(byte_index <= label_bytes);
        if (byte_index == label_bytes) {
            try writer.print("test_label{d}:\n", .{next_label_index.*});
            next_label_index.* += 1;
        }
    }
}

fn print(writer: std.fs.File.Writer, instruction: Instruction.Instruction) !void {
    var operand_buffer: [2][32]u8 = undefined;
    const operand_1_label = Instruction.getOperandLabel(instruction.operand[0], &operand_buffer[0]);
    const instruction_type_string = Instruction.getInstructionTypeString(instruction.type);
    if (instruction.operand[1].type == .none) {
        try writer.print("{s} {s}", .{
            instruction_type_string,
            operand_1_label,
        });
    } else {
        if (instruction.operand[0].type == .memory) {
            try writer.print("{s} {s} {s}, {s}", .{
                instruction_type_string,
                if (instruction.wide) "word" else "byte",
                operand_1_label,
                Instruction.getOperandLabel(instruction.operand[1], &operand_buffer[1]),
            });
        } else {
            try writer.print("{s} {s}, {s}", .{
                instruction_type_string,
                operand_1_label,
                Instruction.getOperandLabel(instruction.operand[1], &operand_buffer[1]),
            });
        }
    }
}

fn printWithLabels(writer: std.fs.File.Writer, instruction: Instruction.Instruction, byte_index: usize, labels: std.ArrayList(usize)) !void {
    const maybe_jump_ip_inc8 = Instruction.getJumpIpInc8(instruction);
    if (maybe_jump_ip_inc8) |jump_ip_inc8| {
        const label_byte_index: usize = @as(usize, @intCast(@as(isize, @intCast(byte_index)) + jump_ip_inc8)) + instruction.size;
        const index: usize = ArrayListHelpers.findValueIndex(labels, label_byte_index).?;
        try writer.print("{s} test_label{d}", .{Instruction.getInstructionTypeString(instruction.type), index});
    } else {
        try print(writer, instruction);
    }
}

fn decodeAndPrintAll(allocator: std.mem.Allocator, writer: std.fs.File.Writer, context: *Context.Context) !void {
    var instructions = try std.ArrayList(Instruction.Instruction).initCapacity(allocator, context.program_size / 2);
    defer instructions.deinit();

    var labels = std.ArrayList(usize).init(allocator);
    defer labels.deinit();

    while (context.register.named_word.ip < context.program_size) {
        const instruction = Decoder.decode(context).?;
        try instructions.append(instruction);
        context.register.named_word.ip += instruction.size;

        const maybe_jump_ip_inc8 = Instruction.getJumpIpInc8(instruction);
        if (maybe_jump_ip_inc8) |jump_ip_inc8| {
            // TODO(TB): consider overflow
            const jump_byte: usize = @as(usize, @intCast(@as(isize, @intCast(context.register.named_word.ip)) + jump_ip_inc8));
            try ArrayListHelpers.insertSortedSetArrayList(&labels, jump_byte);
        }
    }

    _ = try writer.write("\nbits 16\n\n");

    var byte_index: usize = 0;
    var next_label_index: usize = 0;
    for (instructions.items) |instruction| {
        try printLabel(writer, byte_index, &next_label_index, labels);

        try printWithLabels(writer, instruction, byte_index, labels);
        try writer.print("\n", .{});

        byte_index += instruction.size;
    }
    try printLabel(writer, byte_index, &next_label_index, labels);
}

fn getEAClocks(mem: Instruction.Memory) u8 {
    if (mem.reg[0].index == .none) {
        // displacement only
        std.debug.assert(mem.reg[1].index == .none);
        return 6;
    } else {
        if (mem.reg[1].index == .none) {
            if (mem.displacement == 0) {
                // base or index only
                return 5;
            } else {
                // displacement + base or index
                return 9;
            }
        } else {
            if (mem.displacement == 0) {
                // base + index
                if (mem.reg[0].index == .bp) {
                    if (mem.reg[1].index == .di) {
                        // bp + di
                        return 7;
                    } else {
                        // bp + si
                        std.debug.assert(mem.reg[1].index == .si);
                        return 8;
                    }
                } else {
                    std.debug.assert(mem.reg[0].index == .b and mem.reg[0].offset == .none and mem.reg[0].size == .word);
                    if (mem.reg[1].index == .si) {
                        // bx + si
                        return 7;
                    } else {
                        // bx + di
                        std.debug.assert(mem.reg[1].index == .di);
                        return 8;
                    }
                }
            } else {
                // displacement + base + index
                if (mem.reg[0].index == .bp) {
                    if (mem.reg[1].index == .di) {
                        // bp + di + disp
                        return 11;
                    } else {
                        // bp + si + disp
                        std.debug.assert(mem.reg[1].index == .si);
                        return 12;
                    }
                } else {
                    std.debug.assert(mem.reg[0].index == .b and mem.reg[0].offset == .none and mem.reg[0].size == .word);
                    if (mem.reg[1].index == .si) {
                        // bx + si + disp
                        return 11;
                    } else {
                        // bx + di + disp
                        std.debug.assert(mem.reg[1].index == .di);
                        return 12;
                    }
                }
            }
        }
    }
}

fn getClocks(instruction: Instruction.Instruction) struct { u8, u8 } {
    switch (instruction.type) {
        .mov => {
            switch (instruction.operand[0].type) {
                .register => |reg_a| {
                    switch (instruction.operand[1].type) {
                        .register => {
                            return .{ 2, 0 };
                        },
                        .memory => |mem_b| {
                            if (reg_a.index == .a) {
                                // NOTE(TB): this does not have ea for some reason, even though it uses memory
                                return .{ 10, 0 };
                            }

                            return .{ 8, getEAClocks(mem_b) };
                        },
                        .immediate => {
                            return .{ 4, 0 };
                        },
                        else => unreachable,
                    }
                },
                .memory => |mem_a| {
                    switch (instruction.operand[1].type) {
                        .register => |reg_b| {
                            if (reg_b.index == .a) {
                                // NOTE(TB): this does not have ea for some reason, even though it uses memory
                                return .{ 10, 0 };
                            }
                            return .{ 9, getEAClocks(mem_a) };
                        },
                        .immediate => {
                            return .{ 10, getEAClocks(mem_a) };
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
        .add, .sub => {
            switch (instruction.operand[0].type) {
                .register => {
                    switch (instruction.operand[1].type) {
                        .register => {
                            return .{ 3, 0 };
                        },
                        .memory => |mem_b| {
                            return .{ 9, getEAClocks(mem_b) };
                        },
                        .immediate => {
                            return .{ 4, 0 };
                        },
                        else => unreachable,
                    }
                },
                .memory => |mem_a| {
                    switch (instruction.operand[1].type) {
                        .register => {
                            return .{ 16, getEAClocks(mem_a) };
                        },
                        .immediate => {
                            return  .{ 17, getEAClocks(mem_a) };
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
        .cmp => {
            switch (instruction.operand[0].type) {
                .register => {
                    switch (instruction.operand[1].type) {
                        .register => {
                            return .{ 3, 0 };
                        },
                        .memory => |mem_b| {
                            return .{ 9, getEAClocks(mem_b) };
                        },
                        .immediate => {
                            return .{ 4, 0 };
                        },
                        else => unreachable,
                    }
                },
                .memory => {
                    switch (instruction.operand[1].type) {
                        .register => {
                            return .{ 9, 0 };
                        },
                        .immediate => {
                            return .{ 10, 0 };
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

fn getClocksString(instruction: Instruction.Instruction, clocks: *u64, buffer: []u8) ![]u8 {
    const base_clocks, const ea_clocks = getClocks(instruction);
    const total = base_clocks + ea_clocks;
    clocks.* += total;

    if (ea_clocks != 0) {
        return std.fmt.bufPrint(buffer, "+{d} = {d} ({d} + {d}ea)", .{total, clocks.*, base_clocks, ea_clocks});
    }

    return std.fmt.bufPrint(buffer, "+{d} = {d}", .{total, clocks.*});
}

fn simulateAndPrintAll(writer: std.fs.File.Writer, context: *Context.Context, dump: bool, print_clocks: bool) !void {
    var clocks: u64 = 0;
    _ = try writer.print("\n", .{});
    while (context.register.named_word.ip < context.program_size) {
        const instruction = Decoder.decode(context).?;
        try print(writer, instruction);
        const flags_before = context.flags;
        const registers_before = context.register;
        _ = try writer.print(" ;", .{});

        if (print_clocks) {
            var clocks_string_buffer: [64]u8 = undefined;
            _ = try writer.print(" Clocks: {s} |", .{try getClocksString(instruction, &clocks, &clocks_string_buffer)});
        }

        Simulator.simulateInstruction(instruction, context);
        try printRegistersThatChangedShort(writer, registers_before, context.register);
        if (flags_before != context.flags) {
            var flags_before_buffer: [@typeInfo(Simulator.FlagBitIndex).Enum.fields.len]u8 = undefined;
            const flags_before_string = Simulator.printFlags(flags_before, &flags_before_buffer);
            var flags_after_buffer: [@typeInfo(Simulator.FlagBitIndex).Enum.fields.len]u8 = undefined;
            const flags_after_string = Simulator.printFlags(context.flags, &flags_after_buffer);
            _ = try writer.print(" flags:{s}->{s}", .{flags_before_string, flags_after_string});
        }
        _ = try writer.print("\n", .{});
    }
    _ = try writer.print("\n", .{});
    try printRegisters(writer, context);

    if (Simulator.hasAtLeastOneFlagSet(context.flags)) {
        var flags_buffer: [@typeInfo(Simulator.FlagBitIndex).Enum.fields.len]u8 = undefined;
        const flags = Simulator.printFlags(context.flags, &flags_buffer);
        _ = try writer.print(";   flags: {s}\n", .{flags});
    }

    if (dump) {
        const file = try std.fs.cwd().createFile(
            "sim8086_memory.txt",
            .{ .read = true },
        );
        defer file.close();

        const bytes_written = try file.writeAll(&context.memory);
        _ = bytes_written;
    }
}

fn printRegisters(writer: std.fs.File.Writer, context: *const Context.Context) !void {
    _ = try writer.print("; Final registers:\n", .{});
    if (context.register.named_word.ax != 0) {
        _ = try writer.print(";      ax: 0x{x:0>4} ({0d})\n", .{context.register.named_word.ax});
    }
    if (context.register.named_word.bx != 0) {
        _ = try writer.print(";      bx: 0x{x:0>4} ({0d})\n", .{context.register.named_word.bx});
    }
    if (context.register.named_word.cx != 0) {
        _ = try writer.print(";      cx: 0x{x:0>4} ({0d})\n", .{context.register.named_word.cx});
    }
    if (context.register.named_word.dx != 0) {
        _ = try writer.print(";      dx: 0x{x:0>4} ({0d})\n", .{context.register.named_word.dx});
    }
    if (context.register.named_word.sp != 0) {
        _ = try writer.print(";      sp: 0x{x:0>4} ({0d})\n", .{context.register.named_word.sp});
    }
    if (context.register.named_word.bp != 0) {
        _ = try writer.print(";      bp: 0x{x:0>4} ({0d})\n", .{context.register.named_word.bp});
    }
    if (context.register.named_word.si != 0) {
        _ = try writer.print(";      si: 0x{x:0>4} ({0d})\n", .{context.register.named_word.si});
    }
    if (context.register.named_word.di != 0) {
        _ = try writer.print(";      di: 0x{x:0>4} ({0d})\n", .{context.register.named_word.di});
    }
    if (context.register.named_word.cs != 0) {
        _ = try writer.print(";      cs: 0x{x:0>4} ({0d})\n", .{context.register.named_word.cs});
    }
    if (context.register.named_word.es != 0) {
        _ = try writer.print(";      es: 0x{x:0>4} ({0d})\n", .{context.register.named_word.es});
    }
    if (context.register.named_word.ss != 0) {
        _ = try writer.print(";      ss: 0x{x:0>4} ({0d})\n", .{context.register.named_word.ss});
    }
    if (context.register.named_word.ds != 0) {
        _ = try writer.print(";      ds: 0x{x:0>4} ({0d})\n", .{context.register.named_word.ds});
    }
    _ = try writer.print(";      ip: 0x{x:0>4} ({0d})\n", .{context.register.named_word.ip});
}

fn printRegistersThatChangedShort(writer: std.fs.File.Writer, registers_before: Context.Registers, registers: Context.Registers) !void {
    if (registers_before.named_word.ax != registers.named_word.ax) {
        _ = try writer.print(" ax:0x{x}->0x{x}", .{registers_before.named_word.ax, registers.named_word.ax});
    }
    if (registers_before.named_word.bx != registers.named_word.bx) {
        _ = try writer.print(" bx:0x{x}->0x{x}", .{registers_before.named_word.bx, registers.named_word.bx});
    }
    if (registers_before.named_word.cx != registers.named_word.cx) {
        _ = try writer.print(" cx:0x{x}->0x{x}", .{registers_before.named_word.cx, registers.named_word.cx});
    }
    if (registers_before.named_word.dx != registers.named_word.dx) {
        _ = try writer.print(" dx:0x{x}->0x{x}", .{registers_before.named_word.dx, registers.named_word.dx});
    }
    if (registers_before.named_word.sp != registers.named_word.sp) {
        _ = try writer.print(" sp:0x{x}->0x{x}", .{registers_before.named_word.sp, registers.named_word.sp});
    }
    if (registers_before.named_word.bp != registers.named_word.bp) {
        _ = try writer.print(" bp:0x{x}->0x{x}", .{registers_before.named_word.bp, registers.named_word.bp});
    }
    if (registers_before.named_word.si != registers.named_word.si) {
        _ = try writer.print(" si:0x{x}->0x{x}", .{registers_before.named_word.si, registers.named_word.si});
    }
    if (registers_before.named_word.di != registers.named_word.di) {
        _ = try writer.print(" di:0x{x}->0x{x}", .{registers_before.named_word.di, registers.named_word.di});
    }
    if (registers_before.named_word.ip != registers.named_word.ip) {
        _ = try writer.print(" ip:0x{x}->0x{x}", .{registers_before.named_word.ip, registers.named_word.ip});
    }
    if (registers_before.named_word.cs != registers.named_word.cs) {
        _ = try writer.print(" cs:0x{x}->0x{x}", .{registers_before.named_word.cs, registers.named_word.cs});
    }
    if (registers_before.named_word.es != registers.named_word.es) {
        _ = try writer.print(" es:0x{x}->0x{x}", .{registers_before.named_word.es, registers.named_word.es});
    }
    if (registers_before.named_word.ss != registers.named_word.ss) {
        _ = try writer.print(" ss:0x{x}->0x{x}", .{registers_before.named_word.ss, registers.named_word.ss});
    }
    if (registers_before.named_word.ds != registers.named_word.ds) {
        _ = try writer.print(" ds:0x{x}->0x{x}", .{registers_before.named_word.ds, registers.named_word.ds});
    }
}

const Args = struct {
    file_name: []u8,
    action: union(enum) {
        exec: struct {
            dump: bool,
            print_clocks: bool,
        },
        decode: void,
    },
};

pub fn run(args: Args) !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = allocator.allocator();
    const file = try std.fs.cwd().openFile(args.file_name, .{});
    // TODO(TB): use buffered writer
    //var bw = std.io.bufferedWriter(out);
    //const writer = bw.writer();
    //try bw.flush(); // don't forget to flush!
    const out = std.io.getStdOut().writer();
    var context: *Context.Context = try gpa.create(Context.Context);
    defer gpa.destroy(context);
    context.init();
    context.program_size = @intCast(try file.read(&context.memory));

    switch (args.action) {
        .exec => |extra_args| {
            try simulateAndPrintAll(out, context, extra_args.dump, extra_args.print_clocks);
        },
        .decode => {
            try decodeAndPrintAll(gpa, out, context);
        },
    }
}
