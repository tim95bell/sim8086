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
        // TODO(TB): should there be immediate_8 and immediate_16?
        immediate: u16,
        memory: Memory,
        relative_jump_displacement: i8,
    },
};

const Register = struct {
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
    const none: Register = .{ .index = .none, .offset = .none, .size = .word };

    index: RegisterIndex,
    offset: RegisterOffset,
    size: RegisterSize,
};

const Memory = struct {
    // TODO(TB): should displacement be stored sepertely for word and byte?
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
    ip,
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
            // TODO(TB): getGeneralPurposeRegisterLabelLetter is doing duplicated worrk here
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
        .ip => {
            buffer[0] = 'i';
            buffer[1] = 'p';
        },
        .none => {
            return buffer[0..0];
        },
    }
    return buffer[0..2];
}

const reg_field_encoding: [16]Register = .{
    Register.al, Register.cl, Register.dl, Register.bl, Register.ah, Register.ch, Register.dh, Register.bh, Register.ax, Register.cx, Register.dx, Register.bx, Register.sp, Register.bp, Register.si, Register.di
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
                return std.fmt.bufPrint(buffer, "[{d}]", .{@as(u16, @bitCast(data.displacement))}) catch unreachable;
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
    memory: [1028 * 1028 * 1028]u8,
    program_size: u16,
    register: extern union {
        // change 9 to RegisterIndex.len
        named_word: extern struct {
            ax: u16,
            bx: u16,
            cx: u16,
            dx: u16,
            sp: u16,
            bp: u16,
            si: u16,
            di: u16,
            ip: u16,
        },
        named_byte: extern struct {
            al: u8,
            ah: u8,
            bl: u8,
            bh: u8,
            cl: u8,
            ch: u8,
            dl: u8,
            dh: u8,
        },
        byte: [@typeInfo(RegisterIndex).Enum.fields.len][2]u8,
        word: [@typeInfo(RegisterIndex).Enum.fields.len]u16,
    },

    fn init(self: *Context) void {
        self.memory = undefined;
        self.program_size = 0;
        self.register = undefined;

        self.register.byte[0][0] = 1;
        self.register.byte[0][1] = 2;
        self.register.byte[1][0] = 3;
        self.register.byte[1][1] = 4;
        self.register.byte[2][0] = 5;
        self.register.byte[2][1] = 6;
        self.register.byte[3][0] = 7;
        self.register.byte[3][1] = 8;
        self.register.byte[4][0] = 9;
        self.register.byte[4][1] = 10;
        self.register.byte[5][0] = 11;
        self.register.byte[5][1] = 12;
        self.register.byte[6][0] = 13;
        self.register.byte[6][1] = 14;
        self.register.byte[7][0] = 15;
        self.register.byte[7][1] = 16;
        self.register.byte[8][0] = 17;
        self.register.byte[8][1] = 18;

        std.debug.assert(self.register.byte[0][0] == self.register.named_byte.al);
        std.debug.assert(self.register.byte[0][1] == self.register.named_byte.ah);
        std.debug.assert(@as(u16, self.register.byte[0][0]) | (@as(u16, self.register.byte[0][1]) << 8) == self.register.named_word.ax);
        std.debug.assert(@as(u16, self.register.byte[0][0]) | (@as(u16, self.register.byte[0][1]) << 8) == self.register.word[0]);

        std.debug.assert(self.register.byte[1][0] == self.register.named_byte.bl);
        std.debug.assert(self.register.byte[1][1] == self.register.named_byte.bh);
        std.debug.assert(@as(u16, self.register.byte[1][0]) | (@as(u16, self.register.byte[1][1]) << 8) == self.register.named_word.bx);
        std.debug.assert(@as(u16, self.register.byte[1][0]) | (@as(u16, self.register.byte[1][1]) << 8) == self.register.word[1]);

        std.debug.assert(self.register.byte[2][0] == self.register.named_byte.cl);
        std.debug.assert(self.register.byte[2][1] == self.register.named_byte.ch);
        std.debug.assert(@as(u16, self.register.byte[2][0]) | (@as(u16, self.register.byte[2][1]) << 8) == self.register.named_word.cx);
        std.debug.assert(@as(u16, self.register.byte[2][0]) | (@as(u16, self.register.byte[2][1]) << 8) == self.register.word[2]);

        std.debug.assert(self.register.byte[3][0] == self.register.named_byte.dl);
        std.debug.assert(self.register.byte[3][1] == self.register.named_byte.dh);
        std.debug.assert(@as(u16, self.register.byte[3][0]) | (@as(u16, self.register.byte[3][1]) << 8) == self.register.named_word.dx);
        std.debug.assert(@as(u16, self.register.byte[3][0]) | (@as(u16, self.register.byte[3][1]) << 8) == self.register.word[3]);

        std.debug.assert(@as(u16, self.register.byte[4][0]) | (@as(u16, self.register.byte[4][1]) << 8) == self.register.named_word.sp);
        std.debug.assert(@as(u16, self.register.byte[4][0]) | (@as(u16, self.register.byte[4][1]) << 8) == self.register.word[4]);

        std.debug.assert(@as(u16, self.register.byte[5][0]) | (@as(u16, self.register.byte[5][1]) << 8) == self.register.named_word.bp);
        std.debug.assert(@as(u16, self.register.byte[5][0]) | (@as(u16, self.register.byte[5][1]) << 8) == self.register.word[5]);

        std.debug.assert(@as(u16, self.register.byte[6][0]) | (@as(u16, self.register.byte[6][1]) << 8) == self.register.named_word.si);
        std.debug.assert(@as(u16, self.register.byte[6][0]) | (@as(u16, self.register.byte[6][1]) << 8) == self.register.word[6]);

        std.debug.assert(@as(u16, self.register.byte[7][0]) | (@as(u16, self.register.byte[7][1]) << 8) == self.register.named_word.di);
        std.debug.assert(@as(u16, self.register.byte[7][0]) | (@as(u16, self.register.byte[7][1]) << 8) == self.register.word[7]);

        std.debug.assert(@as(u16, self.register.byte[8][0]) | (@as(u16, self.register.byte[8][1]) << 8) == self.register.named_word.ip);
        std.debug.assert(@as(u16, self.register.byte[8][0]) | (@as(u16, self.register.byte[8][1]) << 8) == self.register.word[8]);

        // TODO(TB): zero out memory?
        @memset(&self.register.word, 0);
    }
};

fn getRegisterSlice(register: Register, context: *const Context) []u8 {
    std.debug.assert((register.offset != .byte) or (register.size == .byte));
    std.debug.assert((register.index != .sp and register.index != .bp and register.index != .si and register.index != .di) or (register.size == .word and register.offset == .none));
    return context.register.byte[@intFromEnum(register.index)][@intFromEnum(register.offset)..@intFromEnum(register.offset) + @intFromEnum(register.size)];
}

fn decodeImmToReg(instruction_type: InstructionType, context: *const Context) Instruction {
    const data = context.memory[0..];
    const index = context.register.named_word.ip;
    const w: u1 = @intCast((data[index] & 0b00001000) >> 3);
    return .{
        .address = @intCast(index),
        .type = instruction_type,
        .operand = .{
            .{
                .type = .{
                    .register = regFieldEncoding(w, @intCast(data[index] & 0b00000111)),
                },
            },
            .{
                .type = .{
                    .immediate = extractUnsignedWord(data.ptr + index + 1, w != 0),
                },
            }
        },
        .size = 2 + @as(u8, w),
        .wide = w != 0,
    };
}

fn decodeAddSubCmpRegToFromRegMem(context: *const Context) Instruction {
    const data = context.memory[0..];
    const index = context.register.named_word.ip;
    return decodeRegToFromRegMem(extractAddSubCmpType(@intCast((data[index] >> 3) & 0b00000111)), context);
}

fn decodeRegToFromRegMem(instruction_type: InstructionType, context: *const Context) Instruction {
    const index = context.register.named_word.ip;
    const data = context.memory[0..];
    const d: bool = data[context.register.named_word.ip] & 0b00000010 != 0;
    const w: u1 = @intCast(data[index] & 0b00000001);

    const mod, const reg, const rm = extractModRegRm(data[index + 1]);
    const displacement: [*]const u8 = data.ptr + index + 2;
    var instruction: Instruction = .{
        .type = instruction_type,
        .address = @intCast(index),
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

fn decodeAddSubCmpImmToAcc(context: *const Context) Instruction {
    const data = context.memory[0..];
    const index = context.register.named_word.ip;
    const wide: bool = (data[index] & 0b1) != 0;
    return .{
        .type = extractAddSubCmpType(@intCast((data[index] >> 3) & 0b00000111)),
        .address = @intCast(index),
        .operand = .{
            .{
                .type = .{
                    .register = .{
                        .index = .a,
                        .offset = .none,
                        .size = if (wide) .word else .byte,
                    },
                },
            },
            .{
                .type = .{
                    .immediate = extractUnsignedWord(data.ptr + index + 1, wide),
                },
            },
        },
        .size = if (wide) 3 else 2,
        .wide = wide,
    };
}

fn decodeAddSubCmpImmToRegMem(context: *const Context) Instruction {
    const data = context.memory[0..];
    const index = context.register.named_word.ip;
    _, const reg, _ = extractModRegRm(data[index + 1]);
    const s: u1 = @intCast((data[index] & 0b10) >> 1);
    return decodeImmToRegMem(extractAddSubCmpType(reg), context, s);
}

fn decodeImmToRegMem(instruction_type: InstructionType, context: *const Context, s: u1) Instruction {
    const data = context.memory[0..];
    const i = context.register.named_word.ip;
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
        const displacement: [*]const u8 = (&context.memory).ptr + context.register.named_word.ip + 2;
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
        .reg = .{
            .{
                .index = undefined,
                .size = .word,
                .offset = .none,
            },
            .{
                .index = undefined,
                .size = .word,
                .offset = .none,
            },
        },
    };
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

fn decode(context: *const Context) ?Instruction {
    const data = context.memory[0..];
    const i = context.register.named_word.ip;
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
                .reg = .{
                    Register.none,
                    Register.none,
                },
                // TODO(TB): displacement in this case should be unsigned?
                .displacement = extractSignedWord(data.ptr + i + 1, true),
                .displacement_size = 2,
            },
        };
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
        return .{
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
            .operand = .{
                .{ .type = .{
                    .relative_jump_displacement = @as(i8, @bitCast(data[i + 1])),
                }},
                .{ .type = .none },
            },
            .size = 2,
            .wide = false,
        };
    } else if ((data[i] & 0b11111100) == 0b11100000) {
        // loop, loopz, loopnz, jcxz
        return .{
            .type = switch (data[i] & 0b00000011) {
                0b10 => .loop,
                0b01 => .loopz,
                0b00 => .loopnz,
                0b11 => .jcxz,
                else => unreachable,
            },
            .address = @intCast(i),
            .operand = .{
                .{ .type = .{
                    .relative_jump_displacement = @as(i8, @bitCast(data[i + 1])),
                }},
                .{ .type = .none },
            },
            .size = 2,
            .wide = false,
        };
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

fn decodeAndPrintAll(allocator: std.mem.Allocator, writer: std.fs.File.Writer, context: *Context) !void {
    var instructions = try std.ArrayList(Instruction).initCapacity(allocator, context.program_size / 2);
    defer instructions.deinit();

    var labels = std.ArrayList(usize).init(allocator);
    defer labels.deinit();

    while (context.register.named_word.ip < context.program_size) {
        const instruction = decode(context).?;
        try instructions.append(instruction);
        context.register.named_word.ip += instruction.size;

        const maybe_jump_ip_inc8 = getJumpIpInc8(instruction);
        if (maybe_jump_ip_inc8) |jump_ip_inc8| {
            // TODO(TB): consider overflow
            const jump_byte: usize = @as(usize, @intCast(@as(isize, @intCast(context.register.named_word.ip)) + jump_ip_inc8));
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
    var out = std.io.getStdOut();
    const writer = out.writer();
    var context: *Context = try gpa.create(Context);
    defer gpa.destroy(context);
    context.init();
    context.program_size = @intCast(try file.read(&context.memory));
    try decodeAndPrintAll(gpa, writer, context);
}
