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

const InstructionType = enum {
    mov,
};

const Instruction = struct {
    type: union(InstructionType) {
        mov: union(enum) {
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
    SP,
    BP,
    SI,
    DI,
    AL,
    BL,
    CL,
    DL,
    AH,
    BH,
    CH,
    DH,
    AX,
    BX,
    CX,
    DX,
};

fn name(register_id: RegisterId) []const u8 {
    return switch (register_id) {
        .AX => "ax",
        .BX => "bx",
        .CX => "cx",
        .DX => "dx",
        .AL => "al",
        .BL => "bl",
        .CL => "cl",
        .DL => "dl",
        .AH => "ah",
        .BH => "bh",
        .CH => "ch",
        .DH => "dh",
        .SP => "sp",
        .BP => "bp",
        .SI => "si",
        .DI => "di",
    };
}

fn regFieldEncoding(w: u1, reg: u3) RegisterId {
    return reg_field_encoding[(@as(u4, w) << 3) | reg];
}

// access with 4 bit index: (w << 3) | reg
const reg_field_encoding: [16]RegisterId = .{
    .AL,
    .CL,
    .DL,
    .BL,
    .AH,
    .CH,
    .DH,
    .BH,
    .AX,
    .CX,
    .DX,
    .BX,
    .SP,
    .BP,
    .SI,
    .DI,
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
        const displacement: u16 = @as(u16, displacement_bytes[0]) | (@as(u16, displacement_bytes[1]) << 8);
        return std.fmt.bufPrint(buffer, "[{d}]", .{displacement});
    } else {
        const mem_without_displacement = mov_effective_address_calculation_string[rm_lookup_key];
        var displacement: i16 = if (displacement_size == 0) 0 else if (displacement_size == 1) @as(i16, @as(i8, @bitCast(displacement_bytes[0]))) else @as(i16, displacement_bytes[0]) | @as(i16, @bitCast(@as(u16, displacement_bytes[1]) << 8));
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

    try writer.print("{s} {s}, {s}\n", .{
        getInstructionTypeString(instruction_type),
        if (data.d) reg_label else mem_label,
        if (data.d) mem_label else reg_label
    });
}

fn getInstructionTypeString(instruction_type: InstructionType) []const u8 {
    return switch (instruction_type) {
        .mov => "mov"
    };
}

fn decode(allocator: std.mem.Allocator, data: []const u8) anyerror!void {
    var instructions = try std.ArrayList(Instruction).initCapacity(allocator, data.len / 2);
    defer instructions.deinit();

    var out = std.io.getStdOut();
    var writer = out.writer();
    _ = try out.write("\nbits 16\n\n");
    var i: usize = 0;

    while (i < data.len) {
        if ((data[i] & 0b11110000) == 0b10110000) {
            // mov imm to reg
            const w: u1 = @intCast((data[i] & 0b00001000) >> 3);
            var instruction: *Instruction = try instructions.addOne();
            instruction.type = .{ .mov = .{ .immToReg = undefined } };
            instruction.type.mov.immToReg.reg = regFieldEncoding(w, @intCast(data[i] & 0b00000111));
            instruction.type.mov.immToReg.immediate = if (w == 0) data[i + 1] else data[i + 1] | (@as(u16, data[i + 2]) << 8);
            instruction.size = 2 + @as(u8, w);
            i += instruction.size;
        } else if ((data[i] & 0b11111100) == 0b10001000) {
            const d: bool = data[i] & 0b00000010 != 0;
            const w: u1 = @intCast(data[i] & 0b00000001);

            const mod: u2 = @intCast((data[i + 1] & 0b11000000) >> 6);
            const reg: u3 = @intCast((data[i + 1] & 0b00111000) >> 3);
            const rm: u3 = @intCast(data[i + 1] & 0b00000111);
            const reg_id = regFieldEncoding(w, reg);

            if (mod == 0b11) {
                const rm_id = regFieldEncoding(w, rm);

                var instruction: *Instruction = try instructions.addOne();
                instruction.type = .{ .mov = .{ .regToFromReg = undefined } };
                instruction.type.mov.regToFromReg.dst_reg = if (d) reg_id else rm_id;
                instruction.type.mov.regToFromReg.src_reg = if (d) rm_id else reg_id;
                instruction.size = 2;
                i += instruction.size;
            } else {
                // mod = 00, 01, or 10
                const displacement_only = mod == 0b00 and rm == 0b110;
                const displacement_size: u8 = if (displacement_only) 2 else if (mod == 0b11) 0 else mod;
                var instruction: *Instruction = try instructions.addOne();
                instruction.type = .{ .mov = .{ .regToFromMem = .{
                    .reg = reg_id,
                    .displacement_size = displacement_size,
                    .displacement = undefined,
                    .rm_lookup_key = rm,
                    .d = d,
                    .displacement_only = displacement_only,
                } } };
                @memcpy(instruction.type.mov.regToFromMem.displacement[0..displacement_size], data[i + 2 .. i + 2 + displacement_size]);
                instruction.size = if (mod == 0b10 or displacement_only) 4 else if (mod == 0b01) 3 else 2;
                i += instruction.size;
            }
        } else if ((data[i] & 0b11111110) == 0b11000110) {
            // imm to reg/mem
            const w: u1 = @intCast(data[i] & 0b1);
            const mod: u2 = @intCast((data[i + 1] & 0b11000000) >> 6);
            std.debug.assert((data[i + 1] & 0b00111000) == 0);
            const rm: u3 = @intCast(data[i + 1] & 0b00000111);

            const displacement_only = mod == 0b00 and rm == 0b110;
            const displacement_size: u8 = if (mod == 0b11) 0 else if (displacement_only) 2 else mod;
            const immediate_index_offset: u8 = 2 + displacement_size;
            const immediate: u16 = if (w == 0) data[i + immediate_index_offset] else data[i + immediate_index_offset] | (@as(u16, data[i + immediate_index_offset + 1]) << 8);

            if (mod == 0b11) {
                // imm to reg
                // TODO(TB): not sure how to test this
                var instruction: *Instruction = try instructions.addOne();
                instruction.type = .{ .mov = .{ .immToReg = undefined } };
                instruction.type.mov.immToReg.reg = regFieldEncoding(w, rm);
                instruction.type.mov.immToReg.immediate = immediate;
                instruction.size = 3 + @as(u8, w);
                i += instruction.size;
            } else {
                // imm to mem
                var instruction: *Instruction = try instructions.addOne();
                instruction.type = .{ .mov = .{ .immToMem = undefined } };
                instruction.type.mov.immToMem.immediate = immediate;
                @memcpy(instruction.type.mov.immToMem.displacement[0..displacement_size], data[i + 2 .. i + 2 + displacement_size]);
                instruction.type.mov.immToMem.displacement_only = displacement_only;
                instruction.type.mov.immToMem.displacement_size = displacement_size;
                instruction.type.mov.immToMem.rm_lookup_key = rm;
                instruction.type.mov.immToMem.w = w;
                instruction.size = 3 + displacement_size + @as(u8, w);
                i += instruction.size;
            }
        } else if ((data[i] & 0b11111100) == 0b10100000) {
            // mem to/from acc
            const d: bool = data[i] & 0b00000010 == 0;
            const w: u1 = @intCast(data[i] & 0b1);

            var instruction: *Instruction = try instructions.addOne();
            instruction.type = .{ .mov = .{ .regToFromMem = .{
                .reg = if (w == 0) RegisterId.AL else RegisterId.AX,
                .displacement = undefined,
                .displacement_size = 2,
                .rm_lookup_key = 0,
                .d = d,
                .displacement_only = true,
            } } };
            @memcpy(&instruction.type.mov.regToFromMem.displacement, data[i + 1 .. i + 3]);
            instruction.size = 3;
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
                        try writer.print("mov {s}, {s}\n", .{ name(d.dst_reg), name(d.src_reg) });
                    },
                    .immToReg => |d| {
                        try writer.print("mov {s}, {d}\n", .{ name(d.reg), d.immediate });
                    },
                    .immToMem => |d| {
                        var mem_label_buffer: [17]u8 = undefined;
                        const mem_label = try get_mem_label(&mem_label_buffer, d.displacement_only, d.displacement_size, d.displacement, d.rm_lookup_key);

                        try writer.print("mov {s}, {s} {d}\n", .{ mem_label, if (d.w == 0) "byte" else "word", d.immediate });
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
