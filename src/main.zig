const std = @import("std");
const TermGUI = @import("TermGUI.zig");

const cli = @import("cli.zig");

fn renderJsonNode(key: []const u8, value: *const std.json.Value, indent: u32) void {
    const collapsible = switch (value.*) {
        .Object => true,
        .Array => true,
        .Float => false,
        .String => false,
        .Integer => false,
        .Bool => false,
        .Null => false,
    };
    var i: u32 = 0;
    while (i < indent) : (i += 1) {
        std.debug.warn("│", .{}); // ╵ todo
    }
    std.debug.warn("{} {}", .{ if (collapsible) @as([]const u8, "-") else "▾", key });
    switch (value.*) {
        .Object => |obj| {
            std.debug.warn("\n", .{});
            var iter = obj.iterator();
            while (iter.next()) |kv| {
                renderJsonNode(kv.key, &kv.value, indent + 1);
            }
        },
        .Array => |arr| {
            std.debug.warn("\n", .{});
            for (arr.items) |itm| {
                renderJsonNode("0:", &itm, indent + 1);
            }
        },
        .String => |str| {
            std.debug.warn(" \"{}\"\n", .{str});
        },
        .Float => |f| std.debug.warn(" {d}\n", .{f}),
        .Integer => |f| std.debug.warn(" {d}\n", .{f}),
        .Bool => |f| std.debug.warn(" {}\n", .{f}),
        .Null => std.debug.warn(" null\n", .{}),
    }
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    const stdinf = std.io.getStdIn();

    if (std.os.isatty(stdinf.handle)) {
        std.debug.warn("Usage: echo '{{}}' | jsonexplorer\n", .{});
        return;
    }

    std.debug.warn("\r\x1b[KReading File...", .{});

    const jsonTxt = try stdinf.reader().readAllAlloc(alloc, 1000 * 1000);
    defer alloc.free(jsonTxt);

    std.debug.warn("\r\x1b[KParsing JSON...", .{});

    var jsonParser = std.json.Parser.init(alloc, false); // copy_strings = false;
    defer jsonParser.deinit();
    var jsonRes = try jsonParser.parse(jsonTxt);
    defer jsonRes.deinit();

    var jsonRoot = &jsonRes.root;

    std.debug.warn("\r\x1b[K", .{});

    var stdin2file = try std.fs.openFileAbsolute("/dev/tty", .{ .read = true });
    defer stdin2file.close();
    var stdin2 = stdin2file.reader();

    const rawMode = try cli.enterRawMode(stdin2file);
    defer cli.exitRawMode(stdin2file, rawMode) catch {};

    cli.enterFullscreen() catch {};
    defer cli.exitFullscreen() catch {};

    renderJsonNode(".", jsonRoot, 0);

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
    // │ / filter (appears at the top of each list. left arrow to go to parent and filter it eg.)
    // │ - 0: "none"
    // │ - 1: "gnu"
    // │ - 2: "gnuabin32"
    // ╵ - 3: "gnuabin64"
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
