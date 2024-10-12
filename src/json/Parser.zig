const std = @import("std");
const String = @import("String.zig");
const Lexer = @import("Lexer.zig");

pub const ItemType = enum { t_null, t_boolean, t_string, t_number, t_object, t_array };

pub const Item = union(ItemType) {
    t_null: void,
    t_boolean: bool,
    t_string: String,
    t_number: f64,
    t_object: std.AutoHashMap(String, Item),
    t_array: std.ArrayList(Item),

    pub fn print(self: *const Item) void {
        switch (self.*) {
            .t_null => std.debug.print("null", .{}),
            .t_boolean => |data| std.debug.print("{s}", .{if (data) "true" else "false"}),
            .t_string => |data| std.debug.print("\"{s}\"", .{data.getBufferConst()}),
            .t_number => |data| std.debug.print("{d}", .{data}),
            .t_object => unreachable,
            .t_array => |data| {
                std.debug.print("[", .{});
                for (data.items, 0..) |x, i| {
                    x.print();
                    if (i < data.items.len - 1) {
                        std.debug.print(", ", .{});
                    }
                }
                std.debug.print("]", .{});
            },
        }
    }

    pub fn deinit(self: *Item, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .t_string => |data| {
                data.deinit(allocator);
            },
            .t_array => |*data| {
                for (data.items) |*x| {
                    x.deinit(allocator);
                }
                data.deinit();
            },
            .t_object => |*data| {
                var iterator = data.iterator();
                while (iterator.next()) |x| {
                    x.key_ptr.deinit(allocator);
                    x.value_ptr.deinit(allocator);
                }
                data.deinit();
            },
            else => {},
        }
    }
};

pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Item {
    var lexer = Lexer.create(input);
    defer lexer.deinit(allocator);

    var item = try parseNextItem(allocator, &lexer);
    errdefer item.deinit(allocator);

    lexer.next(allocator);
    if (lexer.token.type == .t_end_of_stream) {
        return item;
    }

    return ParseError.SyntaxError;
}

fn parseNextItem(allocator: std.mem.Allocator, lexer: *Lexer) ParseError!Item {
    lexer.peek(allocator);
    switch (lexer.token.type) {
        .t_open_object => return try parseNextObject(allocator, lexer),
        .t_open_array => return try parseNextArray(allocator, lexer),
        .t_null => {
            lexer.next(allocator);
            return .t_null;
        },
        .t_number => |data| {
            lexer.next(allocator);
            return .{ .t_number = data };
        },
        .t_boolean => |data| {
            lexer.next(allocator);
            return .{ .t_boolean = data };
        },
        .t_string => |*data| {
            const result = .{ .t_string = data.* };
            data.release();
            lexer.next(allocator);
            return result;
        },
        else => return ParseError.SyntaxError,
    }
}

fn parseNextObject(allocator: std.mem.Allocator, lexer: *Lexer) !Item {
    lexer.next(allocator);
    std.debug.assert(lexer.token.type == .t_open_object);
    var items = std.AutoHashMap(String, Item).init(allocator);
    errdefer {
        var iterator = items.iterator();
        while (iterator.next()) |x| {
            x.key_ptr.deinit(allocator);
            x.value_ptr.deinit(allocator);
        }
        items.deinit();
    }

    while (true) {
        lexer.peek(allocator);
        if (lexer.token.type == .t_close_object) {
            lexer.next(allocator);
            return .{ .t_object = items };
        } else if (lexer.token.type == .t_comma) {
            if (items.count() == 0) {
                return ParseError.SyntaxError;
            }

            lexer.next(allocator);
        }

        var key = try parseNextItem(allocator, lexer);
        errdefer key.deinit(allocator);

        if (key != .t_string) {
            return ParseError.SyntaxError;
        }

        lexer.next(allocator);
        if (lexer.token.type != .t_colon) {
            return ParseError.SyntaxError;
        }

        var value = try parseNextItem(allocator, lexer);
        errdefer value.deinit(allocator);

        // TODO(TB): consider if there is multiple keys that are the same?
        try items.put(key.t_string, value);
    }
}

const ParseError = error{ SyntaxError, OutOfMemory };

fn parseNextArray(allocator: std.mem.Allocator, lexer: *Lexer) !Item {
    lexer.next(allocator);
    std.debug.assert(lexer.token.type == .t_open_array);
    var items = std.ArrayList(Item).init(allocator);
    errdefer items.deinit();
    errdefer for (items.items) |*x| {
        x.deinit(allocator);
    };

    while (true) {
        lexer.peek(allocator);
        if (lexer.token.type == .t_close_array) {
            lexer.next(allocator);
            return .{ .t_array = items };
        } else if (lexer.token.type == .t_comma) {
            if (items.items.len == 0) {
                return ParseError.SyntaxError;
            }

            lexer.next(allocator);
        }

        // TODO(TB): should parseNextItem directly into the memory of items
        var item = try parseNextItem(allocator, lexer);

        items.append(item) catch |err| {
            item.deinit(allocator);
            return err;
        };
    }
}

const expect = std.testing.expect;

test "json parse: false" {
    var result = try parse(std.testing.allocator, "false");
    defer result.deinit(std.testing.allocator);
    try expect(result == .t_boolean);
    try expect(result.t_boolean == false);
}

test "json parse: true" {
    var result = try parse(std.testing.allocator, "true");
    defer result.deinit(std.testing.allocator);
    try expect(result == .t_boolean);
    try expect(result.t_boolean == true);
}

test "json parse: null" {
    var result = try parse(std.testing.allocator, "null");
    defer result.deinit(std.testing.allocator);
    try expect(result == .t_null);
}

test "json parse: 3423324" {
    var result = try parse(std.testing.allocator, "3423324");
    defer result.deinit(std.testing.allocator);
    try expect(result == .t_number);
    try expect(result.t_number == 3423324);
}

test "json parse: 3423.324" {
    var result = try parse(std.testing.allocator, "3423.324");
    defer result.deinit(std.testing.allocator);
    try expect(result == .t_number);
    try expect(result.t_number == 3423.324);
}

test "json parse: small string with escapes" {
    const buffer = "\"dfs\\\\sdfdfs\\\"dfdsfsdf\"";
    var result = try parse(std.testing.allocator, buffer);
    defer result.deinit(std.testing.allocator);
    try expect(result == .t_string);
    try expect(result.t_string.len == 19);
    try expect(result.t_string.type == .small_string);
    try expect(std.mem.eql(u8, result.t_string.getBufferConst(), "dfs\\sdfdfs\"dfdsfsdf"));
}

test "json parse: large string" {
    const buffer = "\"thisisalargestringdflklfndlfgndfjkgndslfnldsnflkdsfndklsjngfjkldsnfgwdsfljkndsjklfndslfgnfgdjlnl\"";
    var result = try parse(std.testing.allocator, buffer);
    defer result.deinit(std.testing.allocator);
    try expect(result == .t_string);
    try expect(result.t_string.len == 96);
    try expect(result.t_string.type == .large_string);
    try expect(std.mem.eql(u8, result.t_string.getBufferConst(), buffer[1 .. buffer.len - 1]));
}

test "json parse: empty array" {
    const buffer = "[]";
    var result = try parse(std.testing.allocator, buffer);
    defer result.deinit(std.testing.allocator);
    try expect(result == .t_array);
    try expect(result.t_array.items.len == 0);
}

test "json parse: array" {
    const buffer = "[null, false, [], true, [1, 2, \"hello\"]]";
    var result = try parse(std.testing.allocator, buffer);
    defer result.deinit(std.testing.allocator);
    try expect(result == .t_array);
    try expect(result.t_array.items.len == 5);
}

test "json parse: array2" {
    const buffer = "[\"sdfbjkbfbjdfbjdkshflkdsjflksdjflkndjklgfbdjkfdslkfhlkdsfjlkdsjflsdflkdslfkjlhsdf\", false]";
    var result = try parse(std.testing.allocator, buffer);
    defer result.deinit(std.testing.allocator);
    try expect(result == .t_array);
    try expect(result.t_array.items.len == 2);

    try expect(result.t_array.items[0] == .t_string);
    try expect(std.mem.eql(u8, result.t_array.items[0].t_string.getBufferConst(), "sdfbjkbfbjdfbjdkshflkdsjflksdjflkndjklgfbdjkfdslkfhlkdsfjlkdsjflsdflkdslfkjlhsdf"));

    try expect(result.t_array.items[1] == .t_boolean);
    try expect(result.t_array.items[1].t_boolean == false);
}

test "json parse: array3" {
    const buffer = "[\"sdfbjkbfbjdfbjdkshflkdsjflksdjflkndjklgfbdjkfdslkfhlkdsfjlkdsjflsdflkdslfkjlhsdf\", dsfsf]";
    const result = parse(std.testing.allocator, buffer);
    try expect(result == ParseError.SyntaxError);
}

test "json parse: array4" {
    const buffer = "[\"sdfsd\", dsfsf]";
    const result = parse(std.testing.allocator, buffer);
    try expect(result == ParseError.SyntaxError);
}

test "json parse: object" {
    const buffer = "{\"x0\": null, \"y0\": 0, \"x1\": 1, \"y1\": true}";

    var result = try parse(std.testing.allocator, buffer);
    defer result.deinit(std.testing.allocator);
    try expect(result == .t_object);
    try expect(result.t_object.count() == 4);

    {
        var key = try String.create(std.testing.allocator, "x0");
        defer key.deinit(std.testing.allocator);
        try expect(result.t_object.contains(key));
        const value = result.t_object.get(key);
        try expect(value != null);
        try expect(value.? == .t_null);
    }

    {
        var key = try String.create(std.testing.allocator, "y0");
        defer key.deinit(std.testing.allocator);
        try expect(result.t_object.contains(key));
        const value = result.t_object.get(key);
        try expect(value != null);
        try expect(value.? == .t_number);
        try expect(value.?.t_number == 0);
    }

    {
        var key = try String.create(std.testing.allocator, "x1");
        defer key.deinit(std.testing.allocator);
        try expect(result.t_object.contains(key));
        const value = result.t_object.get(key);
        try expect(value != null);
        try expect(value.? == .t_number);
        try expect(value.?.t_number == 1);
    }

    {
        var key = try String.create(std.testing.allocator, "y1");
        defer key.deinit(std.testing.allocator);
        try expect(result.t_object.contains(key));
        const value = result.t_object.get(key);
        try expect(value != null);
        try expect(value.? == .t_boolean);
        try expect(value.?.t_boolean == true);
    }
}

test "json parse: object2" {
    const buffer = "{\"key1\": \"sdfjbkhlisdfhjlihsfkljdshfkjldhsflkdjslkfhndfkjghndsklfhdfkljgbdlksfhjldskhf\",\"key2\": null, \"key3\": \"sdfdjkbfkjdshjkfdsjkfbdjksfbkjdsbfjkdsbfjksdbfjkdsbfjkbsdfjkbsdkjfbsdjkfbdsjkfbjkdsbfjksdbf\",}";

    const result = parse(std.testing.allocator, buffer);
    try expect(result == ParseError.SyntaxError);
}
