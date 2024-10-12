const Register = @import("Register.zig");
const Size = @import("Size.zig").Size;

// TODO(TB): should displacement be stored sepertely for word and byte?
displacement: i16,
size: Size,
reg: [2]Register,
