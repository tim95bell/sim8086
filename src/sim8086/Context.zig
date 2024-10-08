const std = @import("std");
const Instruction = @import("Instruction.zig");

pub const Context = struct {
    memory: [1028 * 1028 * 1028]u8,
    program_size: u16,
    register: Registers,
    flags: u16,

    pub fn init(self: *Context) void {
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

        @memset(&self.register.word, 0);
        @memset(&self.memory, 0);
        self.flags = 0;
    }
};

pub const Registers = extern union {
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
    byte: [@typeInfo(Instruction.RegisterIndex).Enum.fields.len - 1][2]u8,
    word: [@typeInfo(Instruction.RegisterIndex).Enum.fields.len - 1]u16,
};
