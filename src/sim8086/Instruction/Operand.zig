const std = @import("std");
const Register = @import("../Register.zig");
const Memory = @import("../Memory.zig");

const Self = @This();

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

pub fn getLabel(operand: Self, buffer: []u8) []u8 {
    // TODO(TB): figure out the max length required here
    std.debug.assert(buffer.len >= 32);
    switch (operand.type) {
        .register => |data| {
            return data.getLabel(buffer);
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
                    return std.fmt.bufPrint(buffer, "[{s}]", .{data.reg[0].getLabel(&reg_label_buffer)}) catch unreachable;
                } else {
                    const negative = data.displacement < 0;
                    return std.fmt.bufPrint(buffer, "[{s}{s}{d}]", .{
                        data.reg[0].getLabel(&reg_label_buffer),
                        if (negative) "-" else "+",
                        if (negative) data.displacement * -1 else data.displacement,
                    }) catch unreachable;
                }
            } else {
                var reg_label_buffer: [2][2]u8 = undefined;
                const reg_0_label = data.reg[0].getLabel(&reg_label_buffer[0]);
                const reg_1_label = data.reg[1].getLabel(&reg_label_buffer[1]);
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
            return std.fmt.bufPrint(buffer, "${s}{d}", .{ if (negative) "-" else "+", positive_data_plus_2 }) catch unreachable;
        },
        .none => {
            return buffer[0..0];
        },
    }
}
