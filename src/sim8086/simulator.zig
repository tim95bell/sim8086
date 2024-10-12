const std = @import("std");
const Instruction = @import("Instruction.zig");
const Context = @import("Context.zig");

// ReadWriteAddress : a pointer to a register or memory, and the width
pub const ReadWriteAddress = struct {
    data: [*]u8,
    wide: bool,
};

// TODO(TB): change this from index to the actual bit (e.g. change 3 to 8=0b1000, change 0 to 1=0b1)
// NOTE(TB): enum names prefixed with `flag` because if is a keyword
pub const FlagBitIndex = enum(u4) {
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

pub fn hasAtLeastOneFlagSet(flags: u16) bool {
    return flags != 0;
}

pub fn clearFlags(flags: *u16) void {
    flags.* = 0;
}

pub fn setFlag(flags: *u16, flag: FlagBitIndex, value: bool) void {
    flags.* &= ~(@as(u16, 1) << @intFromEnum(flag));
    flags.* |= (@as(u16, if (value) 1 else 0) << @intFromEnum(flag));
}

pub fn testFlag(flags: u16, flag: FlagBitIndex) bool {
    return ((flags >> @intFromEnum(flag)) & 0b1) != 0;
}

pub fn printFlags(flags: u16, buffer: []u8) []u8 {
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

fn sub(operand: [2]Instruction.Operand, context: *Context.Context) struct { ReadWriteAddress, i17, i17, i17 } {
    const dst_address: ReadWriteAddress = createReadWriteAddress(operand[0], context);
    const a: i17 = readSigned(dst_address);
    const b: i17 = getSrcOperandValueSigned(operand[1], context);
    const c: i17 = a - b;
    return .{ dst_address, a, b, c };
}

fn getRegisterValueUnsigned(register: Instruction.Register, context: *const Context.Context) u16 {
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

fn getRegisterValueSigned(register: Instruction.Register, context: *const Context.Context) i16 {
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

fn getRegisterBytePtr(register: Instruction.Register, context: *Context.Context) *u8 {
    std.debug.assert(register.size == .byte);
    std.debug.assert((register.offset != .byte) or (register.size == .byte));
    std.debug.assert((register.index != .sp and register.index != .bp and register.index != .si and register.index != .di) or (register.size == .word and register.offset == .none));
    std.debug.assert(register.index != .none);
    return &context.register.byte[@intFromEnum(register.index)][@intFromEnum(register.offset)];
}

fn getRegisterBytePtrConst(register: Instruction.Register, context: *const Context.Context) *const u8 {
    std.debug.assert(register.size == .byte);
    std.debug.assert((register.offset != .byte) or (register.size == .byte));
    std.debug.assert((register.index != .sp and register.index != .bp and register.index != .si and register.index != .di) or (register.size == .word and register.offset == .none));
    std.debug.assert(register.index != .none);
    return &context.register.byte[@intFromEnum(register.index)][@intFromEnum(register.offset)];
}

fn getRegisterWordPtr(register: Instruction.Register, context: *Context.Context) *u16 {
    std.debug.assert(register.size == .word);
    std.debug.assert(register.offset == .none);
    std.debug.assert((register.offset != .byte) or (register.size == .byte));
    std.debug.assert((register.index != .sp and register.index != .bp and register.index != .si and register.index != .di) or (register.size == .word and register.offset == .none));
    std.debug.assert(register.index != .none);
    return &context.register.word[@intFromEnum(register.index)];
}

fn getRegisterWordPtrConst(register: Instruction.Register, context: *const Context.Context) *const u16 {
    std.debug.assert(register.size == .word);
    std.debug.assert(register.offset == .none);
    std.debug.assert((register.offset != .byte) or (register.size == .byte));
    std.debug.assert((register.index != .sp and register.index != .bp and register.index != .si and register.index != .di) or (register.size == .word and register.offset == .none));
    std.debug.assert(register.index != .none);
    return &context.register.word[@intFromEnum(register.index)];
}

fn getSrcOperandValue(operand: Instruction.Operand, context: *Context.Context) u16 {
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

fn getSrcOperandValueSigned(operand: Instruction.Operand, context: *Context.Context) i16 {
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

fn getMemoryIndex(memory: Instruction.Memory, context: *const Context.Context) u32 {
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

fn createReadWriteAddressFromMemory(memory: Instruction.Memory, context: *Context.Context) ReadWriteAddress {
    const index: u32 = getMemoryIndex(memory, context);
    return .{
        .data = @ptrCast(&context.memory[index]),
        .wide = memory.size == .word,
    };
}

fn createReadWriteAddress(operand: Instruction.Operand, context: *Context.Context) ReadWriteAddress {
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

pub fn simulateInstruction(instruction: Instruction.Instruction, context: *Context.Context) void {
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
            std.debug.print("unimplemented operation: {s}\n", .{Instruction.getInstructionTypeString(instruction.type)});
        },
    }
}
