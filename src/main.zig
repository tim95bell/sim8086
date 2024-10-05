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

// ReadWriteAddress : a pointer to a register or memory, and the width
const ReadWriteAddress = struct {
    data: [*]u8,
    wide: bool,
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
    size: Size,
};

const Memory = struct {
    // TODO(TB): should displacement be stored sepertely for word and byte?
    displacement: i16,
    size: Size,
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
    cs,
    ds,
    ss,
    es,
    none,
};

const RegisterOffset = enum(u8) {
    none = 0,
    byte = 1,
};

const Size = enum(u8) {
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
            // TODO(TB): getGeneralPurposeRegisterLabelLetter is doing duplicated work here
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
        .cs => {
            buffer[0] = 'c';
            buffer[1] = 's';
        },
        .ds => {
            buffer[0] = 'd';
            buffer[1] = 's';
        },
        .ss => {
            buffer[0] = 's';
            buffer[1] = 's';
        },
        .es => {
            buffer[0] = 'e';
            buffer[1] = 's';
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
                // NOTE(TB): treat displacement as unsigned, as signed address does not make sense
                return std.fmt.bufPrint(buffer, "[+{d}]", .{@as(u16, @bitCast(data.displacement))}) catch unreachable;
            } else if (data.reg[1].index == .none) {
                var reg_label_buffer: [2]u8 = undefined;
                if (data.displacement == 0) {
                    // TODO(TB): is this legal? would it be signed then?
                    return std.fmt.bufPrint(buffer, "[{s}]", .{getRegisterLabel(data.reg[0], &reg_label_buffer)}) catch unreachable;
                } else {
                    const negative = data.displacement < 0;
                    return std.fmt.bufPrint(buffer, "[{s}{s}{d}]", .{
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
                    return std.fmt.bufPrint(buffer, "[{s}+{s}]", .{
                        reg_0_label,
                        reg_1_label,
                    }) catch unreachable;
                } else {
                    const negative = data.displacement < 0;
                    return std.fmt.bufPrint(buffer, "[{s}+{s}{s}{d}]", .{
                        reg_0_label,
                        reg_1_label,
                        if (negative) "-" else "+",
                        if (negative) data.displacement * -1 else data.displacement,
                    }) catch unreachable;
                }
            }
        },
        .relative_jump_displacement => |data| {
            // NOTE(TB): add 2 to to data here so that it is as if going from before the jump instruction
            const negative = data < 0;
            const data_plus_2 = data + 2;
            const positive_data_plus_2 = if (negative) data_plus_2 * -1 else data_plus_2;
            return std.fmt.bufPrint(buffer, "${s}{d}", .{if (negative) "-" else "+", positive_data_plus_2}) catch unreachable;
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
        .jnz => "jne",
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
    return if (wide) @as(i16, @bitCast(data[0] | (@as(u16, data[1]) << 8))) else @as(i16, @as(i8, @bitCast(data[0])));
}

fn extractUnsignedWord(data: [*]const u8, wide: bool) u16 {
    return if (wide) data[0] | (@as(u16, data[1]) << 8) else data[0];
}

fn extractUnsignedWordSignExtend(data: [*]const u8, wide: bool, sign_extend: bool) u16 {
    return if (wide)
        (if (sign_extend) @bitCast(@as(i16, @as(i8, @bitCast(data[0])))) else data[0] | (@as(u16, data[1]) << 8))
        else data[0];
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

// TODO(TB): change this from index to the actual bit (e.g. change 3 to 8=0b1000, change 0 to 1=0b1)
// NOTE(TB): enum names prefixed with `flag` because if is a keyword
const FlagBitIndex = enum(u4) {
    flag_cf = 0,
    flag_pf = 2,
    flag_af = 4,
    flag_zf = 6,
    flag_sf,
    flag_tf,
    flag_if,
    flag_df,
    flag_of,
};

// TODO(TB): how to replace uses of this with using comptime and type info?
const all_flags: [@typeInfo(FlagBitIndex).Enum.fields.len]FlagBitIndex = .{
    .flag_cf,
    .flag_pf,
    .flag_af,
    .flag_zf,
    .flag_sf,
    .flag_tf,
    .flag_if,
    .flag_df,
    .flag_of,
};

// TODO(TB): can this be a method on the enum?
fn getFlagBitIndexLabel(flag: FlagBitIndex) u8 {
    return switch (flag) {
        .flag_cf => 'C',
        .flag_pf => 'P',
        .flag_af => 'A',
        .flag_zf => 'Z',
        .flag_sf => 'S',
        .flag_tf => 'T',
        .flag_if => 'I',
        .flag_df => 'D',
        .flag_of => 'O',
    };
}

const Registers = extern union {
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
        cs: u16,
        ds: u16,
        ss: u16,
        es: u16,
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
    byte: [@typeInfo(RegisterIndex).Enum.fields.len - 1][2]u8,
    word: [@typeInfo(RegisterIndex).Enum.fields.len - 1]u16,
};

const Context = struct {
    memory: [1028 * 1028 * 1028]u8,
    program_size: u16,
    register: Registers,
    flags: u16,

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

        std.debug.assert(@as(u16, self.register.byte[9][0]) | (@as(u16, self.register.byte[9][1]) << 8) == self.register.named_word.cs);
        std.debug.assert(@as(u16, self.register.byte[9][0]) | (@as(u16, self.register.byte[9][1]) << 8) == self.register.word[9]);

        std.debug.assert(@as(u16, self.register.byte[10][0]) | (@as(u16, self.register.byte[10][1]) << 8) == self.register.named_word.ds);
        std.debug.assert(@as(u16, self.register.byte[10][0]) | (@as(u16, self.register.byte[10][1]) << 8) == self.register.word[10]);

        std.debug.assert(@as(u16, self.register.byte[11][0]) | (@as(u16, self.register.byte[11][1]) << 8) == self.register.named_word.ss);
        std.debug.assert(@as(u16, self.register.byte[11][0]) | (@as(u16, self.register.byte[11][1]) << 8) == self.register.word[11]);

        std.debug.assert(@as(u16, self.register.byte[12][0]) | (@as(u16, self.register.byte[12][1]) << 8) == self.register.named_word.es);
        std.debug.assert(@as(u16, self.register.byte[12][0]) | (@as(u16, self.register.byte[12][1]) << 8) == self.register.word[12]);

        // TODO(TB): zero out memory?
        @memset(&self.register.word, 0);
        self.flags = 0;
    }
};

fn hasAtLeastOneFlagSet(flags: u16) bool {
    return flags != 0;
}

fn clearFlags(flags: *u16) void {
    flags.* = 0;
}

fn setFlag(flags: *u16, flag: FlagBitIndex, value: bool) void {
    flags.* &= ~(@as(u16, 1) << @intFromEnum(flag));
    flags.* |= (@as(u16, if (value) 1 else 0) << @intFromEnum(flag));
}

fn testFlag(flags: u16, flag: FlagBitIndex) bool {
    return ((flags >> @intFromEnum(flag)) & 0b1) != 0;
}

fn printFlags(flags: u16, buffer: []u8) []u8 {
    std.debug.assert(buffer.len >= @typeInfo(FlagBitIndex).Enum.fields.len);
    var len: u8 = 0;
    for (all_flags) |flag| {
        if (testFlag(flags, flag)) {
            buffer[len] = getFlagBitIndexLabel(flag);
            len += 1;
        }
    }
    return buffer[0..len];
}

fn parity(x: u8) bool {
    return (
        (x & 0b1)
        + ((x >> 1) & 0b1)
        + ((x >> 2) & 0b1)
        + ((x >> 3) & 0b1)
        + ((x >> 4) & 0b1)
        + ((x >> 5) & 0b1)
        + ((x >> 6) & 0b1)
        + ((x >> 7) & 0b1)
    ) % 2 == 0;
}

fn testBit(x: anytype, n: anytype) bool {
    return ((x >> n) & 1) != 0;
}

fn getCarry(a: anytype, b: anytype, c: anytype, n: anytype) bool {
    return if (testBit(a, n) != testBit(b, n)) !testBit(c, n)
        else testBit(c, n);
}

fn getBorrow(a: anytype, b: anytype, c: anytype, n: anytype) bool {
    return (!testBit(a, n) and (testBit(b, n) or testBit(c, n))) or (testBit(a, n) and (testBit(b, n) == testBit(c, n)));
}

fn updateZSPFlags(flags: *u16, new_value: u17, wide: bool) void {
    const significant_bit_index: u5 = if (wide) 15 else 7;
    setFlag(flags, .flag_zf, new_value == 0);
    setFlag(flags, .flag_sf, testBit(new_value, significant_bit_index));
    setFlag(flags, .flag_pf, parity(@truncate(new_value)));
}

fn updateAddFlags(a: i17, b: i17, c: i17, wide: bool, flags: *u16) void {
    // a + b = c
    updateZSPFlags(flags, @bitCast(c), wide);
    const significant_bit_index: u5 = if (wide) 15 else 7;
    const carry_bit_index: u5 = significant_bit_index + 1;

    const significant_bit_carry = getCarry(a, b, c, significant_bit_index);
    const carry_bit_carry = getCarry(a, b, c, carry_bit_index);
    setFlag(flags, .flag_cf, carry_bit_carry);
    setFlag(flags, .flag_of, carry_bit_carry != significant_bit_carry);
    setFlag(flags, .flag_af, getCarry(a, b, c, 4));
}

fn updateSubFlags(a: i17, b: i17, c: i17, wide: bool, flags: *u16) void {
    // a - b = c
    updateZSPFlags(flags, @bitCast(c), wide);
    const significant_bit_index: u5 = if (wide) 15 else 7;
    const carry_bit_index: u5 = significant_bit_index + 1;

    const significant_bit_borrow = getBorrow(a, b, c, significant_bit_index);
    const carry_bit_borrow = getBorrow(a, b, c, carry_bit_index);
    setFlag(flags, .flag_cf, carry_bit_borrow);
    setFlag(flags, .flag_of, carry_bit_borrow != significant_bit_borrow);
    setFlag(flags, .flag_af, getBorrow(a, b, c, 4));
}

fn sub(operand: [2]Operand, context: *Context) struct { ReadWriteAddress, i17, i17, i17 } {
    const dst_address: ReadWriteAddress = createReadWriteAddress(operand[0], context);
    const a: i17 = readSigned(dst_address);
    const b: i17 = getSrcOperandValueSigned(operand[1], context);
    const c: i17 = a - b;
    return .{ dst_address, a, b, c };
}

fn getRegisterValueUnsigned(register: Register, context: *const Context) u16 {
    if (register.size == .byte) {
        std.debug.assert(register.index != .none);
        return context.register.byte[@intFromEnum(register.index)][@intFromEnum(register.offset)];
    } else {
        std.debug.assert(register.size == .word);
        std.debug.assert(register.offset == .none);
        std.debug.assert(register.index != .none);
        return context.register.word[@intFromEnum(register.index)];
    }
}

fn getRegisterValueSigned(register: Register, context: *const Context) i16 {
    if (register.size == .byte) {
        std.debug.assert(register.index != .none);
        return @as(i8, @bitCast(context.register.byte[@intFromEnum(register.index)][@intFromEnum(register.offset)]));
    } else {
        std.debug.assert(register.size == .word);
        std.debug.assert(register.offset == .none);
        std.debug.assert(register.index != .none);
        return @bitCast(context.register.word[@intFromEnum(register.index)]);
    }
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
    const w: u1 = @truncate(data[index]);

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
        var displacement_size: u8 = undefined;
        instruction.operand[rm_operand_index] = .{
            .type = .{
                .memory = createMem(mod, rm, w != 0, displacement, &displacement_size),
            },
        };
        instruction.size = 2 + displacement_size;
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
    const s: u1 = @truncate(data[index] >> 1);
    return decodeImmToRegMem(extractAddSubCmpType(reg), context, s);
}

fn decodeImmToRegMem(instruction_type: InstructionType, context: *const Context, s: u1) Instruction {
    const data = context.memory[0..];
    const i = context.register.named_word.ip;
    const w: u1 = @truncate(data[i]);
    const mod, const reg, const rm = extractModRegRm(data[i + 1]);
    std.debug.assert(reg == 0b000 or reg == 0b101 or reg == 0b111);
    const displacement_only = mod == 0b00 and rm == 0b110;
    const displacement_size: u8 = if (mod == 0b11) 0 else if (displacement_only) 2 else mod;
    const immediate_index_offset: u8 = 2 + displacement_size;
    const wide_immediate = s == 0 and w == 1;
    const immediate: u16 = extractUnsignedWordSignExtend(data.ptr + i + immediate_index_offset, w != 0, s != 0);

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
        // TODO(TB): clean up this function, should not be 2 displacement_size
        var displacement_size_2: u8 = undefined;
        instruction.operand[0].type = .{
            .memory = createMem(mod, rm, w != 0, displacement, &displacement_size_2),
        };
        instruction.size = displacement_size_2 + @as(u8, if (wide_immediate) 4 else 3);
    }
    return instruction;
}

fn decodeRegMemToFromSegmentRegister(comptime d: bool, context: *const Context) Instruction {
    const i = context.register.named_word.ip;
    const mod: u2 = @intCast(context.memory[i + 1] >> 6);
    std.debug.assert((context.memory[i + 1] & 0b00100000) == 0);
    const sr: u2 = @intCast((context.memory[i + 1] >> 3) & 0b11);
    const rm: u3 = @intCast(context.memory[i + 1] & 0b111);
    const displacement = (&context.memory).ptr + 2;
    var displacement_size: u8 = undefined;
    var instruction: Instruction = .{
        .type = .mov,
        .address = @intCast(i),
        .operand = undefined,
        .size = undefined,
        .wide = true,
    };
    const sr_index = if (d) 0 else 1;
    const rm_index = if (d) 1 else 0;
    instruction.operand[rm_index] = createRm(mod, rm, 1, displacement, &displacement_size);
    instruction.operand[sr_index] = .{
        .type = .{
            .register = .{
                .index = switch (sr) {
                    0b00 => .es,
                    0b01 => .cs,
                    0b10 => .ss,
                    0b11 => .ds,
                },
                .size = .word,
                .offset = .none,
            },
        },
    };
    instruction.size = 2 + displacement_size;
    return instruction;
}

fn createMem(mod: u2, rm: u3, w: bool, displacement: [*]const u8, displacement_size_out: *u8) Memory {
    std.debug.assert(mod != 0b11);
    const displacement_only = mod == 0b00 and rm == 0b110;
    const displacement_size = if (displacement_only) 2 else if (mod == 0b11) 0 else mod;
    displacement_size_out.* = displacement_size;
    std.debug.assert(displacement_size == 0 or displacement_size == 1 or displacement_size == 2);
    var result: Memory = .{
        .displacement = if (displacement_size > 0) extractSignedWord(displacement, displacement_size == 2) else 0,
        .size = if (w) .word else .byte,
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

fn createRm(mod: u2, rm: u3, w: u1, displacement: [*]const u8, displacement_size_out: *u8) Operand {
    if (mod == 0b11) {
        displacement_size_out.* = 0;
        return .{ .type = .{ .register = regFieldEncoding(w, rm) } };
    } else {
        return .{ .type = .{ .memory = createMem(mod, rm, w != 0, displacement, displacement_size_out) } };
    }
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
                .size = if (wide) .word else .byte,
                // TODO(TB): displacement in this case should be unsigned?
                .displacement = extractSignedWord(data.ptr + i + 1, true),
            },
        };
        return instruction;
    } else if ((data[i] & 0b11111111) == 0b10001110) {
        // register/memory to segment register
        return decodeRegMemToFromSegmentRegister(true, context);
    } else if ((data[i] & 0b11111111) == 0b10001100) {
        // segment register to register/memory
        return decodeRegMemToFromSegmentRegister(false, context);
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
        try writer.print("{s} {s}", .{
            instruction_type_string,
            operand_1_label,
        });
    } else {
        if (instruction.operand[0].type == .memory and instruction.operand[1].type == .immediate) {
            try writer.print("{s} {s} {s}, {s}", .{
                instruction_type_string,
                if (instruction.wide) "word" else "byte",
                operand_1_label,
                getOperandLabel(instruction.operand[1], &operand_buffer[1]),
            });
        } else {
            try writer.print("{s} {s}, {s}", .{
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
        try writer.print("{s} test_label{d}", .{getInstructionTypeString(instruction.type), index});
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
        try writer.print("\n", .{});

        byte_index += instruction.size;
    }
    try printLabel(writer, byte_index, &next_label_index, labels);
}

fn getRegisterBytePtr(register: Register, context: *Context) *u8 {
    std.debug.assert(register.size == .byte);
    std.debug.assert((register.offset != .byte) or (register.size == .byte));
    std.debug.assert((register.index != .sp and register.index != .bp and register.index != .si and register.index != .di) or (register.size == .word and register.offset == .none));
    std.debug.assert(register.index != .none);
    return &context.register.byte[@intFromEnum(register.index)][@intFromEnum(register.offset)];
}

fn getRegisterBytePtrConst(register: Register, context: *const Context) *const u8 {
    std.debug.assert(register.size == .byte);
    std.debug.assert((register.offset != .byte) or (register.size == .byte));
    std.debug.assert((register.index != .sp and register.index != .bp and register.index != .si and register.index != .di) or (register.size == .word and register.offset == .none));
    std.debug.assert(register.index != .none);
    return &context.register.byte[@intFromEnum(register.index)][@intFromEnum(register.offset)];
}

fn getRegisterWordPtr(register: Register, context: *Context) *u16 {
    std.debug.assert(register.size == .word);
    std.debug.assert(register.offset == .none);
    std.debug.assert((register.offset != .byte) or (register.size == .byte));
    std.debug.assert((register.index != .sp and register.index != .bp and register.index != .si and register.index != .di) or (register.size == .word and register.offset == .none));
    std.debug.assert(register.index != .none);
    return &context.register.word[@intFromEnum(register.index)];
}

fn getRegisterWordPtrConst(register: Register, context: *const Context) *const u16 {
    std.debug.assert(register.size == .word);
    std.debug.assert(register.offset == .none);
    std.debug.assert((register.offset != .byte) or (register.size == .byte));
    std.debug.assert((register.index != .sp and register.index != .bp and register.index != .si and register.index != .di) or (register.size == .word and register.offset == .none));
    std.debug.assert(register.index != .none);
    return &context.register.word[@intFromEnum(register.index)];
}

fn getSrcOperandValue(operand: Operand, context: *Context) u16 {
    switch (operand.type) {
        .register => |data| {
            if (data.size == .byte) {
                return getRegisterBytePtr(data, context).*;
            } else {
                return getRegisterWordPtr(data, context).*;
            }
        },
        .memory => |data| {
            return read(createReadWriteAddressFromMemory(data, context));
        },
        .immediate => |data| {
            return data;
        },
        else => unreachable,
    }
}

fn getSrcOperandValueSigned(operand: Operand, context: *Context) i16 {
    switch (operand.type) {
        .register => |data| {
            if (data.size == .byte) {
                return @as(i8, @bitCast(getRegisterBytePtr(data, context).*));
            } else {
                return @bitCast(getRegisterWordPtr(data, context).*);
            }
        },
        .memory => |data| {
            return readSigned(createReadWriteAddressFromMemory(data, context));
        },
        .immediate => |data| {
            return @bitCast(data);
        },
        else => unreachable,
    }
}

fn write(src: ReadWriteAddress, new_value: u16) void {
    src.data[0] = @intCast(new_value & 0b11111111);
    std.debug.assert(src.wide or (new_value & 0b1111111100000000) == 0);
    if (src.wide) {
        src.data[1] = @intCast((new_value & 0b1111111100000000) >> 8);
    }
}

fn read(src: ReadWriteAddress) u16 {
    if (src.wide) {
        return src.data[0] | (@as(u16, src.data[1]) << 8);
    } else {
        return src.data[0];
    }
}

fn readSigned(src: ReadWriteAddress) i16 {
    if (src.wide) {
        return @bitCast(src.data[0] | (@as(u16, src.data[1]) << 8));
    } else {
        return @as(i8, @bitCast(src.data[0]));
    }
}

fn getMemoryIndex(memory: Memory, context: *const Context) u32 {
    // TODO(TB): handle negative index?
    if (memory.reg[0].index == .none) {
        // NOTE(TB): displacement is treated as unsigned when not adding to registers
        return @intCast(@as(u16, @bitCast(memory.displacement)));
    } else if (memory.reg[1].index == .none) {
        const result: i32 = @as(i32, memory.displacement) + @as(i32, getRegisterValueSigned(memory.reg[0], context));
        std.debug.assert(result > 0);
        return @intCast(result);
    } else {
        const result: i32 = @as(i32, memory.displacement) + @as(i32, getRegisterValueSigned(memory.reg[0], context)) + @as(i32, getRegisterValueSigned(memory.reg[1], context));
        std.debug.assert(result > 0);
        return @intCast(result);
    }
}

fn createReadWriteAddressFromMemory(memory: Memory, context: *Context) ReadWriteAddress {
    const index: u32 = getMemoryIndex(memory, context);
    return .{
        .data = @ptrCast(&context.memory[index]),
        .wide = memory.size == .word,
    };
}

fn createReadWriteAddress(operand: Operand, context: *Context) ReadWriteAddress {
    switch (operand.type) {
        .register => |data| {
            return .{
                .data = @ptrCast(&context.register.byte[@intFromEnum(data.index)][@intFromEnum(data.offset)]),
                .wide = data.size == .word,
            };
        },
        .memory => |data| {
            return createReadWriteAddressFromMemory(data, context);
        },
        else => unreachable,
    }
}

fn simulateInstruction(instruction: Instruction, context: *Context) void {
    context.register.named_word.ip += instruction.size;

    if (instruction.operand[0].type != .none) {
        switch (instruction.operand[0].type) {
            .register => |data| {
                if (instruction.wide) {
                    std.debug.assert(data.size == .word);
                } else {
                    std.debug.assert(data.size == .byte);
                }
            },
            .memory => |data| {
                if (instruction.wide) {
                    std.debug.assert(data.size == .word);
                } else {
                    std.debug.assert(data.size == .byte);
                }
            },
            else => {},
        }

        if (instruction.operand[1].type != .none) {
            switch (instruction.operand[1].type) {
                .register => |data| {
                    if (instruction.wide) {
                        std.debug.assert(data.size == .word);
                    } else {
                        std.debug.assert(data.size == .byte);
                    }
                },
                .memory => |data| {
                    if (instruction.wide) {
                        std.debug.assert(data.size == .word);
                    } else {
                        std.debug.assert(data.size == .byte);
                    }
                },
                else => {},
            }
        }
    } else {
        std.debug.assert(instruction.operand[1].type == .none);
    }

    switch (instruction.type) {
        .mov => {
            const dst_address: ReadWriteAddress = createReadWriteAddress(instruction.operand[0], context);
            const new_value: u16 = getSrcOperandValue(instruction.operand[1], context);
            write(dst_address, new_value);
        },
        .add => {
            const dst_address: ReadWriteAddress = createReadWriteAddress(instruction.operand[0], context);
            const a: i17 = readSigned(dst_address);
            const b: i17 = getSrcOperandValueSigned(instruction.operand[1], context);
            const c: i17 = a + b;
            write(dst_address, @bitCast(@as(i16, @truncate(c))));
            std.debug.assert(@as(i16, @truncate(c)) == readSigned(dst_address));
            updateAddFlags(a, b, c, instruction.wide, &context.flags);
        },
        .sub => {
            const dst_address, const a, const b, const c = sub(instruction.operand, context);
            write(dst_address, @bitCast(@as(i16, @truncate(c))));
            std.debug.assert(@as(i16, @truncate(c)) == readSigned(dst_address));
            updateSubFlags(a, b, c, instruction.wide, &context.flags);
        },
        .cmp => {
            _, const a, const b, const c = sub(instruction.operand, context);
            updateSubFlags(a, b, c, instruction.wide, &context.flags);
        },
        .je => {
            if (instruction.operand[0].type == .relative_jump_displacement) {
                const displacement = instruction.operand[0].type.relative_jump_displacement;
                std.debug.assert(instruction.operand[1].type == .none);
                if (testFlag(context.flags, .flag_zf)) {
                    std.debug.assert(context.register.named_word.ip >= displacement);
                    // TODO(TB): check for ip overflow
                    const new_ip: i32 = @as(i32, context.register.named_word.ip) + displacement;
                    context.register.named_word.ip = @bitCast(@as(i16, @truncate(new_ip)));
                }
            } else {
                std.debug.assert(false);
            }
        },
        .jnz => {
            if (instruction.operand[0].type == .relative_jump_displacement) {
                const displacement = instruction.operand[0].type.relative_jump_displacement;
                std.debug.assert(instruction.operand[1].type == .none);
                if (!testFlag(context.flags, .flag_zf)) {
                    std.debug.assert(context.register.named_word.ip >= displacement);
                    // TODO(TB): check for ip overflow
                    const new_ip: i32 = @as(i32, context.register.named_word.ip) + displacement;
                    context.register.named_word.ip = @bitCast(@as(i16, @truncate(new_ip)));
                }
            } else {
                std.debug.assert(false);
            }
        },
        .jp => {
            if (instruction.operand[0].type == .relative_jump_displacement) {
                const displacement = instruction.operand[0].type.relative_jump_displacement;
                std.debug.assert(instruction.operand[1].type == .none);
                if (testFlag(context.flags, .flag_pf)) {
                    std.debug.assert(context.register.named_word.ip >= displacement);
                    // TODO(TB): check for ip overflow
                    const new_ip: i32 = @as(i32, context.register.named_word.ip) + displacement;
                    context.register.named_word.ip = @bitCast(@as(i16, @truncate(new_ip)));
                }
            } else {
                std.debug.assert(false);
            }
        },
        .jb => {
            if (instruction.operand[0].type == .relative_jump_displacement) {
                const displacement = instruction.operand[0].type.relative_jump_displacement;
                std.debug.assert(instruction.operand[1].type == .none);
                if (testFlag(context.flags, .flag_cf)) {
                    std.debug.assert(context.register.named_word.ip >= displacement);
                    // TODO(TB): check for ip overflow
                    const new_ip: i32 = @as(i32, context.register.named_word.ip) + displacement;
                    context.register.named_word.ip = @bitCast(@as(i16, @truncate(new_ip)));
                }
            } else {
                std.debug.assert(false);
            }
        },
        .loopnz => {
            if (instruction.operand[0].type == .relative_jump_displacement) {
                const displacement = instruction.operand[0].type.relative_jump_displacement;
                std.debug.assert(instruction.operand[1].type == .none);

                // TODO(TB): not supposed to update flags after this?
                context.register.named_word.cx -= 1;

                if (context.register.named_word.cx != 0) {
                    std.debug.assert(context.register.named_word.ip >= displacement);
                    // TODO(TB): check for ip overflow
                    const new_ip: i32 = @as(i32, context.register.named_word.ip) + displacement;
                    context.register.named_word.ip = @bitCast(@as(i16, @truncate(new_ip)));
                }
            } else {
                std.debug.assert(false);
            }
        },
        else => {
            std.debug.print("unimplemented operation: {s}\n", .{getInstructionTypeString(instruction.type)});
        },
    }
}

fn simulateAndPrintAll(writer: std.fs.File.Writer, context: *Context) !void {
    _ = try writer.print("\n", .{});
    while (context.register.named_word.ip < context.program_size) {
        const instruction = decode(context).?;
        try print(writer, instruction);
        const flags_before = context.flags;
        const registers_before = context.register;
        _ = try writer.print(" ;", .{});
        simulateInstruction(instruction, context);
        try printRegistersThatChangedShort(writer, registers_before, context.register);
        if (flags_before != context.flags) {
            var flags_before_buffer: [@typeInfo(FlagBitIndex).Enum.fields.len]u8 = undefined;
            const flags_before_string = printFlags(flags_before, &flags_before_buffer);
            var flags_after_buffer: [@typeInfo(FlagBitIndex).Enum.fields.len]u8 = undefined;
            const flags_after_string = printFlags(context.flags, &flags_after_buffer);
            _ = try writer.print(" flags:{s}->{s}", .{flags_before_string, flags_after_string});
        }
        _ = try writer.print("\n", .{});
    }
    _ = try writer.print("\n", .{});
    try printRegisters(writer, context);

    if (hasAtLeastOneFlagSet(context.flags)) {
        var flags_buffer: [@typeInfo(FlagBitIndex).Enum.fields.len]u8 = undefined;
        const flags = printFlags(context.flags, &flags_buffer);
        _ = try writer.print(";   flags: {s}\n", .{flags});
    }
}

fn printRegisters(writer: std.fs.File.Writer, context: *const Context) !void {
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

fn printRegistersThatChangedShort(writer: std.fs.File.Writer, registers_before: Registers, registers: Registers) !void {
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

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    var file_name: []u8 = &.{};
    var exec: bool = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-exec")) {
            exec = true;
        } else {
            file_name = arg;
        }
    }
    if (file_name.len == 0) {
        @panic("you must provide a file to decode as a command line argument");
    }
    const file = try std.fs.cwd().openFile(file_name, .{});
    const out = std.io.getStdOut().writer();
    // TODO(TB): use buffered writer
    //var bw = std.io.bufferedWriter(out);
    //const writer = bw.writer();
    //try bw.flush(); // don't forget to flush!

    var context: *Context = try gpa.create(Context);
    defer gpa.destroy(context);
    context.init();
    context.program_size = @intCast(try file.read(&context.memory));
    if (exec) {
        try simulateAndPrintAll(out, context);
    } else {
        try decodeAndPrintAll(gpa, out, context);
    }
}
