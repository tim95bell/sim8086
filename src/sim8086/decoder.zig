const std = @import("std");
const Instruction = @import("Instruction.zig");
const Context = @import("Context.zig");
const Register = @import("Register.zig");
const Memory = @import("Memory.zig");

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
    else
        data[0];
}

fn decodeImmToReg(instruction_type: Instruction.Type, context: *const Context) Instruction {
    const data = context.memory[0..];
    const index = context.register.named_word.ip;
    const w: u1 = @intCast((data[index] & 0b00001000) >> 3);
    return .{
        .address = @intCast(index),
        .type = instruction_type,
        .operand = .{ .{
            .type = .{
                .register = Register.regFieldEncoding(w, @intCast(data[index] & 0b00000111)),
            },
        }, .{
            .type = .{
                .immediate = extractUnsignedWord(data.ptr + index + 1, w != 0),
            },
        } },
        .size = 2 + @as(u8, w),
        .wide = w != 0,
    };
}

fn decodeAddSubCmpRegToFromRegMem(context: *const Context) Instruction {
    const data = context.memory[0..];
    const index = context.register.named_word.ip;
    return decodeRegToFromRegMem(extractAddSubCmpType(@intCast((data[index] >> 3) & 0b00000111)), context);
}

fn decodeRegToFromRegMem(instruction_type: Instruction.Type, context: *const Context) Instruction {
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
    instruction.operand[if (d) 0 else 1] = .{ .type = .{ .register = Register.regFieldEncoding(w, reg) } };
    const rm_operand_index: u1 = if (d) 1 else 0;
    if (mod == 0b11) {
        instruction.operand[rm_operand_index] = .{ .type = .{ .register = Register.regFieldEncoding(w, rm) } };
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

fn extractAddSubCmpType(bits: u3) Instruction.Type {
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

fn decodeImmToRegMem(instruction_type: Instruction.Type, context: *const Context, s: u1) Instruction {
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
            .register = Register.regFieldEncoding(w, rm),
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

fn createRm(mod: u2, rm: u3, w: u1, displacement: [*]const u8, displacement_size_out: *u8) Instruction.Operand {
    if (mod == 0b11) {
        displacement_size_out.* = 0;
        return .{ .type = .{ .register = Register.regFieldEncoding(w, rm) } };
    } else {
        return .{ .type = .{ .memory = createMem(mod, rm, w != 0, displacement, displacement_size_out) } };
    }
}

pub fn decode(context: *const Context) ?Instruction {
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
                } },
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
                } },
                .{ .type = .none },
            },
            .size = 2,
            .wide = false,
        };
    } else {
        return null;
    }
}
