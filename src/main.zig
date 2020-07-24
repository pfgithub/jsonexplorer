const std = @import("std");
const TermGUI = @import("TermGUI.zig");

const cli = @import("cli.zig");

pub fn main() !void {
    const rawMode = try cli.enterRawMode();
    defer cli.exitRawMode(rawMode) catch {};

    cli.enterFullscreen() catch {};
    defer cli.exitFullscreen() catch {};

    while (cli.nextEvent()) |ev| {
        std.debug.warn("Event: {}\n", .{ev});
        if (ev.is("ctrl+c")) break;
    }

    // const tgui = TermGUI.init();
    // defer tgui.deinit();
    //
    // while (true) {
    //     tgui.text(5, 5, "test");
    //
    //     const ev = cli.nextEvent();
    //     if (ev.is("ctrl+c")) {
    //         break;
    //     }
    // }

    // an interactive json explorer
    // eg `zig targets | jsonexplorer`
    //
    // / Filter...
    // ▾ "abi"
    //   / filter (appears at the top of each list. left arrow to go to parent and filter it eg.)
    //   - "none"
    //   - "gnu"
    //   - "gnuabin32"
    //   ...
    // ▸ "arch"
    // ▸ "cpuFeatures"
    // ▸ "cpus"
    // ▸ "glibc"
    // ▸ "libc"
    // ▸ "native"
    // ▸ "os"
    //
    // needs an easy to access filter function
    // like at the top or keybind /
    //
    // just noticed a neat unicode thing —🢒
    // |
    // 🢓
    //
    // imagine if I could make a library where terminal ui and imgui were the same
    // cross platform. desktop/mobile/web(webgl)/terminal(gui) and accessability stuff
    //
    // that would be neat
    // terminal gui would be pretty different from the rest in terms of pixel distances
    // lib user would have to specify abstract distances which is bad for design
}
