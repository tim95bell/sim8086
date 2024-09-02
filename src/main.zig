const std = @import("std");

const Instruction = struct {
    address: u32,
    type: InstructionType,
    operand: [2]Operand,
    size: u8,
    wide: bool,
};

const InstructionType = enum {
    mov,
    add,
    sub,
    cmp,
    jnz,
    je,
    jl,
    jle,
    jb,
    jbe,
    jp,
    jo,
    js,
    jnl,
    jg,
    jnb,
    ja,
    jnp,
    jno,
    jns,
    loop,
    loopz,
    loopnz,
    jcxz,
};

const Operand = struct {
    const Type = enum {
        none,
        register,
        immediate,
        memory,
        relative_jump_displacement,
    };

    type: union(Type) {
        none: void,
        register: Register,
        immediate: u16,
        memory: Memory,
        relative_jump_displacement: i8,
    },
};

const Register = struct {
    index: RegisterIndex,
    offset: RegisterOffset,
    size: RegisterSize,
};

const Memory = struct {
    displacement: i16,
    // TODO(TB): displacement_size shouldnt really be here
    displacement_size: u8,
    reg: [2]Register,
};

const RegisterIndex = enum {
    a,
    b,
    c,
    d,
    sp,
    bp,
    si,
    di,
    none,
};

const RegisterOffset = enum(u8) {
    none = 0,
    byte = 1,
};

const RegisterSize = enum(u8) {
    byte = 1,
    word = 2,
};

fn getGeneralPurposeRegisterLabelLetter(reg: RegisterIndex) u8 {
    return switch (reg) {
        .a => 'a',
        .b => 'b',
        .c => 'c',
        .d => 'd',
        else => unreachable,
    };
}

fn getRegisterLabel(register: Register, buffer: []u8) []u8 {
    std.debug.assert(buffer.len >= 2);
    switch (register.index) {
        .a, .b, .c, .d => {
            buffer[0] = getGeneralPurposeRegisterLabelLetter(register.index);
            if (register.offset == .none) {
                if (register.size == .byte) {
                    buffer[1] = 'l';
                } else {
                    std.debug.assert(register.size == .word);
                    buffer[1] = 'x';
                }
            } else {
                std.debug.assert(register.offset == .byte);
                std.debug.assert(register.size == .byte);
                buffer[1] = 'h';
            }
        },
        .sp => {
            buffer[0] = 's';
            buffer[1] = 'p';
        },
        .bp => {
            buffer[0] = 'b';
            buffer[1] = 'p';
        },
        .si => {
            buffer[0] = 's';
            buffer[1] = 'i';
        },
        .di => {
            buffer[0] = 'd';
            buffer[1] = 'i';
        },
        .none => {
            return buffer[0..0];
        },
    }
    return buffer[0..2];
}

const al: Register = .{ .index = .a, .offset = .none, .size = .byte };
const bl: Register = .{ .index = .b, .offset = .none, .size = .byte };
const cl: Register = .{ .index = .c, .offset = .none, .size = .byte };
const dl: Register = .{ .index = .d, .offset = .none, .size = .byte };
const ah: Register = .{ .index = .a, .offset = .byte, .size = .byte };
const bh: Register = .{ .index = .b, .offset = .byte, .size = .byte };
const ch: Register = .{ .index = .c, .offset = .byte, .size = .byte };
const dh: Register = .{ .index = .d, .offset = .byte, .size = .byte };
const ax: Register = .{ .index = .a, .offset = .none, .size = .word };
const bx: Register = .{ .index = .b, .offset = .none, .size = .word };
const cx: Register = .{ .index = .c, .offset = .none, .size = .word };
const dx: Register = .{ .index = .d, .offset = .none, .size = .word };
const sp: Register = .{ .index = .sp, .offset = .none, .size = .word };
const bp: Register = .{ .index = .bp, .offset = .none, .size = .word };
const si: Register = .{ .index = .si, .offset = .none, .size = .word };
const di: Register = .{ .index = .di, .offset = .none, .size = .word };
const reg_field_encoding: [16]Register = .{
    al, cl, dl, bl, ah, ch, dh, bh, ax, cx, dx, bx, sp, bp, si, di
};

fn regFieldEncoding(w: u1, reg: u3) Register {
    return reg_field_encoding[@as(u4, w) << 3 | reg];
}

fn getOperandLabel(operand: Operand, buffer: []u8) []u8 {
    // TODO(TB): figure out the max length required here
    std.debug.assert(buffer.len >= 32);
    switch (operand.type) {
        .register => |data| {
            return getRegisterLabel(data, buffer);
        },
        .immediate => |data| {
            return std.fmt.bufPrint(buffer, "{d}", .{data}) catch unreachable;
        },
        .memory => |data| {
            if (data.reg[0].index == .none) {
                std.debug.assert(data.reg[1].index == .none);
                return std.fmt.bufPrint(buffer, "[{d}]", .{data.displacement}) catch unreachable;
            } else if (data.reg[1].index == .none) {
                var reg_label_buffer: [2]u8 = undefined;
                if (data.displacement == 0) {
                    // TODO(TB): is this legal? would it be signed then?
                    return std.fmt.bufPrint(buffer, "[{s}]", .{getRegisterLabel(data.reg[0], &reg_label_buffer)}) catch unreachable;
                } else {
                    const negative = data.displacement < 0;
                    return std.fmt.bufPrint(buffer, "[{s} {s} {d}]", .{
                        getRegisterLabel(data.reg[0], &reg_label_buffer),
                        if (negative) "-" else "+",
                        if (negative) data.displacement * -1 else data.displacement,
                    }) catch unreachable;
                }
            } else {
                var reg_label_buffer: [2][2]u8 = undefined;
                const reg_0_label = getRegisterLabel(data.reg[0], &reg_label_buffer[0]);
                const reg_1_label = getRegisterLabel(data.reg[1], &reg_label_buffer[1]);
                if (data.displacement == 0) {
                    return std.fmt.bufPrint(buffer, "[{s} + {s}]", .{
                        reg_0_label,
                        reg_1_label,
                    }) catch unreachable;
                } else {
                    const negative = data.displacement < 0;
                    return std.fmt.bufPrint(buffer, "[{s} + {s} {s} {d}]", .{
                        reg_0_label,
                        reg_1_label,
                        if (negative) "-" else "+",
                        if (negative) data.displacement * -1 else data.displacement,
                    }) catch unreachable;
                }
            }
        },
        .relative_jump_displacement => |data| {
            return std.fmt.bufPrint(buffer, "{d}", .{data}) catch unreachable;
        },
        .none => {
            return buffer[0..0];
        }
    }
}

fn getInstructionTypeString(instruction_type: InstructionType) []const u8 {
    return switch (instruction_type) {
        .mov => "mov",
        .add => "add",
        .sub => "sub",
        .cmp => "cmp",
        .jnz => "jnz",
        .je => "je",
        .jl => "jl",
        .jle => "jle",
        .jb => "jb",
        .jbe => "jbe",
        .jp => "jp",
        .jo => "jo",
        .js => "js",
        .jnl => "jnl",
        .jg => "jg",
        .jnb => "jnb",
        .ja => "ja",
        .jnp => "jnp",
        .jno => "jno",
        .jns => "jns",
        .loop => "loop",
        .loopz => "loopz",
        .loopnz => "loopnz",
        .jcxz => "jcxz",
    };
}

fn extractModRegRm(data: u8) struct { u2, u3, u3 } {
    // TODO(TB): try doing this with a packed struct
    return .{
        @intCast(data >> 6),
        @intCast((data >> 3) & 0b111),
        @intCast(data & 0b111),
    };
}

fn extractSignedWord(data: [*]const u8, wide: bool) i16 {
    return if (wide) @as(i16, data[0]) | @as(i16, @bitCast(@as(u16, data[1]) << 8)) else @as(i16, @as(i8, @bitCast(data[0])));
}

fn extractUnsignedWord(data: [*]const u8, wide: bool) u16 {
    return if (wide) data[0] | (@as(u16, data[1]) << 8) else data[0];
}

fn getJumpIpInc8(instruction: Instruction) ?i8 {
    return switch (instruction.type) {
        .jnz, .je, .jl, .jle, .jb, .jbe, .jp, .jo, .js,
        .jnl, .jg, .jnb, .ja, .jnp, .jno, .jns, .loop,
        .loopz, .loopnz, .jcxz => instruction.operand[0].type.relative_jump_displacement,
        else => null,
    };
}

fn insertSortedSetArrayList(xs: *std.ArrayList(usize), y: usize) !void {
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

fn findValueIndex(xs: std.ArrayList(usize), value: usize) ?usize {
    for (xs.items, 0..) |x, i| {
        if (x == value) {
            return i;
        }
    }
    return null;
}

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

const Context = struct {
    data: []const u8,
    index: usize,
};

fn decodeImmToReg(instruction_type: InstructionType, context: Context) Instruction {
    const w: u1 = @intCast((context.data[context.index] & 0b00001000) >> 3);
    var instruction: Instruction = .{
        .address = @intCast(context.index),
        .type = instruction_type,
        .operand = undefined,
        .size = 2 + @as(u8, w),
        .wide = w != 0,
    };
    instruction.operand[0] = .{
        .type = .{
            .register = regFieldEncoding(w, @intCast(context.data[context.index] & 0b00000111)),
        },
    };
    instruction.operand[1] = .{
        .type = .{
            .immediate = extractUnsignedWord(context.data.ptr + context.index + 1, w != 0),
        },
    };
    return instruction;
}

fn decodeAddSubCmpRegToFromRegMem(context: Context) Instruction {
    return decodeRegToFromRegMem(extractAddSubCmpType(@intCast((context.data[context.index] >> 3) & 0b00000111)), context);
}

fn decodeRegToFromRegMem(instruction_type: InstructionType, context: Context) Instruction {
    const d: bool = context.data[context.index] & 0b00000010 != 0;
    const w: u1 = @intCast(context.data[context.index] & 0b00000001);

    const mod, const reg, const rm = extractModRegRm(context.data[context.index + 1]);
    const displacement: [*]const u8 = context.data.ptr + context.index + 2;
    var instruction: Instruction = .{
        .type = instruction_type,
        .address = @intCast(context.index),
        .operand = undefined,
        .size = undefined,
        .wide = w != 0,
    };
    instruction.operand[if (d) 0 else 1] = .{ .type = .{ .register = regFieldEncoding(w, reg) } };
    const rm_operand_index: u1 = if (d) 1 else 0;
    if (mod == 0b11) {
        instruction.operand[rm_operand_index] = .{ .type = .{ .register = regFieldEncoding(w, rm) } };
        instruction.size = 2;
    } else {
        // mod = 00, 01, or 10
        instruction.operand[rm_operand_index] = .{
            .type = .{
                .memory = createMem(mod, rm, displacement),
            },
        };
        instruction.size = 2 + instruction.operand[rm_operand_index].type.memory.displacement_size;
    }
    return instruction;
}

fn extractAddSubCmpType(bits: u3) InstructionType {
    return switch (bits) {
        0b000 => .add,
        0b101 => .sub,
        0b111 => .cmp,
        else => unreachable,
    };
}

fn decodeAddSubCmpImmToAcc(context: Context) Instruction {
    const wide: bool = (context.data[context.index] & 0b1) != 0;
    var instruction: Instruction = .{
        .type = extractAddSubCmpType(@intCast((context.data[context.index] >> 3) & 0b00000111)),
        .address = @intCast(context.index),
        .operand = undefined,
        .size = if (wide) 3 else 2,
        .wide = wide,
    };
    instruction.operand[0].type = .{
        .register = .{
            .index = .a,
            .offset = .none,
            .size = if (wide) .word else .byte,
        },
    };
    instruction.operand[1].type = .{
        .immediate = extractUnsignedWord(context.data.ptr + context.index + 1, wide),
    };
    return instruction;
}

fn decodeAddSubCmpImmToRegMem(context: Context) Instruction {
    _, const reg, _ = extractModRegRm(context.data[context.index + 1]);
    const s: u1 = @intCast((context.data[context.index] & 0b10) >> 1);
    return decodeImmToRegMem(extractAddSubCmpType(reg), context, s);
}

fn decodeImmToRegMem(instruction_type: InstructionType, context: Context, s: u1) Instruction {
    const data = context.data;
    const i = context.index;
    const w: u1 = @intCast(data[i] & 0b1);
    const mod, const reg, const rm = extractModRegRm(data[i + 1]);
    std.debug.assert(reg == 0b000 or reg == 0b101 or reg == 0b111);
    const displacement_only = mod == 0b00 and rm == 0b110;
    const displacement_size: u8 = if (mod == 0b11) 0 else if (displacement_only) 2 else mod;
    const immediate_index_offset: u8 = 2 + displacement_size;
    const wide_immediate = s == 0 and w == 1;
    const immediate: u16 = extractUnsignedWord(data.ptr + i + immediate_index_offset, wide_immediate);

    var instruction: Instruction = .{
        .type = instruction_type,
        .address = @intCast(i),
        .operand = undefined,
        .size = undefined,
        // TODO(TB): instruction should be wide if w=1, w=1 && s=0 is only for data being 2 bytes?
        .wide = w != 0,
    };
    instruction.operand[1].type = .{
        .immediate = immediate,
    };
    if (mod == 0b11) {
        // imm to reg
        instruction.operand[0].type = .{
            .register = regFieldEncoding(w, rm),
        };
        instruction.size = if (wide_immediate) 4 else 3;
    } else {
        // imm to mem
        const displacement: [*]const u8 = context.data.ptr + context.index + 2;
        instruction.operand[0].type = .{
            .memory = createMem(mod, rm, displacement),
        };
        instruction.size = instruction.operand[0].type.memory.displacement_size + @as(u8, if (wide_immediate) 4 else 3);
    }
    return instruction;
}

fn createMem(mod: u2, rm: u3, displacement: [*]const u8) Memory {
    const displacement_only = mod == 0b00 and rm == 0b110;
    const displacement_size = if (displacement_only) 2 else if (mod == 0b11) 0 else mod;
    std.debug.assert(displacement_size == 0 or displacement_size == 1 or displacement_size == 2);
    var result: Memory = .{
        .displacement = if (displacement_size > 0) extractSignedWord(displacement, displacement_size == 2) else 0,
        .displacement_size = displacement_size,
        .reg = undefined,
    };
    result.reg[0].size = .word;
    result.reg[0].offset = .none;
    result.reg[1].size = .word;
    result.reg[1].offset = .none;
    switch (rm) {
        0b000 => {
            result.reg[0].index = .b;
            result.reg[1].index = .si;
        },
        0b001 => {
            result.reg[0].index = .b;
            result.reg[1].index = .di;
        },
        0b010 => {
            result.reg[0].index = .bp;
            result.reg[1].index = .si;
        },
        0b011 => {
            result.reg[0].index = .bp;
            result.reg[1].index = .di;
        },
        0b100 => {
            result.reg[0].index = .si;
            result.reg[1].index = .none;
        },
        0b101 => {
            result.reg[0].index = .di;
            result.reg[1].index = .none;
        },
        0b110 => {
            result.reg[0].index = if (mod == 0b00) .none else .bp;
            result.reg[1].index = .none;
        },
        0b111 => {
            result.reg[0].index = .b;
            result.reg[1].index = .none;
        },
    }
    return result;
}

fn decode(context: Context) ?Instruction {
    const data = context.data;
    const i = context.index;
    if ((data[i] & 0b11110000) == 0b10110000) {
        // mov imm to reg
        return decodeImmToReg(.mov, context);
    } else if ((data[i] & 0b11111100) == 0b10001000) {
        // mov reg to/from reg/mem
        return decodeRegToFromRegMem(.mov, context);
    } else if ((data[i] & 0b11111110) == 0b11000110) {
        // mov imm to reg/mem
        return decodeImmToRegMem(.mov, context, 0);
    } else if ((data[i] & 0b11111100) == 0b10100000) {
        // mov mem to/from acc
        const d: bool = data[i] & 0b00000010 == 0;
        const wide = data[i] & 0b1 != 0;

        var instruction: Instruction = .{
            .type = .mov,
            .address = @intCast(i),
            .operand = undefined,
            .size = 3,
            .wide = wide,
        };
        const mem_index: u8 = if (d) 1 else 0;
        const acc_index: u8 = if (d) 0 else 1;
        instruction.operand[acc_index].type = .{
            .register = .{
                .index = .a,
                .offset = .none,
                .size = if (wide) .word else .byte,
            },
        };
        instruction.operand[mem_index].type = .{
            .memory = .{
                .reg = undefined,
                // TODO(TB): displacement in this case should be unsigned?
                .displacement = extractSignedWord(data.ptr + i + 1, true),
                .displacement_size = 2,
            },
        };
        instruction.operand[mem_index].type.memory.reg[0].index = .none;
        instruction.operand[mem_index].type.memory.reg[1].index = .none;
        return instruction;
    } else if ((data[i] & 0b11000100) == 0b00000000) {
        // add/sub/cmp reg/mem to/from reg
        return decodeAddSubCmpRegToFromRegMem(context);
    } else if ((data[i] & 0b11111100) == 0b10000000) {
        // add/sub/cmp imm to reg/mem
        return decodeAddSubCmpImmToRegMem(context);
    } else if ((data[i] & 0b11000110) == 0b00000100) {
        // add/sub/cmp imm to acc
        return decodeAddSubCmpImmToAcc(context);
    } else if ((data[i] & 0b11110000) == 0b01110000) {
        // jnz, je, jnz, je, jl, jle, jb, jbe, jp, jo, js, jnl, jg, jnb, ja, jnp, jno, jns
        var instruction: Instruction = .{
            .type = switch (data[i] & 0b00001111) {
                0b0101 => .jnz,
                0b0100 => .je,
                0b1100 => .jl,
                0b1110 => .jle,
                0b0010 => .jb,
                0b0110 => .jbe,
                0b1010 => .jp,
                0b0000 => .jo,
                0b1000 => .js,
                0b1101 => .jnl,
                0b1111 => .jg,
                0b0011 => .jnb,
                0b0111 => .ja,
                0b1011 => .jnp,
                0b0001 => .jno,
                0b1001 => .jns,
                else => unreachable,
            },
            .address = @intCast(i),
            .operand = undefined,
            .size = 2,
            .wide = false,
        };
        instruction.operand[0].type = .{
            .relative_jump_displacement = @as(i8, @bitCast(data[i + 1])),
        };
        instruction.operand[1].type = .none;
        return instruction;
    } else if ((data[i] & 0b11111100) == 0b11100000) {
        // loop, loopz, loopnz, jcxz
        var instruction: Instruction = .{
            .type = switch (data[i] & 0b00000011) {
                0b10 => .loop,
                0b01 => .loopz,
                0b00 => .loopnz,
                0b11 => .jcxz,
                else => unreachable,
            },
            .address = @intCast(i),
            .operand = undefined,
            .size = 2,
            .wide = false,
        };
        instruction.operand[0].type = .{
            .relative_jump_displacement = @as(i8, @bitCast(data[i + 1])),
        };
        return instruction;
    } else {
        return null;
    }
}

fn print(writer: std.fs.File.Writer, instruction: Instruction) !void {
    var operand_buffer: [2][32]u8 = undefined;
    const operand_1_label = getOperandLabel(instruction.operand[0], &operand_buffer[0]);
    const instruction_type_string = getInstructionTypeString(instruction.type);
    if (instruction.operand[1].type == .none) {
        try writer.print("{s} {s}\n", .{
            instruction_type_string,
            operand_1_label,
        });
    } else {
        if (instruction.operand[0].type == .memory and instruction.operand[1].type == .immediate) {
            try writer.print("{s} {s} {s}, {s}\n", .{
                instruction_type_string,
                if (instruction.wide) "word" else "byte",
                operand_1_label,
                getOperandLabel(instruction.operand[1], &operand_buffer[1]),
            });
        } else {
            try writer.print("{s} {s}, {s}\n", .{
                instruction_type_string,
                operand_1_label,
                getOperandLabel(instruction.operand[1], &operand_buffer[1]),
            });
        }
    }
}

fn printWithLabels(writer: std.fs.File.Writer, instruction: Instruction, byte_index: usize, labels: std.ArrayList(usize)) !void {
    const maybe_jump_ip_inc8 = getJumpIpInc8(instruction);
    if (maybe_jump_ip_inc8) |jump_ip_inc8| {
        const label_byte_index: usize = @as(usize, @intCast(@as(isize, @intCast(byte_index)) + jump_ip_inc8)) + instruction.size;
        const index: usize = findValueIndex(labels, label_byte_index).?;
        try writer.print("{s} test_label{d}\n", .{getInstructionTypeString(instruction.type), index});
    } else {
        try print(writer, instruction);
    }
}

fn decodeAndPrintAll(allocator: std.mem.Allocator, writer: std.fs.File.Writer, data: []const u8) !void {
    var context: Context = .{ .data = data, .index = 0 };

    var instructions = try std.ArrayList(Instruction).initCapacity(allocator, data.len / 2);
    defer instructions.deinit();

    var labels = std.ArrayList(usize).init(allocator);
    defer labels.deinit();

    while (context.index < data.len) {
        const instruction = decode(context).?;
        try instructions.append(instruction);
        context.index += instruction.size;

        const maybe_jump_ip_inc8 = getJumpIpInc8(instruction);
        if (maybe_jump_ip_inc8) |jump_ip_inc8| {
            // TODO(TB): consider overflow
            const jump_byte: usize = @as(usize, @intCast(@as(isize, @intCast(context.index)) + jump_ip_inc8));
            try insertSortedSetArrayList(&labels, jump_byte);
        }
    }

    _ = try writer.write("\nbits 16\n\n");

    var byte_index: usize = 0;
    var next_label_index: usize = 0;
    for (instructions.items) |instruction| {
        try printLabel(writer, byte_index, &next_label_index, labels);

        try printWithLabels(writer, instruction, byte_index, labels);

        byte_index += instruction.size;
    }
    try printLabel(writer, byte_index, &next_label_index, labels);
}

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    if (args.len != 2) {
        @panic("you must provide exactly 1 command line argument, the name of the file to disassemble\n");
    }
    const file_name = args[1];
    const file = try std.fs.cwd().openFile(file_name, .{});
    const data = try file.readToEndAlloc(gpa, 1024 * 1024 * 1024);
    var out = std.io.getStdOut();
    const writer = out.writer();
    try decodeAndPrintAll(gpa, writer, data);
}
