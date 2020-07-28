const cli = @import("cli.zig");

const Me = @This();

pub const ScreenChar = struct {
    style: cli.Style,
    char: u8,
};

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
}
