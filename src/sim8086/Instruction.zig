const std = @import("std");

pub const Instruction = struct {
    address: u32,
    type: InstructionType,
    operand: [2]Operand,
    size: u8,
    wide: bool,
};

pub const InstructionType = enum {
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

pub const Operand = struct {
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

pub const Register = struct {
    pub const al: Register = .{ .index = .a, .offset = .none, .size = .byte };
    pub const bl: Register = .{ .index = .b, .offset = .none, .size = .byte };
    pub const cl: Register = .{ .index = .c, .offset = .none, .size = .byte };
    pub const dl: Register = .{ .index = .d, .offset = .none, .size = .byte };
    pub const ah: Register = .{ .index = .a, .offset = .byte, .size = .byte };
    pub const bh: Register = .{ .index = .b, .offset = .byte, .size = .byte };
    pub const ch: Register = .{ .index = .c, .offset = .byte, .size = .byte };
    pub const dh: Register = .{ .index = .d, .offset = .byte, .size = .byte };
    pub const ax: Register = .{ .index = .a, .offset = .none, .size = .word };
    pub const bx: Register = .{ .index = .b, .offset = .none, .size = .word };
    pub const cx: Register = .{ .index = .c, .offset = .none, .size = .word };
    pub const dx: Register = .{ .index = .d, .offset = .none, .size = .word };
    pub const sp: Register = .{ .index = .sp, .offset = .none, .size = .word };
    pub const bp: Register = .{ .index = .bp, .offset = .none, .size = .word };
    pub const si: Register = .{ .index = .si, .offset = .none, .size = .word };
    pub const di: Register = .{ .index = .di, .offset = .none, .size = .word };
    pub const none: Register = .{ .index = .none, .offset = .none, .size = .word };

    index: RegisterIndex,
    offset: RegisterOffset,
    size: Size,
};

pub const Memory = struct {
    // TODO(TB): should displacement be stored sepertely for word and byte?
    displacement: i16,
    size: Size,
    reg: [2]Register,
};

pub const RegisterIndex = enum {
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

pub const RegisterOffset = enum(u8) {
    none = 0,
    byte = 1,
};

pub const Size = enum(u8) {
    byte = 1,
    word = 2,
};

pub fn getGeneralPurposeRegisterLabelLetter(reg: RegisterIndex) u8 {
    return switch (reg) {
        .a => 'a',
        .b => 'b',
        .c => 'c',
        .d => 'd',
        else => unreachable,
    };
}

pub fn getRegisterLabel(register: Register, buffer: []u8) []u8 {
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

pub const reg_field_encoding: [16]Register = .{
    Register.al, Register.cl, Register.dl, Register.bl, Register.ah, Register.ch, Register.dh, Register.bh, Register.ax, Register.cx, Register.dx, Register.bx, Register.sp, Register.bp, Register.si, Register.di
};

pub fn regFieldEncoding(w: u1, reg: u3) Register {
    return reg_field_encoding[@as(u4, w) << 3 | reg];
}

pub fn getOperandLabel(operand: Operand, buffer: []u8) []u8 {
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

pub fn getInstructionTypeString(instruction_type: InstructionType) []const u8 {
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

pub fn getJumpIpInc8(instruction: Instruction) ?i8 {
    return switch (instruction.type) {
        .jnz, .je, .jl, .jle, .jb, .jbe, .jp, .jo, .js,
        .jnl, .jg, .jnb, .ja, .jnp, .jno, .jns, .loop,
        .loopz, .loopnz, .jcxz => instruction.operand[0].type.relative_jump_displacement,
        else => null,
    };
}
