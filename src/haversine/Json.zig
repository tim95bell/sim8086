const std = @import("std");

pub const ItemType = enum { t_null, t_boolean, t_string, t_number, t_object, t_array };

pub const Item = union(ItemType) {
    t_null: void,
    t_boolean: bool,
    t_string: String,
    t_number: f64,
    t_object: std.AutoHashMap(Item, Item),
    t_array: std.ArrayList(Item),

    pub fn print(self: *const Item) void {
        switch (self.*) {
            .t_null => std.debug.print("null\n", .{}),
            .t_boolean => |data| std.debug.print("{s}\n", .{if (data) "true" else "false"}),
            .t_string => |data| std.debug.print("\"{s}\"\n", .{data.getBufferConst()}),
            .t_number => |data| std.debug.print("{d}\n", .{data}),
            .t_object => unreachable,
            .t_array => unreachable,
        }
    }

    pub fn deinit(self: *const Item, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .t_string => |data| {
                data.deinit(allocator);
            },
            // TODO(TB): deinit t_array and t_object?
            else => {},
        }
    }
};

pub fn parse(allocator: std.mem.Allocator, input: []const u8) ?Item {
    var tokenizer = Tokenizer.create(input);

    const item = parseNextItem(allocator, &tokenizer);
    if (item != null) {
        var token = tokenizer.next(allocator);
        defer token.deinit(allocator);
        if (token.type == .t_end_of_stream) {
            return item;
        }

        // TODO(TB): could this use errdefer?
        item.?.deinit(allocator);
    }

    return null;
}

fn parseNextItem(allocator: std.mem.Allocator, tokenizer: *Tokenizer) ?Item {
    var token = tokenizer.next(allocator);
    defer token.deinit(allocator);
    switch (token.type) {
        .t_open_object => return parseNextObject(allocator, tokenizer),
        .t_open_array => return parseNextArray(allocator, tokenizer),
        .t_null => return .t_null,
        .t_number => |data| return .{ .t_number = data },
        .t_boolean => |data| return .{ .t_boolean = data },
        .t_string => |*data| {
            const result = .{ .t_string = data.* };
            data.release();
            return result;
        },
        else => return null,
    }
}

fn parseNextObject(allocator: std.mem.Allocator, tokenizer: *Tokenizer) ?Item {
    // TODO(TB):
    _ = allocator;
    _ = tokenizer;
    return null;
}

fn parseNextArray(allocator: std.mem.Allocator, tokenizer: *Tokenizer) ?Item {
    // TODO(TB):
    _ = allocator;
    _ = tokenizer;
    return null;
}

pub const String = struct {
    const Self = @This();

    type: union(enum) {
        small_string: [32]u8,
        large_string: [*]u8,
    },
    len: usize,

    fn getBuffer(self: *Self) []u8 {
        return switch (self.type) {
            .small_string => |*data| data[0..self.len],
            .large_string => |data| data[0..self.len],
        };
    }

    fn getBufferConst(self: *const Self) []const u8 {
        return switch (self.type) {
            .small_string => |*data| data[0..self.len],
            .large_string => |data| data[0..self.len],
        };
    }

    // TODO(TB): should this be on const?
    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        switch (self.type) {
            .large_string => |data| allocator.free(data[0..self.len]),
            else => {},
        }
    }

    // NOTE(TB): used to remove ownership of the data so that deinit will not do anthing
    pub fn release(self: *Self) void {
        self.type = .{ .small_string = undefined };
        self.len = 0;
    }
};

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

fn isWhiteSpace(x: u8) bool {
    return x == ' ' or x == '\n' or x == '\t';
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

    // TODO(TB): len might be wrong here
    return .{ .type = .{ .t_number = result }, .index = start_index, .len = index - start_index };
}

pub const Tokenizer = struct {
    input: []const u8,
    index: usize,

    pub fn create(input: []const u8) Tokenizer {
        return .{
            .input = input,
            .index = 0,
        };
    }

    pub fn init(self: *Tokenizer, input: []u8) void {
        self.input = input;
        self.index = 0;
    }

    fn skipWhiteSpace(self: *Tokenizer) void {
        while (self.index < self.input.len and isWhiteSpace(self.input[self.index])) {
            self.index += 1;
        }
    }

    pub fn next(self: *Tokenizer, allocator: std.mem.Allocator) Token {
        self.skipWhiteSpace();

        if (self.index >= self.input.len) {
            return .{ .type = .t_end_of_stream, .len = 0, .index = self.index };
        }

        const result: Token = switch (self.input[self.index]) {
            '{' => .{ .type = .t_open_object, .len = 1, .index = self.index },
            '}' => .{ .type = .t_close_object, .len = 1, .index = self.index },
            '[' => .{ .type = .t_open_array, .len = 1, .index = self.index },
            ']' => .{ .type = .t_close_array, .len = 1, .index = self.index },
            ':' => .{ .type = .t_colon, .len = 1, .index = self.index },
            ',' => .{ .type = .t_comma, .len = 1, .index = self.index },
            'n' => if (matchSymbol(self.input, self.index + 1, "ull"))
                .{ .type = .t_null, .len = 4, .index = self.index }
            else
                .{ .type = .t_invalid, .len = 0, .index = self.index },
            't' => if (matchSymbol(self.input, self.index + 1, "rue"))
                .{ .type = .{ .t_boolean = true }, .len = 4, .index = self.index }
            else
                .{ .type = .t_invalid, .len = 0, .index = self.index },
            'f' => if (matchSymbol(self.input, self.index + 1, "alse"))
                .{ .type = .{ .t_boolean = false }, .len = 5, .index = self.index }
            else
                .{ .type = .t_invalid, .len = 0, .index = self.index },
            '"' => lexStringAfterOpenQuote(allocator, self.input, self.index + 1),
            else => lexNumber(self.input, self.index),
        };
        self.index += result.len;
        return result;
    }
};
