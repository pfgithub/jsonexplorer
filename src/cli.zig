const std = @import("std");
const help = @import("./helpers.zig");

const EscapeCodes = struct {
    const smcup = "\x1b[?1049h\x1b[22;0;0t\x1b[2J\x1b[H";
    const rmcup = "\x1b[2J\x1b[H\x1b[?1049l\x1b[23;0;0t";
};

fn print(msg: []const u8) !void {
    try std.io.getStdOut().writer().print("{}", .{msg});
}

/// enters fullscreen
/// fullscreen is a seperate screen that does not impact the screen you type commands on
/// make sure to exit fullscreen before exit
pub fn enterFullscreen() !void {
    try print(EscapeCodes.smcup);
}
/// exit fullscreen and restore the previous terminal state
pub fn exitFullscreen() !void {
    try print(EscapeCodes.rmcup);
}

fn tcflags(comptime itms: anytype) std.os.tcflag_t {
    comptime {
        var res: std.os.tcflag_t = 0;
        for (itms) |itm| res |= @as(std.os.tcflag_t, @field(std.os, @tagName(itm)));
        return res;
    }
}

pub fn enterRawMode(stdin: std.fs.File) !std.os.termios {
    const origTermios = try std.os.tcgetattr(stdin.handle);
    var termios = origTermios;
    termios.lflag &= ~tcflags(.{ .ECHO, .ICANON, .ISIG, .IXON, .IEXTEN, .BRKINT, .INPCK, .ISTRIP, .CS8 });
    try std.os.tcsetattr(stdin.handle, std.os.TCSA.FLUSH, termios);
    return origTermios;
}
pub fn exitRawMode(stdin: std.fs.File, orig: std.os.termios) !void {
    try std.os.tcsetattr(stdin.handle, std.os.TCSA.FLUSH, orig);
}

fn ioctl(fd: std.os.fd_t, request: u32, comptime ResT: type) !ResT {
    var res: ResT = undefined;
    while (true) {
        switch (std.os.errno(std.os.system.ioctl(fd, request, @ptrToInt(&res)))) {
            0 => break,
            std.os.EBADF => return error.BadFileDescriptor,
            std.os.EFAULT => unreachable, // Bad pointer param
            std.os.EINVAL => unreachable, // Bad params
            std.os.ENOTTY => return error.RequestDoesNotApply,
            std.os.EINTR => continue,
            else => |err| return std.os.unexpectedErrno(err),
        }
    }
    return res;
}

const TermSize = struct { w: u16, h: u16 };
pub fn winSize(stdout: std.fs.File) !TermSize {
    var wsz: std.os.linux.winsize = try ioctl(stdout.handle, std.os.linux.TIOCGWINSZ, std.os.linux.winsize);
    return TermSize{ .w = wsz.ws_col, .h = wsz.ws_row };
}

pub fn startCaptureMouse() !void {
    try print("\x1b[?1003;1004;1015;1006h");
}
pub fn stopCaptureMouse() !void {
    try print("\x1b[?1003;1004;1015;1006l");
}

pub const Event = union(enum) {
    const Keycode = union(enum) {
        character: u21,
        backspace,
        delete,
        enter,
        up,
        left,
        down,
        right,
        insert,
        tab,
    };
    const KeyEvent = struct {
        modifiers: struct {
            ctrl: bool = false,
            shift: bool = false,
        } = .{},
        keycode: Keycode,
    };
    key: KeyEvent,
    resize: void,
    mouse: struct {
        x: u32,
        y: u32,
        button: MouseButton,
        direction: MouseDirection,
        ctrl: bool,
        alt: bool,
        shift: bool,
    },
    scroll: struct {
        x: u32,
        y: u32,
        pixels: i32,
        ctrl: bool,
        alt: bool,
        shift: bool,
    },
    focus,
    blur,
    none,

    const MouseButton = enum { none, left, middle, right };
    const MouseDirection = enum { down, move, up };

    pub fn from(text: []const u8) !Event {
        var resev: KeyEvent = .{ .keycode = .{ .character = 0 } };
        var split = std.mem.tokenize(text, "+");
        b: while (split.next()) |section| {
            inline for (.{ "ctrl", "shift" }) |modifier| {
                if (std.mem.eql(u8, section, modifier)) {
                    if (@field(resev.modifiers, modifier)) return error.AlreadySet;
                    @field(resev.modifiers, modifier) = true;
                    continue :b;
                }
            }
            if (section.len == 1) {
                if (resev.keycode != .character or resev.keycode.character != 0) return error.DoubleSetCode;
                resev.keycode = .{ .character = section[0] };
                continue :b;
            }
            inline for (@typeInfo(Keycode).Union.fields) |field| {
                if (field.field_type != void) continue;
                if (std.mem.eql(u8, section, field.name)) {
                    resev.keycode = @field(Keycode, field.name);
                    continue :b;
                }
            }
            std.debug.warn("Unused Section: `{}`\n", .{section});
            return error.UnusedSection;
        }
        if (resev.keycode == .character and resev.keycode.character == 0) return error.NeverSetCode;
        return Event{ .key = resev };
    }
    pub fn fromc(comptime text: []const u8) Event {
        return comptime Event.from(text) catch @compileError("bad event str");
    }

    pub fn is(thsev: Event, comptime text: []const u8) bool {
        return std.meta.eql(thsev, comptime Event.from(text) catch @compileError("bad event str"));
    }

    // fun idea, functioniterator isn't good enough atm it seems
    fn formatIter(value: Event, out: anytype) void {
        switch (value) {
            .key => |k| {
                if (k.modifiers.ctrl) out.emit("ctrl");
                if (k.modifiers.shift) out.emit("shift");
                out.emit(std.meta.tagName(k.keycode));
            },
            else => {
                out.emit("Unsupported: ");
                out.emit(std.meta.tagName(value));
            },
        }
    }
    pub fn format(value: Event, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        // var fniter = help.FunctionIterator(formatIter, Event, []const u8).init(value);
        // fniter.start();
        // var joinIter = help.iteratorJoin(fniter, "+");
        // while (joinIter.next()) |it| {
        //     try writer.writeAll(it);
        // }
        switch (value) {
            .key => |k| {
                try writer.writeAll("[");
                if (k.modifiers.ctrl) try writer.writeAll("ctrl+");
                if (k.modifiers.shift) try writer.writeAll("shift+");
                switch (k.keycode) {
                    .character => |char| {
                        if (char < 128) try writer.print("{c}", .{@intCast(u8, char)}) else try writer.print("{}", .{char});
                    },
                    else => |code| try writer.writeAll(std.meta.tagName(code)),
                }
                try writer.writeAll("]");
            },
            .resize => {
                try writer.writeAll(":resize:");
            },
            .mouse => |m| {
                try writer.writeAll("(");
                switch (m.direction) {
                    .down => try writer.writeAll("↓"),
                    .move => {},
                    .up => try writer.writeAll("↑"),
                }
                switch (m.button) {
                    .left => try writer.writeAll("lmb "),
                    .right => try writer.writeAll("rmb "),
                    .middle => try writer.writeAll("mmb "),
                    .none => {},
                }
                if (m.ctrl) try writer.writeAll("ctrl ");
                if (m.alt) try writer.writeAll("alt ");
                if (m.shift) try writer.writeAll("shift ");
                try writer.print("{}, {})", .{ m.x, m.y });
            },
            .scroll => |m| {
                if (m.pixels < 0) try writer.print("↑{} ", .{-m.pixels})
                // zig-fmt
                else try writer.print("↓{} ", .{m.pixels});
                try writer.writeAll("(");
                if (m.ctrl) try writer.writeAll("ctrl ");
                if (m.alt) try writer.writeAll("alt ");
                if (m.shift) try writer.writeAll("shift ");
                try writer.print("{}, {})", .{ m.x, m.y });
            },
            else => {
                try writer.writeAll(":unknown ");
                try writer.writeAll(std.meta.tagName(value));
                try writer.writeAll(":");
            },
        }
    }
};

test "Event.from" {
    const somev = try Event.from("ctrl+c");
    std.debug.warn("\n{}\n", .{somev});
}

const IntRetV = struct { char: u8, val: u32 };
/// read a u32 from a stream
/// returns the read u32 and the final read character
/// undefined behaviours on overflow
fn readInt(stream: anytype) !IntRetV {
    var res: u32 = 0;
    var itm = try stream.readByte();
    while (itm >= '0' and itm <= '9') : (itm = try stream.readByte()) {
        res = (res * 10) + (itm - '0');
    }
    return IntRetV{ .char = itm, .val = res };
}

// TODO instead of signal handlers, use sigwaitinfo/sigtimedwait
// and somehow wait for either a character or a signal (eg with select syntax #5263)
// or syscall magic and wait for something on two streams and write to a stream or something
// on signal.

pub fn nextEvent(stdinf: std.fs.File) !?Event {
    const stdin = stdinf.reader();

    const firstByte = stdin.readByte() catch return null;
    switch (firstByte) {
        // ctrl+k, ctrl+m don't work
        // also ctrl+[ allows you to type bad stuff that panics rn
        1...8, 11...26 => |ch| return Event{ .key = .{ .modifiers = .{ .ctrl = true }, .keycode = .{ .character = ch - 1 + 'a' } } },
        '\t' => return Event{ .key = .{ .keycode = .tab } },
        '\x1b' => {
            switch (stdin.readByte() catch return null) {
                '[' => {
                    switch (stdin.readByte() catch return null) {
                        '1'...'9' => |num| {
                            // if next byte is 1-9, this is a urxvt mouse event
                            // readInt(stdin, &[_]u8{num, byte})
                            // and then the rest
                            if ((stdin.readByte() catch return null) != '~') std.debug.panic("Unknown escape 1-9 something\n", .{});
                            switch (num) {
                                '2' => return Event.fromc("insert"),
                                '3' => return Event.fromc("delete"),
                                else => std.debug.panic("Unknown <esc>[#~ char `{c}`\n", .{num}),
                            }
                        },
                        'A' => return Event.fromc("up"),
                        'B' => return Event.fromc("down"),
                        'D' => return Event.fromc("left"),
                        'C' => return Event.fromc("right"),
                        'O' => return Event.blur,
                        'I' => return Event.focus,
                        '<' => {
                            const MouseButtonData = packed struct {
                                button: packed enum(u2) { left = 0, middle = 1, right = 2, none = 3 },
                                shift: u1,
                                alt: u1,
                                ctrl: u1,
                                move: u1,
                                scroll: u1,
                                unused: u1,
                            };

                            const b = readInt(stdin) catch return null;
                            if (b.char != ';') return error.BadEscapeSequence;
                            const x = readInt(stdin) catch return null;
                            if (x.char != ';') return error.BadEscapeSequence;
                            const y = readInt(stdin) catch return null;
                            if (y.char != 'M' and y.char != 'm') return error.BadEscapeSequence;

                            const data = @bitCast(MouseButtonData, @intCast(u8, b.val));

                            if (y.char == 'm' and data.move == 1) @panic("mouse is moving and released at the same time");

                            if (data.scroll == 1)
                                return Event{
                                    .scroll = .{
                                        .x = x.val - 1,
                                        .y = y.val - 1,
                                        .pixels = switch (data.button) {
                                            .left => -3,
                                            .middle => 3,
                                            else => return error.BadScrollEvent,
                                        },
                                        .ctrl = data.ctrl == 1,
                                        .alt = data.alt == 1,
                                        .shift = data.shift == 1,
                                    },
                                };

                            return Event{
                                .mouse = .{
                                    .x = x.val - 1,
                                    .y = y.val - 1,
                                    .button = switch (data.button) {
                                        .left => Event.MouseButton.left,
                                        .middle => .middle,
                                        .right => .right,
                                        .none => .none,
                                    },
                                    .direction = if (data.move == 1) Event.MouseDirection.move
                                    //zig fmt
                                    else if (y.char == 'm') Event.MouseDirection.up else .down,
                                    .ctrl = data.ctrl == 1,
                                    .alt = data.alt == 1,
                                    .shift = data.shift == 1,
                                },
                            };
                        },
                        else => |chr| std.debug.panic("Unknown [ escape {c}\n", .{chr}),
                    }
                },
                else => |esch| std.debug.panic("Unknown Escape Type {}\n", .{esch}),
            }
        },
        10 => return Event{ .key = .{ .keycode = .enter } },
        32...126 => return Event{ .key = .{ .keycode = .{ .character = firstByte } } },
        127 => return Event{ .key = .{ .keycode = .backspace } },
        128...255 => {
            const len = std.unicode.utf8ByteSequenceLength(firstByte) catch std.debug.panic("Invalid unicode start byte: {}\n", .{firstByte});
            var read = [_]u8{ firstByte, undefined, undefined, undefined };
            stdin.readNoEof(read[1..len]) catch return null;
            const unichar = std.unicode.utf8Decode(read[0..len]) catch |e| std.debug.panic("Unicode decode error: {}\n", .{e});
            return Event{ .key = .{ .keycode = .{ .character = unichar } } };
        },
        else => std.debug.panic("Unsupported: {}\n", .{firstByte}),
    }
}

var cbRunning = false;
var doResize = false;
var mainLoopFn: fn () void = undefined;

fn handleSigwinch(sig: i32, info: *const std.os.siginfo_t, ctx_ptr: ?*const c_void) callconv(.C) void {
    if (cbRunning) {
        doResize = true;
    } else {
        mainLoopFn();
    }
    setSignalHandler();
}

fn setSignalHandler() void {
    var act = std.os.Sigaction{
        .sigaction = handleSigwinch,
        .mask = std.os.empty_sigset,
        .flags = (std.os.SA_SIGINFO | std.os.SA_RESTART | std.os.SA_RESETHAND),
    };
    std.os.sigaction(std.os.SIGWINCH, &act, null);
}
/// data: any
/// cb: fn (data: @TypeOf(data), event: Event) bool
pub fn mainLoop(data: anytype, comptime cb: anytype, stdinF: std.fs.File) !void {
    const DataType = @TypeOf(data);
    const MLFnData = struct {
        var dataptr: usize = undefined;
        pub fn mainLoopFn_() void {
            if (!cb(@intToPtr(*const DataType, dataptr).*, .resize))
                @panic("requested exit during resize handler. not supported.");
        }
    };
    MLFnData.dataptr = @ptrToInt(&data);
    mainLoopFn = MLFnData.mainLoopFn_;
    setSignalHandler();
    while (try nextEvent(stdinF)) |ev| {
        cbRunning = true;
        if (!cb(data, ev)) break;
        cbRunning = false;
        // what is this
        while (doResize) {
            doResize = false;
            cbRunning = true;
            if (!cb(data, .resize)) break;
            cbRunning = false;
        }
    }
}

// \x1b[30m
// \x1b[90m
pub const Color = struct {
    const ColorCode = enum(u3) {
        black = 0,
        red = 1,
        green = 2,
        yellow = 3,
        blue = 4,
        magenta = 5,
        cyan = 6,
        white = 7,
    };
    code: ColorCode,
    bright: bool,
    pub fn from(comptime code: anytype) Color {
        const tt = @tagName(code);
        if (comptime std.mem.startsWith(u8, tt, "br")) return .{ .bright = true, .code = @field(ColorCode, tt[2..]) };
        return .{ .bright = false, .code = @field(ColorCode, tt) };
    }
    /// returned []const u8 is embedded in the binary and freeing is not necessary
    const BGFGMode = enum { bg, fg };
    pub fn escapeCode(color: Color, mode: BGFGMode) []const u8 {
        // ah yes, readable code
        inline for (@typeInfo(ColorCode).Enum.fields) |colrfld| {
            inline for (.{ .bg, .fg }) |bgfgmode| {
                inline for (.{ true, false }) |bright| {
                    if (@enumToInt(color.code) == colrfld.value and mode == bgfgmode and color.bright == bright) {
                        comptime const vtxt = switch (@as(BGFGMode, bgfgmode)) {
                            .bg => if (bright) "10" else "4",
                            .fg => if (bright) "9" else "3",
                        };
                        return "\x1b[" ++ vtxt ++ &[_]u8{colrfld.value + '0'} ++ "m";
                    }
                }
            }
        }
        unreachable; // all cases handled
    }
};

// \x1b[40m
// \x1b[100m

pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    mode: enum { normal, bold, italic } = .normal,
};

/// set the text style. if oldStyle is specified, find the closest path to
///  it rather than the full style.
pub fn setTextStyle(writer: anytype, style: Style, oldStyle: ?Style) !void {
    if (oldStyle) |ostyl| if (std.meta.eql(style, ostyl)) return; // nothing to do
    try writer.writeAll("\x1b(B\x1b[m"); // reset
    if (style.fg) |fg| try writer.writeAll(fg.escapeCode(.fg));
    if (style.bg) |bg| try writer.writeAll(bg.escapeCode(.bg));
    switch (style.mode) {
        .normal => {},
        .bold => try writer.writeAll("\x1b[1m"),
        .italic => try writer.writeAll("\x1b[3m"),
    }
}

pub fn moveCursor(writer: anytype, x: u32, y: u32) !void {
    try writer.print("\x1b[{};{}f", .{ y + 1, x + 1 });
}

pub fn clearScreen(writer: anytype) !void {
    try writer.writeAll("\x1b[2J");
}
pub fn clearToEol(writer: anytype) !void {
    try writer.writeAll("\x1b[0K");
}

// instead of requiring the user to manage cursor positions
// why not store the entire screen here
// and then when it changes, diff it and only update what changed
// ez
