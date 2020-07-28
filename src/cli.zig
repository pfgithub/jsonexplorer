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
    return TermSize{ .w = wsz.ws_row, .h = wsz.ws_col };
}

pub fn startCaptureMouse() !void {
    try print("\x1b[?1003;1015;1006h");
}
pub fn stopCaptureMouse() !void {
    try print("\x1b[?1003;1015;1006l");
}
pub const StringSplitIterator = struct {
    pub const ItItem = []const u8;
    string: []const u8,
    split: []const u8,
    /// split a string at at. if at == "", split at every byte (not codepoint).
    pub fn split(string: []const u8, at: []const u8) StringSplitIterator {
        return .{ .string = string, .split = at };
    }
    pub fn next(me: *StringSplitIterator) ?[]const u8 {
        var res = me.string;
        while (!std.mem.startsWith(u8, me.string, me.split)) {
            if (me.string.len == 0) {
                if (res.len > 0) return res;
                return null;
            }
            me.string = me.string[1..];
        }
        if (me.string.len == 0) {
            if (res.len > 0) return res;
            return null;
        }
        if (me.split.len == 0) {
            me.string = me.string[1..]; // split("something", "");
        }
        defer me.string = me.string[me.split.len..];
        return res[0 .. res.len - me.string.len];
    }
};

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
    };
    const KeyEvent = struct {
        modifiers: struct {
            ctrl: bool,
            shift: bool,
        } = .{ .ctrl = false, .shift = false },
        keycode: Keycode,
    };
    key: KeyEvent,
    resize: void,
    mouse: struct {
        x: u32,
        y: u32,
        button: MouseButton,
        mouseup: bool,
        mousemove: bool,
        ctrl: bool,
        alt: bool,
        shift: bool,
    },

    const MouseButton = enum { none, left, middle, right, scrollup, scrolldown };

    pub fn from(text: []const u8) !Event {
        var resev: KeyEvent = .{ .keycode = .{ .character = 0 } };
        var split = StringSplitIterator.split(text, "+");
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
                try writer.writeAll(std.meta.tagName(m.button));
                if (m.mouseup) try writer.writeAll(" mouseup");
                if (m.mousemove) try writer.writeAll(" mousemove");
                if (m.ctrl) try writer.writeAll(" ctrl");
                if (m.alt) try writer.writeAll(" alt");
                if (m.shift) try writer.writeAll(" shift");
                try writer.print(" {}, {})", .{ m.x, m.y });
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

pub fn nextEvent(stdinf: std.fs.File) ?Event {
    const stdin = stdinf.reader();

    const firstByte = stdin.readByte() catch return null;
    switch (firstByte) {
        3 => return Event.fromc("ctrl+c"),
        4 => return Event.fromc("ctrl+d"),
        26 => return Event.fromc("ctrl+z"),
        '\x1b' => {
            switch (stdin.readByte() catch return null) {
                '[' => {
                    switch (stdin.readByte() catch return null) {
                        '1'...'9' => |num| {
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
                            if (b.char != ';') std.debug.panic("Bad char `{c}`\n", .{b.char});
                            const x = readInt(stdin) catch return null;
                            if (x.char != ';') std.debug.panic("Bad char `{c}`\n", .{x.char});
                            const y = readInt(stdin) catch return null;
                            if (y.char != 'M' and y.char != 'm') std.debug.panic("Bad char `{c}`\n", .{y.char});

                            const data = @bitCast(MouseButtonData, @intCast(u8, b.val));

                            return Event{
                                .mouse = .{
                                    .x = x.val,
                                    .y = y.val,
                                    .button = if (data.scroll == 1) switch (data.button) {
                                        .left => Event.MouseButton.scrollup,
                                        .right => .scrolldown,
                                        else => @panic("bad"),
                                    } else switch (data.button) {
                                        .left => Event.MouseButton.left,
                                        .middle => .middle,
                                        .right => .right,
                                        .none => .none,
                                    },
                                    .mouseup = y.char == 'm',
                                    .mousemove = data.move == 1,
                                    .ctrl = data.ctrl == 1,
                                    .alt = data.alt == 1,
                                    .shift = data.shift == 1,
                                },
                            };
                        },
                        // 'M' => {
                        //     const ButtonInfo = packed struct {
                        //         btn: packed enum(u2) { left = 0, middle = 1, right = 2, none = 3 },
                        //         shift: u1, meta: u1, ctrl: u1, rest: u3,
                        //     };
                        //     const b = stdin.readByte() catch return null;
                        //     const buttons = @bitCast(Event.ButtonInfo, b);
                        //     const x = stdin.readByte() catch return null;
                        //     const y = stdin.readByte() catch return null;
                        //     return Event{ .mouse = .{ .b = buttons, .x = x - 33, .y = y - 33 } };
                        // },
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
pub fn mainLoop(data: anytype, comptime cb: anytype, stdinF: std.fs.File) void {
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
    while (nextEvent(stdinF)) |ev| {
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

// instead of requiring the user to manage cursor positions
// why not store the entire screen here
// and then when it changes, diff it and only update what changed
// ez
