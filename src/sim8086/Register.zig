const std = @import("std");
const Size = @import("Size.zig").Size;

const Self = @This();

pub const Index = enum {
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

pub const Offset = enum(u8) {
    none = 0,
    byte = 1,
};

pub const al: Self = .{ .index = .a, .offset = .none, .size = .byte };
pub const bl: Self = .{ .index = .b, .offset = .none, .size = .byte };
pub const cl: Self = .{ .index = .c, .offset = .none, .size = .byte };
pub const dl: Self = .{ .index = .d, .offset = .none, .size = .byte };
pub const ah: Self = .{ .index = .a, .offset = .byte, .size = .byte };
pub const bh: Self = .{ .index = .b, .offset = .byte, .size = .byte };
pub const ch: Self = .{ .index = .c, .offset = .byte, .size = .byte };
pub const dh: Self = .{ .index = .d, .offset = .byte, .size = .byte };
pub const ax: Self = .{ .index = .a, .offset = .none, .size = .word };
pub const bx: Self = .{ .index = .b, .offset = .none, .size = .word };
pub const cx: Self = .{ .index = .c, .offset = .none, .size = .word };
pub const dx: Self = .{ .index = .d, .offset = .none, .size = .word };
pub const sp: Self = .{ .index = .sp, .offset = .none, .size = .word };
pub const bp: Self = .{ .index = .bp, .offset = .none, .size = .word };
pub const si: Self = .{ .index = .si, .offset = .none, .size = .word };
pub const di: Self = .{ .index = .di, .offset = .none, .size = .word };
pub const none: Self = .{ .index = .none, .offset = .none, .size = .word };

index: Index,
offset: Offset,
size: Size,

pub fn getGeneralPurposeRegisterLabelLetter(reg: Self.Index) u8 {
    return switch (reg) {
        .a => 'a',
        .b => 'b',
        .c => 'c',
        .d => 'd',
        else => unreachable,
    };
}

pub fn getLabel(register: Self, buffer: []u8) []u8 {
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

pub const reg_field_encoding: [16]Self = .{ Self.al, Self.cl, Self.dl, Self.bl, Self.ah, Self.ch, Self.dh, Self.bh, Self.ax, Self.cx, Self.dx, Self.bx, Self.sp, Self.bp, Self.si, Self.di };

pub fn regFieldEncoding(w: u1, reg: u3) Self {
    return reg_field_encoding[@as(u4, w) << 3 | reg];
}
