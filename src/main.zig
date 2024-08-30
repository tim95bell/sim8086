const std = @import("std");

const Instruction = struct {
    type: union(enum) {
        movRegToFromReg: struct {
            dst_reg: RegisterId,
            src_reg: RegisterId,
        },
        movRegToFromMem: struct {
            reg: RegisterId,
            displacement: u16,
            rm_lookup_key: u3,
            d: bool,
            displacement_only: bool,
        },
        movImmToReg: struct {
            reg: RegisterId,
            immediate: u16,
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

fn get_mem_label(buffer: []u8, displacement_only: bool, displacement: u16, rm_lookup_key: u3) std.fmt.BufPrintError![]u8 {
    std.debug.assert(buffer.len >= 17);
    if (displacement_only) {
        return std.fmt.bufPrint(buffer, "[{d}]", .{displacement});
    } else {
        const mem_without_displacement = mov_effective_address_calculation_string[rm_lookup_key];
        if (displacement == 0) {
            return std.fmt.bufPrint(buffer, "[{s}]", .{mem_without_displacement});
        } else {
            return std.fmt.bufPrint(buffer, "[{s} + {d}]", .{ mem_without_displacement, displacement });
        }
    }
}

pub fn decode(allocator: std.mem.Allocator, data: []const u8) anyerror!void {
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
            instruction.type = .{ .movImmToReg = undefined };
            instruction.type.movImmToReg.reg = regFieldEncoding(w, @intCast(data[i] & 0b00000111));
            instruction.type.movImmToReg.immediate = if (w == 0) data[i + 1] else data[i + 1] | (@as(u16, data[i + 2]) << 8);
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
                instruction.type = .{ .movRegToFromReg = undefined };
                instruction.type.movRegToFromReg.dst_reg = if (d) reg_id else rm_id;
                instruction.type.movRegToFromReg.src_reg = if (d) rm_id else reg_id;
                instruction.size = 2;
                i += instruction.size;
            } else {
                // mod = 00, 01, or 10
                const displacement_only = mod == 0b00 and rm == 0b110;
                var instruction: *Instruction = try instructions.addOne();
                instruction.type = .{ .movRegToFromMem = .{
                    .reg = reg_id,
                    .displacement = if (mod == 0b10 or displacement_only) data[i + 2] | (@as(u16, data[i + 3]) << 8) else if (mod == 0b01) @as(u16, data[i + 2]) else 0,
                    .rm_lookup_key = rm,
                    .d = d,
                    .displacement_only = displacement_only,
                } };
                instruction.size = if (mod == 0b10 or displacement_only) 4 else if (mod == 0b01) 3 else 2;
                i += instruction.size;
            }
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
            .movRegToFromMem => |d| {
                var mem_label_buffer: [17]u8 = undefined;
                const mem_label = try get_mem_label(&mem_label_buffer, d.displacement_only, d.displacement, d.rm_lookup_key);
                const reg_label = name(d.reg);

                try writer.print("mov {s}, {s}\n", .{ if (d.d) reg_label else mem_label, if (d.d) mem_label else reg_label });
            },
            .movRegToFromReg => |d| {
                try writer.print("mov {s}, {s}\n", .{ name(d.dst_reg), name(d.src_reg) });
            },
            .movImmToReg => |d| {
                try writer.print("mov {s}, {d}\n", .{ name(d.reg), d.immediate });
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
