const std = @import("std");

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

const mov_effective_address_calculation_string: [8] []const u8 = .{
    "bx + si",
    "bx + di",
    "bp + si",
    "bp + di",
    "si",
    "di",
    "bp",
    "bx",
};

pub fn decode(data: []const u8) std.posix.WriteError!void {
    var out = std.io.getStdOut();
    var writer = out.writer();
    _ = try out.write("\nbits 16\n\n");
    var i: usize = 0;
    var instruction: usize = 0;

    while (i < data.len) {
        if ((data[i] & 0b11110000) == 0b10110000) {
            const w: u1 = @intCast((data[i] & 0b00001000) >> 3);
            const reg: u3 = @intCast(data[i] & 0b00000111);
            const reg_label = name(regFieldEncoding(w, reg));
            const immediate: u16 = if (w == 0) data[i + 1] else data[i + 1] | (@as(u16, data[i + 2]) << 8);
            i += 1 + @as(usize, w);
            try writer.print("mov {s}, {d}\n", .{reg_label, immediate});
        } else if ((data[i] & 0b11111100) == 0b10001000) {
            const d: bool = data[i] & 0b00000010 != 0;
            const w: u1 = @intCast(data[i] & 0b00000001);
            i += 1;

            const mod: u2 = @intCast((data[i] & 0b11000000) >> 6);
            const reg: u3 = @intCast((data[i] & 0b00111000) >> 3);
            const rm: u3 = @intCast(data[i] & 0b00000111);
            const reg_label = name(regFieldEncoding(w, reg));

            if (mod == 0b11) {
                const rm_label = name(regFieldEncoding(w, rm));

                try writer.print("mov {s}, {s}\n", .{if (d) reg_label else rm_label, if (d) rm_label else reg_label});
            } else {
                // mod = 00, 01, or 10
                if (mod == 0b00) {
                    if (rm == 0b110) {
                        const address: u16 = data[i + 1] | (@as(u16, data[i + 2]) << 8);
                        var rm_label_buffer: [7]u8 = undefined;
                        const rm_label = try std.fmt.bufPrint(&rm_label_buffer, "[{d}]", .{address});
                        try writer.print("mov {s}, {s}\n", .{if (d) reg_label else rm_label, if (d) rm_label else reg_label});
                        i += 2;
                    } else {
                        var rm_label_buffer: [9]u8 = undefined;
                        const rm_label = try std.fmt.bufPrint(&rm_label_buffer, "[{s}]", .{mov_effective_address_calculation_string[rm]});
                        try writer.print("mov {s}, {s}\n", .{if (d) reg_label else rm_label, if (d) rm_label else reg_label});
                    }
                } else {
                    const address: u16 = if (mod == 0b01) @as(u16, data[i + 1])
                        else data[i + 1] | (@as(u16, data[i + 2]) << 8);
                    var address_string_buffer: [5]u8 = undefined;
                    const address_string = try std.fmt.bufPrint(&address_string_buffer, "{d}", .{address});
                    const rm_label_without_direct_address_addition = mov_effective_address_calculation_string[rm];
                    // ax + bx + xxxxx
                    var rm_label_buffer: [17]u8 = undefined;
                    const rm_label = try if (address == 0)
                        std.fmt.bufPrint(&rm_label_buffer, "[{s}]", .{rm_label_without_direct_address_addition}) else
                        std.fmt.bufPrint(&rm_label_buffer, "[{s} + {s}]", .{rm_label_without_direct_address_addition, address_string});
                    try writer.print("mov {s}, {s}\n", .{if (d) reg_label else rm_label, if (d) rm_label else reg_label});
                    i += mod;
                }
            }
        } else {
            var buffer: [256] u8 = undefined;
            const str = std.fmt.bufPrint(&buffer, "unknown instruction opcode 0b{b} at instruction index {} and byte index {}\n", .{data[i], instruction, i}) catch {
                @panic("unknown instruction opcode");
            };
            @panic(str);
        }
        i += 1;
        instruction += 1;
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
    try decode(data);
}
