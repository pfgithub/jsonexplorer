const std = @import("std");
const TermGUI = @import("TermGUI.zig");

const cli = @import("cli.zig");

fn renderJsonNode(out: anytype, key: []const u8, value: *const std.json.Value, indent: u32) @TypeOf(out).Error!void {
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
        try out.print("│", .{}); // ╵ todo
    }
    try out.print("{} {}", .{ if (collapsible) @as([]const u8, "-") else "▾", key });
    switch (value.*) {
        .Object => |obj| {
            std.debug.warn("\n", .{});
            var iter = obj.iterator();
            while (iter.next()) |kv| {
                try renderJsonNode(out, kv.key, &kv.value, indent + 1);
            }
        },
        .Array => |arr| {
            std.debug.warn("\n", .{});
            for (arr.items) |itm| {
                try renderJsonNode(out, "0:", &itm, indent + 1);
            }
        },
        .String => |str| {
            try out.print(" \"{}\"\n", .{str});
        },
        .Float => |f| try out.print(" {d}\n", .{f}),
        .Integer => |f| try out.print(" {d}\n", .{f}),
        .Bool => |f| try out.print(" {}\n", .{f}),
        .Null => try out.print(" null\n", .{}),
    }
}
const Themes = [_]Theme{
    Theme.from(.{ .brred, .bryellow, .brgreen, .brcyan, .brblue, .brmagenta }),
    Theme.from(.{ .brmagenta, .bryellow, .brblue }),
    Theme.from(.{ .bryellow, .brwhite, .magenta }),
    Theme.from(.{ .brblue, .brmagenta, .brwhite, .brmagenta }),
    Theme.from(.{ .brmagenta, .brwhite, .brgreen }),
};
const Theme = struct {
    colors: []const cli.Color,
    pub fn from(comptime items: anytype) Theme {
        var res: []const cli.Color = &[_]cli.Color{};
        for (items) |item| {
            res = res ++ &[_]cli.Color{cli.Color.from(item)};
        }
        return Theme{ .colors = res };
    }
};

const Point = struct { x: u32, y: u32 };
const Selection = struct {
    hover: ?Point,
    mouseup: bool,
};

const JsonRender = struct {
    const JsonKey = union(enum) { int: usize, str: []const u8, root };
    const ChildNode = struct { key: JsonKey, value: JsonRender };

    childNodes: []ChildNode,
    content: std.json.Value,
    index: usize,
    open: bool,

    pub fn init(alloc: *std.mem.Allocator, jsonv: std.json.Value, index: usize) std.mem.Allocator.Error!JsonRender {
        const childNodes = switch (jsonv) {
            .Array => |arr| blk: {
                var childNodesL = try alloc.alloc(ChildNode, arr.items.len);
                errdefer alloc.free(childNodesL);

                for (arr.items) |itm, i| {
                    childNodesL[i] = .{ .key = .{ .int = i }, .value = try JsonRender.init(alloc, itm, i) };
                }

                break :blk childNodesL;
            },
            .Object => |hm| blk: {
                const items = hm.items(); // what
                var childNodesL = try alloc.alloc(ChildNode, items.len);
                errdefer alloc.free(childNodesL);

                for (items) |itm, i| {
                    childNodesL[i] = .{ .key = .{ .str = itm.key }, .value = try JsonRender.init(alloc, itm.value, i) };
                }

                break :blk childNodesL;
            },
            else => &[_]ChildNode{},
        };
        errdefer alloc.free(childNodes);
        return JsonRender{
            .open = false,
            .childNodes = childNodes,
            .content = jsonv,
            .index = index,
        };
    }
    pub fn deinit(jr: *JsonRender, alloc: *std.mem.Allocator) void {
        alloc.free(jr.childNodes);
    }
    // todo rename JsonRender and move the render fn out of this so it actually holds data rather than
    // being a gui component type thing
    pub fn render(me: *JsonRender, out: anytype, key: JsonKey, x: u32, y: u32, h: u32, theme: Theme, themeIndex: usize, selection: Selection) @TypeOf(out).Error!u32 {
        if (y >= h) return 0;

        const hovering = if (selection.hover) |hov| hov.x >= x and hov.y == y else false;
        const focused = false;
        const bgstyl: ?cli.Color = if (hovering) cli.Color.from(.brblack) else null;

        if (hovering and selection.mouseup) me.open = !me.open;

        try cli.moveCursor(out, x, y);

        const themeStyle: cli.Style = .{ .fg = theme.colors[themeIndex % theme.colors.len], .bg = bgstyl };

        try cli.setTextStyle(out, themeStyle, null);

        if (me.childNodes.len == 0)
            try out.writeAll("-")
        else if (me.open)
            try out.writeAll("▾")
        else
            try out.writeAll("▸");

        try cli.setTextStyle(out, .{ .bg = bgstyl }, null);

        switch (key) {
            .str => |str| {
                try cli.setTextStyle(out, .{ .fg = cli.Color.from(.white), .bg = bgstyl }, null);
                try out.print(" \"", .{});
                try cli.setTextStyle(out, themeStyle, null);
                try out.print("{}", .{str});
                try cli.setTextStyle(out, .{ .fg = cli.Color.from(.white), .bg = bgstyl }, null);
                try out.print("\"", .{});
                try cli.setTextStyle(out, .{ .bg = bgstyl }, null);
                try out.writeAll(":");
            },
            .int => |int| {
                try cli.setTextStyle(out, themeStyle, null);
                try out.print(" {}", .{int});
                try cli.setTextStyle(out, .{ .bg = bgstyl }, null);
                try out.writeAll(":");
            },
            .root => {},
        }

        switch (me.content) {
            .Array => if (me.childNodes.len == 0) try out.writeAll(" []") else if (!me.open) try out.writeAll(" […]"),
            .Object => if (me.childNodes.len == 0) try out.writeAll(" {}") else if (!me.open) try out.writeAll(" {…}"),
            .String => |str| try out.print(" \"{}\"", .{str}),
            .Float => |f| try out.print(" {d}", .{f}),
            .Integer => |f| try out.print(" {d}", .{f}),
            .Bool => |f| try out.print(" {}", .{f}),
            .Null => try out.print(" null", .{}),
        }

        try cli.clearToEol(out);
        try cli.setTextStyle(out, .{}, null);

        var cy = y + 1;
        if (me.open) for (me.childNodes) |*node| {
            if (cy == h) break;
            cy += try node.value.render(out, node.key, x + 2, cy, h, theme, themeIndex + 1, selection);
            if (cy > h) unreachable; // rendered out of screen
        };

        const barhov = if (selection.hover) |hov| hov.x == x and hov.y > y and hov.y < cy else false;
        const fgcolr: cli.Color = if (barhov) cli.Color.from(.brwhite) else cli.Color.from(.brblack);

        try cli.setTextStyle(out, .{ .fg = fgcolr }, null);
        var cyy: u32 = y + 1;
        while (cyy < cy) : (cyy += 1) {
            try cli.moveCursor(out, x, cyy);

            if (cyy + 1 < cy or cyy + 1 == h) try out.writeAll("│")
            // zig-fmt
            else try out.writeAll("╵");
        }

        return cy - y;
    }
};

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

    cli.startCaptureMouse() catch {};
    defer cli.stopCaptureMouse() catch {};

    var stdoutf = std.io.getStdOut();
    var stdout_buffered = std.io.bufferedWriter(stdoutf.writer());
    const stdout = stdout_buffered.writer();

    var jr = try JsonRender.init(alloc, jsonRoot.*, 0);
    defer jr.deinit(alloc);

    jr.open = true;

    var mousePoint: Point = .{ .x = 0, .y = 0 };
    var mouseVisible = false;

    while (cli.nextEvent(stdin2file)) |ev| : (try stdout_buffered.flush()) {
        if (ev.is("ctrl+c")) break;

        try cli.clearScreen(stdout);
        try cli.moveCursor(stdout, 0, 0);

        var selxn = Selection{ .hover = if (mouseVisible) mousePoint else null, .mouseup = false };

        switch (ev) {
            .mouse => |mev| {
                mousePoint.x = mev.x;
                mousePoint.y = mev.y;
                if (mev.button == .left and mev.direction == .up) selxn.mouseup = true;
            },
            .blur => mouseVisible = false,
            .focus => mouseVisible = true,
            else => {},
        }

        const ss = try cli.winSize(stdoutf);
        _ = try jr.render(stdout, .root, 0, 0, ss.h, Themes[0], 0, selxn);
        try stdout_buffered.flush();

        // try stdout.print("Event: {}\n", .{ev});
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
