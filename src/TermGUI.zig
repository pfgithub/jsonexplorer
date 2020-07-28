const std = @import("std");
const cli = @import("cli.zig");

const Me = @This();

pub const ScreenChar = struct {
    style: cli.Style,
    char: u8,
};

const BufferedWriter = std.io.BufferedWriter(4096, std.fs.File.Writer);

buffered_stdout: BufferedWriter, // = TermGUI.BufferedWriter { .unbuffered_writer = ubw }
stdout: BufferedWriter.Writer, // = buffered_stdout.writer() // buffered_stdout must stay the same place in memory
stdin: std.fs.File.Reader, // = stdin file (/dev/tty or something) .reader()

term_w: usize,
term_h: usize,
screen_chars: [][]ScreenChar,
prev_chars: [][]ScreenChar,

pub fn render(tgui: Me) void {
    // if prev w is different or prev h is different
    //    redraw the whole thing
    // for char
    //    if different
    //        move cursor there
    //        write new char
    defer tgui.buffered_stdout.flush() catch @panic("stdout write failed");
    cli.clearScreen(tgui.stdout);
}
