const std = @import("std");
const cli = @import("cli.zig");

pub fn main() !void {
    const stdin = std.io.getStdIn().inStream();
    const stdout = std.io.getStdIn().outStream();

    const ot = try cli.enterRawMode();
    defer cli.exitRawMode(ot) catch @panic("failed to exit");

    try cli.startCaptureMouse();
    defer cli.stopCaptureMouse() catch @panic("failed to stop mouse capture");

    const escape_start = "\x1b[34m\\\x1b[94m";
    const escape_end = "\x1b(B\x1b[m";

    while (true) {
        const rb = try stdin.readByte();
        switch (rb) {
            3 => break,
            32...126 => |c| try stdout.print("{c}", .{c}),
            '\t' => try stdout.print(escape_start ++ "t" ++ escape_end, .{}),
            '\r' => try stdout.print(escape_start ++ "r" ++ escape_end, .{}),
            '\n' => try stdout.print(escape_start ++ "n" ++ escape_end, .{}),
            else => |c| try stdout.print(escape_start ++ "x{x:0>2}" ++ escape_end, .{c}),
        }
    }
}
