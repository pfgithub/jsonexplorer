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

pub fn startCaptureMouse() !void {
    try print("\x1b[?1003;1015;1015h");
}
pub fn stopCaptureMouse() !void {
    try print("\x1b[?1003;1015;1015l");
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

const Event = union(enum) {
    const Keycode = union(enum) {
        character: u21,
        backspace,
        delete,
        enter,
        up,
        left,
        down,
        right,
    };
    const KeyEvent = struct {
        modifiers: struct {
            ctrl: bool,
            shift: bool,
        } = .{ .ctrl = false, .shift = false },
        keycode: Keycode,
    };
    key: KeyEvent,
    resize: struct {
        w: u32,
        h: u32,
    },
    mouse: struct {},

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
        if (resev.keycode.character == 0) return error.NeverSetCode;
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
                if (k.modifiers.ctrl) try writer.writeAll("+ctrl");
                if (k.modifiers.shift) try writer.writeAll("+shift");
                try writer.writeAll("+");
                switch (k.keycode) {
                    .character => |char| {
                        if (char < 128) try writer.print("{c}", .{@intCast(u8, char)}) else try writer.print("{}", .{char});
                    },
                    else => |code| try writer.writeAll(std.meta.tagName(code)),
                }
                try writer.writeAll("]");
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
                                '3' => return Event{ .key = .{ .keycode = .delete } },
                                else => std.debug.panic("Unknown <esc>[#~ number {}\n", .{num}),
                            }
                        },
                        'A' => return Event{ .key = .{ .keycode = .up } },
                        'B' => return Event{ .key = .{ .keycode = .down } },
                        'D' => return Event{ .key = .{ .keycode = .left } },
                        'C' => return Event{ .key = .{ .keycode = .right } },
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

// instead of requiring the user to manage cursor positions
// why not store the entire screen here
// and then when it changes, diff it and only update what changed
// ez
