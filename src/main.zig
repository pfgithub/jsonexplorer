const std = @import("std");
const TermGUI = @import("TermGUI.zig");

const cli = @import("cli.zig");

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    const stdinf = std.io.getStdIn();

    if (std.os.isatty(stdinf.handle)) {
        std.debug.warn("Usage: echo '{{}}' | jsonexplorer\n", .{});
        return;
    }

    const jsonTxt = try stdinf.reader().readAllAlloc(alloc, 1000 * 1000);
    defer alloc.free(jsonTxt);

    var stdin2file = try std.fs.openFileAbsolute("/dev/tty", .{ .read = true });
    defer stdin2file.close();
    var stdin2 = stdin2file.reader();

    const rawMode = try cli.enterRawMode(stdin2file);
    defer cli.exitRawMode(stdin2file, rawMode) catch {};

    cli.enterFullscreen() catch {};
    defer cli.exitFullscreen() catch {};

    std.debug.warn("JSON Txt: {}\n", .{jsonTxt});

    while (cli.nextEvent(stdin2file)) |ev| {
        if (ev.is("ctrl+c")) break;
        std.debug.warn("Event: {}\n", .{ev});
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
