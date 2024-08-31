const std = @import("std");

const RegToFromReg = struct {
    dst_reg: RegisterId,
    src_reg: RegisterId,
};

const RegToFromMem = struct {
    reg: RegisterId,
    displacement: [2]u8,
    displacement_size: u8,
    displacement_only: bool,
    d: bool,
    rm_lookup_key: u3,
};

const ImmToReg = struct {
    reg: RegisterId,
    immediate: u16,
};

const ImmToMem = struct {
    immediate: u16,
    displacement: [2]u8,
    displacement_size: u8,
    displacement_only: bool,
    rm_lookup_key: u3,
    w: u1,
};

const RegToFromRegMem = struct {
    params: union(enum) {
        regToFromReg: RegToFromReg,
        regToFromMem: RegToFromMem,
    },
    size: u8,
};

const ImmToRegMem = struct {
    params: union(enum) {
        immToReg: ImmToReg,
        immToMem: ImmToMem,
    },
    size: u8,
};

const InstructionType = enum {
    mov,
    add,
};

const Instruction = struct {
    type: union(InstructionType) {
        mov: union(enum) {
            regToFromReg: RegToFromReg,
            regToFromMem: RegToFromMem,
            immToReg: ImmToReg,
            immToMem: ImmToMem,
        },
        add: union(enum) {
            regToFromReg: RegToFromReg,
            regToFromMem: RegToFromMem,
            immToReg: ImmToReg,
            immToMem: ImmToMem,
        },
    },
    size: u8,
};

const RegisterId = enum {
    // 0b00xx => sp, bp, si, di
    // 0b01xx => low a, b, c, or d
    // 0b10xx => high a, b, c, or d
    // 0b11xx => wide a, b, c, or d
    sp,
    bp,
    si,
    di,
    al,
    bl,
    cl,
    dl,
    ah,
    bh,
    ch,
    dh,
    ax,
    bx,
    cx,
    dx,
};

fn name(register_id: RegisterId) []const u8 {
    return switch (register_id) {
        .ax => "ax",
        .bx => "bx",
        .cx => "cx",
        .dx => "dx",
        .al => "al",
        .bl => "bl",
        .cl => "cl",
        .dl => "dl",
        .ah => "ah",
        .bh => "bh",
        .ch => "ch",
        .dh => "dh",
        .sp => "sp",
        .bp => "bp",
        .si => "si",
        .di => "di",
    };
}

fn regFieldEncoding(w: u1, reg: u3) RegisterId {
    return reg_field_encoding[(@as(u4, w) << 3) | reg];
}

// access with 4 bit index: (w << 3) | reg
const reg_field_encoding: [16]RegisterId = .{
    .al,
    .cl,
    .dl,
    .bl,
    .ah,
    .ch,
    .dh,
    .bh,
    .ax,
    .cx,
    .dx,
    .bx,
    .sp,
    .bp,
    .si,
    .di,
};

const mov_effective_address_calculation_string: [8][]const u8 = .{
    "bx + si",
    "bx + di",
    "bp + si",
    "bp + di",
    "si",
    "di",
    "bp",
    "bx",
};

fn get_mem_label(buffer: []u8, displacement_only: bool, displacement_size: u8, displacement_bytes: [2]u8, rm_lookup_key: u3) std.fmt.BufPrintError![]u8 {
    std.debug.assert(buffer.len >= 17);
    if (displacement_only) {
        std.debug.assert(displacement_size == 2);
        const displacement: u16 = extractUnsignedWord(&displacement_bytes, true);
        return std.fmt.bufPrint(buffer, "[{d}]", .{displacement});
    } else {
        const mem_without_displacement = mov_effective_address_calculation_string[rm_lookup_key];
        var displacement: i16 = if (displacement_size == 0) 0 else extractSignedWord(&displacement_bytes, displacement_size == 2);
        if (displacement == 0) {
            return std.fmt.bufPrint(buffer, "[{s}]", .{mem_without_displacement});
        } else {
            std.debug.assert(displacement_size == 1 or displacement_size == 2);
            const signed: bool = displacement < 0;
            if (signed) {
                displacement *= -1;
            }
            return std.fmt.bufPrint(buffer, "[{s} {s} {d}]", .{ mem_without_displacement, if (signed) "-" else "+", displacement });
        }
    }
}

fn printRegToFromMem(writer: std.fs.File.Writer, instruction_type: InstructionType, data: *const RegToFromMem) !void {
    var mem_label_buffer: [17]u8 = undefined;
    const mem_label = try get_mem_label(&mem_label_buffer, data.displacement_only, data.displacement_size, data.displacement, data.rm_lookup_key);
    const reg_label = name(data.reg);

    try writer.print("{s} {s}, {s}\n", .{ getInstructionTypeString(instruction_type), if (data.d) reg_label else mem_label, if (data.d) mem_label else reg_label });
}

fn printRegToFromReg(writer: std.fs.File.Writer, instruction_type: InstructionType, data: *const RegToFromReg) !void {
    try writer.print("{s} {s}, {s}\n", .{
        getInstructionTypeString(instruction_type),
        name(data.dst_reg),
        name(data.src_reg),
    });
}

fn printImmToReg(writer: std.fs.File.Writer, instruction_type: InstructionType, data: *const ImmToReg) !void {
    try writer.print("{s} {s}, {d}\n", .{ getInstructionTypeString(instruction_type), name(data.reg), data.immediate });
}

fn printImmToMem(writer: std.fs.File.Writer, instruction_type: InstructionType, data: *const ImmToMem) !void {
    var mem_label_buffer: [17]u8 = undefined;
    const mem_label = try get_mem_label(&mem_label_buffer, data.displacement_only, data.displacement_size, data.displacement, data.rm_lookup_key);

    try writer.print("{s} {s} {s}, {d}\n", .{
        getInstructionTypeString(instruction_type),
        if (data.w == 0) "byte" else "word",
        mem_label,
        data.immediate,
    });
}

fn getInstructionTypeString(instruction_type: InstructionType) []const u8 {
    return switch (instruction_type) {
        .mov => "mov",
        .add => "add",
    };
}

fn extractModRegRm(data: u8) struct { u2, u3, u3 } {
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

fn getAccRegId(wide: bool) RegisterId {
    return if (wide) RegisterId.ax else RegisterId.al;
}

fn createRegToFromRegMem(d: bool, w: u1, mod: u2, reg: u3, rm: u3, displacement: [*]const u8) RegToFromRegMem {
    const reg_id = regFieldEncoding(w, reg);
    if (mod == 0b11) {
        const rm_id = regFieldEncoding(w, rm);

        return .{
            .params = .{
                .regToFromReg = .{
                    .dst_reg = if (d) reg_id else rm_id,
                    .src_reg = if (d) rm_id else reg_id,
                },
            },
            .size = 2,
        };
    } else {
        // mod = 00, 01, or 10
        const displacement_only = mod == 0b00 and rm == 0b110;
        const displacement_size: u8 = if (displacement_only) 2 else if (mod == 0b11) 0 else mod;
        var result: RegToFromRegMem = .{
            .params = .{
                .regToFromMem = .{
                    .reg = reg_id,
                    .displacement_size = displacement_size,
                    .displacement = undefined,
                    .rm_lookup_key = rm,
                    .d = d,
                    .displacement_only = displacement_only,
                },
            },
            .size = if (mod == 0b10 or displacement_only) @as(u8, 4) else if (mod == 0b01) @as(u8, 3) else @as(u8, 2),
        };
        @memcpy(result.params.regToFromMem.displacement[0..displacement_size], displacement[0..displacement_size]);
        return result;
    }
}

fn createImmToRegMem(mod: u2, rm: u3, s: u1, w: u1, data: [*]const u8) ImmToRegMem {
    const displacement_only = mod == 0b00 and rm == 0b110;
    const displacement_size: u8 = if (mod == 0b11) 0 else if (displacement_only) 2 else mod;
    const immediate_index_offset: u8 = 2 + displacement_size;
    const immediate: u16 = extractUnsignedWord(data + immediate_index_offset, s == 0 and w == 1);

    if (mod == 0b11) {
        // imm to reg
        // TODO(TB): not sure how to test this
        return .{
            .params = .{
                .immToReg = .{
                    .reg = regFieldEncoding(w, rm),
                    .immediate = immediate,
                },
            },
            .size = 3 + @as(u8, w),
        };
    } else {
        // imm to mem
        var result: ImmToRegMem = .{
            .params = .{
                .immToMem = .{
                    .immediate = immediate,
                    .displacement_only = displacement_only,
                    .displacement_size = displacement_size,
                    .rm_lookup_key = rm,
                    .w = w,
                    .displacement = undefined,
                },
            },
            .size = 3 + displacement_size + @as(u8, w),
        };
        @memcpy(result.params.immToMem.displacement[0..displacement_size], data[2 .. 2 + displacement_size]);
        return result;
    }
}

fn decode(allocator: std.mem.Allocator, data: []const u8) anyerror!void {
    var instructions = try std.ArrayList(Instruction).initCapacity(allocator, data.len / 2);
    defer instructions.deinit();

    var out = std.io.getStdOut();
    const writer = out.writer();
    _ = try out.write("\nbits 16\n\n");
    var i: usize = 0;

    while (i < data.len) {
        if ((data[i] & 0b11110000) == 0b10110000) {
            // mov imm to reg
            const w: u1 = @intCast((data[i] & 0b00001000) >> 3);
            var instruction: *Instruction = try instructions.addOne();
            instruction.type = .{ .mov = .{ .immToReg = undefined } };
            instruction.type.mov.immToReg.reg = regFieldEncoding(w, @intCast(data[i] & 0b00000111));
            instruction.type.mov.immToReg.immediate = extractUnsignedWord(data.ptr + i + 1, w != 0);
            instruction.size = 2 + @as(u8, w);
            i += instruction.size;
        } else if ((data[i] & 0b11111100) == 0b10001000) {
            // mov reg to/from reg/mem
            const d: bool = data[i] & 0b00000010 != 0;
            const w: u1 = @intCast(data[i] & 0b00000001);

            const mod, const reg, const rm = extractModRegRm(data[i + 1]);
            const displacement: [*]const u8 = data.ptr + i + 2;
            const params = createRegToFromRegMem(d, w, mod, reg, rm, displacement);
            var instruction: *Instruction = try instructions.addOne();
            instruction.type = .{ .mov = switch (params.params) {
                .regToFromReg => |specific_params| .{
                    .regToFromReg = specific_params,
                },
                .regToFromMem => |specific_params| .{
                    .regToFromMem = specific_params,
                },
            } };
            instruction.size = params.size;
            i += instruction.size;
        } else if ((data[i] & 0b11111110) == 0b11000110) {
            // mov imm to reg/mem
            const w: u1 = @intCast(data[i] & 0b1);
            const mod, const reg, const rm = extractModRegRm(data[i + 1]);
            std.debug.assert(reg == 0);
            const params = createImmToRegMem(mod, rm, 0, w, data[i..].ptr);
            var instruction: *Instruction = try instructions.addOne();
            instruction.type = .{ .mov = switch (params.params) {
                .immToReg => |specific_params| .{
                    .immToReg = specific_params,
                },
                .immToMem => |specific_params| .{
                    .immToMem = specific_params,
                },
            } };
            instruction.size = params.size;
            i += instruction.size;
        } else if ((data[i] & 0b11111100) == 0b10100000) {
            // mem to/from acc
            const d: bool = data[i] & 0b00000010 == 0;
            const w: u1 = @intCast(data[i] & 0b1);

            var instruction: *Instruction = try instructions.addOne();
            instruction.type = .{ .mov = .{ .regToFromMem = .{
                .reg = getAccRegId(w != 0),
                .displacement = undefined,
                .displacement_size = 2,
                .rm_lookup_key = 0,
                .d = d,
                .displacement_only = true,
            } } };
            @memcpy(&instruction.type.mov.regToFromMem.displacement, data[i + 1 .. i + 3]);
            instruction.size = 3;
            i += instruction.size;
        } else if ((data[i] & 0b11111100) == 0b00000000) {
            // add reg/mem to/from reg
            const d = (data[i] & 0b00000010) != 0;
            const w: u1 = @intCast(data[i] & 0b00000001);
            const mod, const reg, const rm = extractModRegRm(data[i + 1]);
            const displacement: [*]const u8 = data.ptr + i + 2;

            var instruction: *Instruction = try instructions.addOne();
            const params = createRegToFromRegMem(d, w, mod, reg, rm, displacement);
            instruction.type = .{ .add = switch (params.params) {
                .regToFromReg => |specific_params| .{
                    .regToFromReg = specific_params,
                },
                .regToFromMem => |specific_params| .{
                    .regToFromMem = specific_params,
                },
            } };
            instruction.size = params.size;
            i += instruction.size;
        } else if ((data[i] & 0b11111100) == 0b10000000) {
            const s: u1 = @intCast((data[i] & 0b10) >> 1);
            const w: u1 = @intCast(data[i] & 0b1);
            const mod, const reg, const rm = extractModRegRm(data[i + 1]);
            std.debug.assert(reg == 0);
            const params = createImmToRegMem(mod, rm, s, w, data[i..].ptr);
            var instruction: *Instruction = try instructions.addOne();
            instruction.type = .{ .add = switch (params.params) {
                .immToReg => |specific_params| .{
                    .immToReg = specific_params,
                },
                .immToMem => |specific_params| .{
                    .immToMem = specific_params,
                },
            } };
            instruction.size = params.size;
            i += instruction.size;
        } else if ((data[i] & 0b11111110) == 0b00000010) {
            // add imm to acc
            // TODO(TB): how to test this?
            const w: bool = (data[i] & 0b1) != 0;
            const imm: u16 = extractUnsignedWord(data.ptr + i + 1, w);
            var instruction: *Instruction = try instructions.addOne();
            instruction.type = .{
                .add = .{ .immToReg = .{
                    .immediate = imm,
                    .reg = getAccRegId(w),
                } },
            };
            instruction.size = if (w) 3 else 2;
            i += instruction.size;
        } else {
            var buffer: [256]u8 = undefined;
            const str = std.fmt.bufPrint(&buffer, "unknown instruction opcode 0b{b} at instruction index {} and byte index {}\n", .{ data[i], instructions.items.len, i }) catch {
                @panic("unknown instruction opcode");
            };
            @panic(str);
        }
    }

    for (instructions.items) |instruction| {
        switch (instruction.type) {
            .mov => |args_kind| {
                switch (args_kind) {
                    .regToFromMem => |d| {
                        try printRegToFromMem(writer, .mov, &d);
                    },
                    .regToFromReg => |d| {
                        try printRegToFromReg(writer, .mov, &d);
                    },
                    .immToReg => |d| {
                        try printImmToReg(writer, .mov, &d);
                    },
                    .immToMem => |d| {
                        try printImmToMem(writer, .mov, &d);
                    },
                }
            },
            .add => |args_kind| {
                switch (args_kind) {
                    .regToFromReg => |d| {
                        try printRegToFromReg(writer, .add, &d);
                    },
                    .regToFromMem => |d| {
                        try printRegToFromMem(writer, .add, &d);
                    },
                    .immToReg => |d| {
                        try printImmToReg(writer, .add, &d);
                    },
                    .immToMem => |d| {
                        try printImmToMem(writer, .add, &d);
                    },
                }
            },
        }
    }
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
    try decode(gpa, data);
}
