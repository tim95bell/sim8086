const std = @import("std");
const String = @import("String.zig");

const Self = @This();

pub const Token = struct {
    len: usize,
    index: usize,
    type: union(enum) {
        t_invalid: void,
        t_end_of_stream: void,
        t_open_object: void,
        t_close_object: void,
        t_open_array: void,
        t_close_array: void,
        t_colon: void,
        t_comma: void,
        t_null: void,
        t_number: f64,
        t_boolean: bool,
        t_string: String,
    },

    pub fn deinit(self: *const Token, allocator: std.mem.Allocator) void {
        switch (self.type) {
            .t_string => |data| {
                data.deinit(allocator);
            },
            else => {},
        }
    }

    pub fn isTerminal(self: *const Token) bool {
        return self.type == .t_invalid or self.type == .t_end_of_stream;
    }

    pub fn print(self: *const Token) void {
        switch (self.type) {
            .t_invalid => std.debug.print("Invalid(index: {d})\n", .{self.index}),
            .t_end_of_stream => std.debug.print("EndOfStream(index: {d})\n", .{self.index}),
            .t_open_object => std.debug.print("OpenObject(index: {d})\n", .{self.index}),
            .t_close_object => std.debug.print("CloseObject(index: {d})\n", .{self.index}),
            .t_open_array => std.debug.print("OpenArray(index: {d})\n", .{self.index}),
            .t_close_array => std.debug.print("CloseArray(index: {d})\n", .{self.index}),
            .t_colon => std.debug.print("Colon(index: {d})\n", .{self.index}),
            .t_comma => std.debug.print("Comma(index: {d})\n", .{self.index}),
            .t_null => std.debug.print("Null(index: {d}, len: {d})\n", .{ self.index, self.len }),
            .t_number => |data| std.debug.print("Number(index: {d}, len: {d}, value: {d})\n", .{ self.index, self.len, data }),
            .t_boolean => |data| std.debug.print("Boolean(index: {d}, len: {d}, value: {s})\n", .{ self.index, self.len, if (data) "true" else "false" }),
            .t_string => |data| std.debug.print("String(index: {d}, len: {d}, value: {s}, value_len: {d})\n", .{ self.index, self.len, data.getBufferConst(), data.len }),
        }
    }
};

input: []const u8,
input_index: usize = 0,
token: Token = .{ .type = .t_invalid, .index = 0, .len = 0 },
peeked: bool = false,

pub fn create(input: []const u8) Self {
    return .{
        .input = input,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.token.deinit(allocator);
}

fn skipWhiteSpace(self: *Self) void {
    while (self.input_index < self.input.len and isWhiteSpace(self.input[self.input_index])) {
        self.input_index += 1;
    }
}

pub fn peek(self: *Self, allocator: std.mem.Allocator) void {
    if (self.peeked) {
        return;
    }

    self.token.deinit(allocator);
    self.peeked = true;
    self.skipWhiteSpace();

    if (self.input_index >= self.input.len) {
        self.token = .{ .type = .t_end_of_stream, .len = 0, .index = self.input_index };
        return;
    }

    self.token = switch (self.input[self.input_index]) {
        '{' => .{ .type = .t_open_object, .len = 1, .index = self.input_index },
        '}' => .{ .type = .t_close_object, .len = 1, .index = self.input_index },
        '[' => .{ .type = .t_open_array, .len = 1, .index = self.input_index },
        ']' => .{ .type = .t_close_array, .len = 1, .index = self.input_index },
        ':' => .{ .type = .t_colon, .len = 1, .index = self.input_index },
        ',' => .{ .type = .t_comma, .len = 1, .index = self.input_index },
        'n' => if (matchSymbol(self.input, self.input_index + 1, "ull"))
            .{ .type = .t_null, .len = 4, .index = self.input_index }
        else
            .{ .type = .t_invalid, .len = 0, .index = self.input_index },
        't' => if (matchSymbol(self.input, self.input_index + 1, "rue"))
            .{ .type = .{ .t_boolean = true }, .len = 4, .index = self.input_index }
        else
            .{ .type = .t_invalid, .len = 0, .index = self.input_index },
        'f' => if (matchSymbol(self.input, self.input_index + 1, "alse"))
            .{ .type = .{ .t_boolean = false }, .len = 5, .index = self.input_index }
        else
            .{ .type = .t_invalid, .len = 0, .index = self.input_index },
        '"' => lexStringAfterOpenQuote(allocator, self.input, self.input_index + 1),
        else => lexNumber(self.input, self.input_index),
    };
}

pub fn next(self: *Self, allocator: std.mem.Allocator) void {
    // TODO(TB): will this be a problem for the deinit?
    self.peek(allocator);
    self.input_index += self.token.len;
    self.peeked = false;
}

fn lexString(allocator: std.mem.Allocator, input: []const u8, start_index: usize) Token {
    if (input[start_index] == '"') {
        return lexStringAfterOpenQuote(allocator, input[1..], start_index + 1);
    }

    return .{ .type = .invalid, .len = 0 };
}

fn lexStringAfterOpenQuote(allocator: std.mem.Allocator, input: []const u8, start_index: usize) Token {
    // NOTE(TB): only supporting escaping " and \
    var last_char_was_escape = false;
    var index = start_index;
    var str_len: usize = 0;
    var has_escape = false;
    while (index < input.len) {
        const c = input[index];
        index += 1;
        if (last_char_was_escape) {
            str_len += 1;
            if (c == '"' or c == '\\') {
                last_char_was_escape = false;
            } else {
                std.debug.print("invalid json string escape \\{c}\n", .{c});
                return .{ .type = .t_invalid, .len = 0, .index = start_index - 1 };
            }
        } else {
            if (c == '"') {
                break;
            }

            if (c == '\\') {
                last_char_was_escape = true;
                has_escape = true;
            } else {
                last_char_was_escape = false;
                str_len += 1;
            }
        }
    }

    const len = index - (start_index - 1);
    var result: Token = .{ .len = len, .index = start_index - 1, .type = .{
        .t_string = .{
            .len = str_len,
            .type = undefined,
        },
    } };
    var buffer: [*]u8 = undefined;
    if (str_len <= 64) {
        result.type.t_string.type = .{ .small_string = undefined };
        buffer = &result.type.t_string.type.small_string;
    } else {
        buffer = (allocator.alloc(u8, str_len) catch {
            std.debug.print("failed to allocate buffer for string token\n", .{});
            return .{ .type = .t_invalid, .len = 0, .index = start_index - 1 };
        }).ptr;

        result.type.t_string.type = .{ .large_string = buffer };
    }
    if (has_escape) {
        // TODO(TB): how to make this faster when there is an escape? memcpy chunks between escapes?
        var str_index: usize = 0;
        var input_index = start_index;
        while (str_index < str_len) {
            if (input[input_index] == '\\') {
                // NOTE(TB): escape character, only supported escapes are '"' and '\', which are just themsleves, so just skip this escape character
                input_index += 1;
            }

            buffer[str_index] = input[input_index];
            input_index += 1;
            str_index += 1;
        }
    } else {
        @memcpy(buffer[0..str_len], input[start_index .. start_index + str_len]);
    }

    return result;
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn isNumeric(c: u8) bool {
    return (c >= '0' and c <= '9');
}

fn isLegalSymbolFirstCharacter(c: u8) bool {
    // alpha OR _
    return isAlpha(c) or c == '_';
}

fn isLegalSymbolRestCharacter(c: u8) bool {
    // alphanumeric OR _
    return isLegalSymbolFirstCharacter(c) or isNumeric(c);
}

fn isWhiteSpace(x: u8) bool {
    return x == ' ' or x == '\n' or x == '\t';
}

fn getCharNumericValue(c: u8) u8 {
    std.debug.assert(isNumeric(c));
    return c - '0';
}

fn matchSymbol(input: []const u8, index: usize, keyword: []const u8) bool {
    return (index + keyword.len <= input.len and
        std.mem.eql(u8, input[index .. index + keyword.len], keyword) and
        (index + keyword.len + 1 > input.len or !isLegalSymbolRestCharacter(input[index + keyword.len])));
}

fn lexNumber(input: []const u8, start_index: usize) Token {
    // TODO(TB): negative numbers
    std.debug.assert(start_index < input.len);
    var index = start_index;
    if (!isNumeric(input[index])) {
        return .{ .type = .t_invalid, .index = start_index, .len = 0 };
    }

    var result: f64 = @floatFromInt(getCharNumericValue(input[index]));
    index += 1;
    while (index < input.len and isNumeric(input[index])) {
        result *= 10;
        result += @floatFromInt(getCharNumericValue(input[index]));
        index += 1;
    }

    if (index < input.len) {
        if (input[index] == '.') {
            index += 1;

            if (index < input.len) {
                if (!isNumeric(input[index])) {
                    return .{ .type = .t_invalid, .index = start_index, .len = 0 };
                } else {
                    var index_past_decimal_point: f32 = 1;
                    result += @as(f64, @floatFromInt(getCharNumericValue(input[index]))) / std.math.pow(f32, 10, index_past_decimal_point);
                    index_past_decimal_point += 1;
                    index += 1;

                    while (index < input.len and isNumeric(input[index])) {
                        result += @as(f64, @floatFromInt(getCharNumericValue(input[index]))) / std.math.pow(f32, 10, index_past_decimal_point);
                        index_past_decimal_point += 1;
                        index += 1;
                    }
                }
            } else {
                return .{ .type = .t_invalid, .index = start_index, .len = 0 };
            }
        }
    }

    return .{ .type = .{ .t_number = result }, .index = start_index, .len = index - start_index };
}
