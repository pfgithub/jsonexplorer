const std = @import("std");
const cli = @import("cli.zig");

var globalOT: ?std.os.termios = null;

pub fn panic(msg: []const u8, stack_trace: ?*std.builtin.StackTrace) noreturn {
    const stdinF = std.io.getStdIn();

    cli.stopCaptureMouse() catch {};
    if (globalOT) |ot| cli.exitRawMode(stdinF, ot) catch {};

    std.debug.warn("Panic: {}\n", .{msg});

    if (stack_trace) |trace|
        std.debug.dumpStackTrace(trace.*);

    std.debug.warn("Consider posting a bug report: https://github.com/pfgithub/jsonexplorer/issues/new\n", .{});

    std.os.exit(1);
}

pub fn main() !void {
    const stdinF = std.io.getStdIn();
    const stdin = stdinF.reader();
    const stdoutF = std.io.getStdOut();
    const stdout = stdoutF.writer();

    const ot = try cli.enterRawMode(stdinF);
    defer cli.exitRawMode(stdinF, ot) catch @panic("failed to exit");
    globalOT = ot;

    var mouseMode = false;
    var eventMode = false;
    for (std.os.argv) |arg, i| { // can't do [1..] because #2622
        if (i < 1) continue;
        std.debug.warn("ARG: {s}\n", .{arg});
        if (std.mem.eql(u8, std.mem.span(arg), "--mouse")) {
            mouseMode = true;
            continue;
        }
        if (std.mem.eql(u8, std.mem.span(arg), "--event")) {
            eventMode = true;
            continue;
        }
        @panic("bad args");
    }

    if (mouseMode) try cli.startCaptureMouse();
    defer if (mouseMode) cli.stopCaptureMouse() catch @panic("failed to stop mouse capture");

    try stdout.print("Escape sequence debug started. Window size is: {}\n", .{try cli.winSize(stdoutF)});

    if (eventMode) {
        try cli.mainLoop(false, struct {
            pub fn f(data: anytype, ev: cli.Event) bool {
                const stdoutF2 = std.io.getStdOut();
                const stdout2 = stdoutF2.writer();

                stdout2.print("{}\n", .{ev}) catch return false;
                if (ev.is("ctrl+c")) {
                    return false;
                }
                if (ev.is("ctrl+p")) @panic("panic test");
                return true;
            }
        }.f, stdinF);
        return;
    }
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
