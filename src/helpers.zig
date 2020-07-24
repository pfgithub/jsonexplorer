const std = @import("std");

// these might be in the standard library already but I don't know how to describe what they do well enough to ask.
// nice to have things

fn interpolateInt(a: anytype, b: @TypeOf(a), progress: f64) @TypeOf(a) {
    const OO = @TypeOf(a);

    const floa = @intToFloat(f64, a);
    const flob = @intToFloat(f64, b);

    return @floatToInt(OO, floa + (flob - floa) * progress);
}

/// interpolate between two values. clamps to edges.
pub fn interpolate(a: anytype, b: @TypeOf(a), progress: f64) @TypeOf(a) {
    const Type = @TypeOf(a);
    if (progress < 0) return a;
    if (progress > 1) return b;

    switch (Type) {
        u8 => return interpolateInt(a, b, progress),
        i64 => return interpolateInt(a, b, progress),
        u64 => return interpolateInt(a, b, progress),
        else => {},
    }
    switch (@typeInfo(Type)) {
        .Int => @compileError("Currently only supports u8, i64, u64"),
        .Struct => |stru| {
            var res: Type = undefined;
            inline for (stru.fields) |field| {
                @field(res, field.name) = interpolate(@field(a, field.name), @field(b, field.name), progress);
            }
            return res;
        },
        else => @compileError("Unsupported"),
    }
}

test "interpolation" {
    std.testing.expectEqual(interpolate(@as(u64, 25), 27, 0.5), 26);
    std.testing.expectEqual(interpolate(@as(u8, 15), 0, 0.2), 12);
    const Kind = struct { a: u64 };
    std.testing.expectEqual(interpolate(Kind{ .a = 10 }, Kind{ .a = 8 }, 0.5), Kind{ .a = 9 });

    std.testing.expectEqual(interpolate(@as(i64, 923), 1200, 0.999999875), 1199);
    std.testing.expectEqual(interpolate(@as(i64, 923), 1200, 1.000421875), 1200);
}

fn ensureAllDefined(comptime ValuesType: type, comptime Enum: type) void {
    comptime {
        const fields = @typeInfo(Enum).Enum.fields;
        const fieldCount = fields.len;
        const valuesInfo = @typeInfo(ValuesType).Struct;

        var ensure: [fieldCount]bool = undefined;
        for (fields) |field, i| {
            ensure[i] = false;
        }
        for (valuesInfo.fields) |field| {
            // var val: Enum = std.meta.stringToEnum(Enum, field.name);
            var val: Enum = @field(Enum, field.name);
            const index = @enumToInt(val);
            if (ensure[index]) {
                @compileError("Duplicate key: " ++ field.name);
            }
            ensure[index] = true;
        }
        for (fields) |field, i| {
            if (!ensure[i]) {
                @compileLog(@intToEnum(Enum, i));
                @compileError("Missing key");
            }
        }
    }
}

/// A "struct" with enum keys
pub fn EnumArray(comptime Enum: type, comptime Value: type) type {
    const fields = @typeInfo(Enum).Enum.fields;
    const fieldCount = fields.len;
    return struct {
        const V = @This();
        data: [fieldCount]Value,

        pub fn init(values: anytype) V {
            const ValuesType = @TypeOf(values);
            const valuesInfo = @typeInfo(ValuesType).Struct;
            ensureAllDefined(ValuesType, Enum);

            var res: [fieldCount]Value = undefined;
            inline for (valuesInfo.fields) |field| {
                var val: Enum = @field(Enum, field.name);
                const index = @enumToInt(val);
                res[index] = @field(values, field.name);
            }
            return .{ .data = res };
        }
        pub fn initDefault(value: Value) V {
            var res: [fieldCount]Value = undefined;
            inline for (fields) |field, i| {
                res[i] = value;
            }
            return .{ .data = res };
        }

        pub fn get(arr: V, key: Enum) Value {
            return arr.data[@enumToInt(key)];
        }
        pub fn getPtr(arr: *V, key: Enum) *Value {
            return &arr.data[@enumToInt(key)];
        }
        pub fn set(arr: *V, key: Enum, value: Value) Value {
            var prev = arr.data[@enumToInt(key)];
            arr.data[@enumToInt(key)] = value;
            return prev;
        }
    };
}

// holds all the values of the union at once instead of just one value
pub fn UnionArray(comptime Union: type) type {
    const tinfo = @typeInfo(Union);
    const Enum = tinfo.Union.tag_type.?;
    const Value = Union;

    const fields = @typeInfo(Enum).Enum.fields;
    const fieldCount = fields.len;
    return struct {
        const V = @This();
        data: [fieldCount]Value,

        pub fn initUndefined() V {
            var res: [fieldCount]Value = undefined;
            return .{ .data = res };
        }

        pub fn get(arr: V, key: Enum) Value {
            return arr.data[@enumToInt(key)];
        }
        pub fn getPtr(arr: *V, key: Enum) *Value {
            return &arr.data[@enumToInt(key)];
        }
        pub fn set(arr: *V, value: Union) Value {
            const enumk = @enumToInt(std.meta.activeTag(value));
            defer arr.data[enumk] = value; // does this make the control flow more confusing? it's nice because I don't need a temporary name but it also could definitely be more confusing.
            return arr.data[enumk];
        }
    };
}

// don't think this can be implemented yet because the fn
// can't be varargs
// vararg tuples please zig ty
/// usingnamespace vtable(@This());
pub fn vtable(comptime Vtable: type) type {
    const ti = @typeInfo(Vtable).Struct;
    return struct {
        pub fn from(comptime Container: type) Vtable {
            var result: Vtable = undefined;
            inline for (ti.fields) |field| {
                @field(result, field.name) = struct {
                    // pub fn a(...args: anytype)
                }.a;
            }
        }
    };
}

// comptime only
pub fn UnionCallReturnType(comptime Union: type, comptime method: []const u8) type {
    var res: ?type = null;
    for (@typeInfo(Union).Union.fields) |field| {
        const returnType = @typeInfo(@TypeOf(@field(field.field_type, method))).Fn.return_type orelse
            @compileError("Generic functions are not supported");
        if (res == null) res = returnType;
        if (res) |re| if (re != returnType) @compileError("Return types for fn " ++ method ++ " differ. First found " ++ @typeName(re) ++ ", then found " ++ @typeName(returnType));
    }
    return res orelse @panic("Union must have at least one field");
}

pub fn DePointer(comptime Type: type) type {
    return switch (@typeInfo(Type)) {
        .Pointer => |ptr| ptr.child,
        else => Type,
    };
}

pub fn unionCall(comptime Union: type, comptime method: []const u8, enumValue: @TagType(Union), args: anytype) UnionCallReturnType(Union, method) {
    const typeInfo = @typeInfo(Union).Union;
    const TagType = std.meta.TagType(Union);

    const callOpts: std.builtin.CallOptions = .{};
    inline for (typeInfo.fields) |field| {
        if (@enumToInt(enumValue) == field.enum_field.?.value) {
            return @call(callOpts, @field(field.field_type, method), args);
        }
    }
    @panic("Did not match any enum value");
}

pub fn unionCallReturnsThis(comptime Union: type, comptime method: []const u8, enumValue: @TagType(Union), args: anytype) Union {
    const typeInfo = @typeInfo(Union).Union;
    const TagType = std.meta.TagType(Union);

    const callOpts: std.builtin.CallOptions = .{};
    inline for (typeInfo.fields) |field| {
        if (@enumToInt(enumValue) == field.enum_field.?.value) {
            return @unionInit(Union, field.name, @call(callOpts, @field(field.field_type, method), args));
        }
    }
    @panic("Did not match any enum value");
}

// should it be unionCallThis(unionv, .deinit, .{args})? feels better imo.
pub fn unionCallThis(comptime method: []const u8, unionValue: anytype, args: anytype) UnionCallReturnType(DePointer(@TypeOf(unionValue)), method) {
    const isPtr = @typeInfo(@TypeOf(unionValue)) == .Pointer;
    const Union = DePointer(@TypeOf(unionValue));
    const typeInfo = @typeInfo(Union).Union;
    const TagType = std.meta.TagType(Union);

    const callOpts: std.builtin.CallOptions = .{};
    inline for (typeInfo.fields) |field| {
        if (@enumToInt(std.meta.activeTag(if (isPtr) unionValue.* else unionValue)) == field.enum_field.?.value) {
            return @call(callOpts, @field(field.field_type, method), .{if (isPtr) &@field(unionValue, field.name) else @field(unionValue, field.name)} ++ args);
        }
    }
    @panic("Did not match any enum value");
}

pub fn FieldType(comptime Container: type, comptime fieldName: []const u8) type {
    if (!@hasField(Container, fieldName)) @compileError("Container does not have field " ++ fieldName);
    // @TypeOf(@field(@as(Container, undefined), fieldName));
    // ^compiler crash
    switch (@typeInfo(Container)) {
        .Union => |uni| for (uni.fields) |field| {
            if (std.mem.eql(u8, field.name, fieldName)) return field.field_type;
        },
        .Struct => |stru| for (stru.fields) |field| {
            if (std.mem.eql(u8, field.name, fieldName)) return field.field_type;
        },
        else => @compileError("Must be Union | Struct"),
    }
    unreachable;
}

pub fn Function(comptime Args: anytype, comptime Return: type) type {
    return struct {
        data: usize,
        call: fn (thisArg: usize, args: Args) Return,
    };
}
fn FunctionReturn(comptime Type: type) type {
    const fnData = @typeInfo(@TypeOf(Type.call)).Fn;
    if (fnData.is_generic) @compileLog("Generic functions are not allowed");
    const Args = blk: {
        var Args: []const type = &[_]type{};
        inline for (fnData.args) |arg| {
            Args = Args ++ [_]type{arg.arg_type.?};
        }
        break :blk Args;
    };
    const ReturnType = fnData.return_type.?;
    return struct {
        pub const All = Function(Args, ReturnType);
        pub const Args = Args;
        pub const ReturnType = ReturnType;
    };
}
pub fn function(data: anytype) FunctionReturn(@typeInfo(@TypeOf(data)).Pointer.child).All {
    const Type = @typeInfo(@TypeOf(data)).Pointer.child;
    comptime if (@TypeOf(data) != *const Type) unreachable;
    const FnReturn = FunctionReturn(Type);
    const CallFn = struct {
        pub fn call(thisArg: FnReturn.All, args: anytype) FnReturn.Return {
            return @call(data.call, .{@intToPtr(@TypeOf(data), thisArg.data)} ++ args);
        }
    }.call;
    @compileLog(FnReturn.All);
    return .{
        .data = @ptrToInt(data),
        .call = &CallFn,
    };
}
test "function" {
    // oops Unreachable at /deps/zig/src/analyze.cpp:5922 in type_requires_comptime. This is a bug in the Zig compiler.
    // zig compiler bug + something is wrong in my code
    if (false) {
        const Position = struct { x: i64, y: i64 };
        const testFn: Function(.{ f64, Position }, f32) = function(&struct {
            number: f64,
            pub fn call(data: *@This(), someValue: f64, argOne: Position) f32 {
                return @floatCast(f32, data.number + someValue + @intToFloat(f64, argOne.x) + @intToFloat(f64, argOne.y));
            }
        }{ .number = 35.6 });
        // function call is only supported within the lifetime of the data pointer
        // should it have an optional deinit method?
        std.testing.expectEqual(testFn.call(.{ 25, .{ .x = 56, .y = 25 } }), 25.6);
        std.testing.expectEqual(testFn.call(.{ 666, .{ .x = 12, .y = 4 } }), 25.6);
        // unfortunately there is no varargs or way to comptime set custom fn args so this has to be a .{array}
    }
}

/// the stdlib comptime hashmap is only created once and makes a "perfect hash"
/// so this works I guess.
///
/// comptime "hash"map. all accesses and sets are ~~O(1)~~ O(n)
pub fn ComptimeHashMap(comptime Key: type, comptime Value: type) type {
    const Item = struct { key: Key, value: Value };
    return struct {
        const HM = @This();
        items: []const Item,
        pub fn init() HM {
            return HM{
                .items = &[_]Item{},
            };
        }
        fn findIndex(comptime hm: HM, comptime key: Key) ?u64 {
            for (hm.items) |itm, i| {
                if (Key == []const u8) {
                    if (std.mem.eql(u8, itm.key, key))
                        return i;
                } else if (itm.key == key)
                    return i;
            }
            return null;
        }
        pub fn get(comptime hm: HM, comptime key: Key) ?Value {
            if (hm.findIndex(key)) |indx| return hm.items[indx].value;
            return null;
        }
        pub fn set(comptime hm: *HM, comptime key: Key, comptime value: Value) ?Value {
            if (hm.findIndex(key)) |prevIndex| {
                const prev = hm.items[prevIndex].value;
                // hm.items[prevIndex].value = value; // did you really think it would be that easy?
                var newItems: [hm.items.len]Item = undefined;
                for (hm.items) |prevItem, i| {
                    if (i == prevIndex) {
                        newItems[i] = Item{ .key = prevItem.key, .value = value };
                    } else {
                        newItems[i] = prevItem;
                    }
                }
                hm.items = &newItems;
                return prev;
            }
            hm.items = hm.items ++ &[_]Item{Item{ .key = key, .value = value }};
            return null;
        }
    };
}
// this can also be made using memoization and blk:
pub const TypeIDMap = struct {
    latestID: u64,
    hm: ComptimeHashMap(type, u64),
    infoStrings: []const []const u8,
    pub fn init() TypeIDMap {
        return .{
            .latestID = 0,
            .hm = ComptimeHashMap(type, u64).init(),
            .infoStrings = &[_][]const u8{"empty"},
        };
    }
    pub fn get(comptime tidm: *TypeIDMap, comptime Type: type) u64 {
        if (tidm.hm.get(Type)) |index| return index;
        tidm.latestID += 1;
        if (tidm.hm.set(Type, tidm.latestID)) |_| @compileError("never");
        tidm.infoStrings = tidm.infoStrings ++ &[_][]const u8{@typeName(Type)};
        // @compileLog("ID", tidm.latestID, "=", Type);
        return tidm.latestID;
    }
};
/// a pointer to arbitrary data. panics if attempted to be read as the wrong type.
pub const AnyPtr = comptime blk: {
    var typeIDMap = TypeIDMap.init();
    break :blk struct {
        pointer: usize,
        typeID: u64,
        pub fn fromPtr(value: anytype) AnyPtr {
            const ti = @typeInfo(@TypeOf(value));
            if (ti != .Pointer) @compileError("must be *ptr");
            if (ti.Pointer.size != .One) @compileError("must be ptr to one item");
            if (ti.Pointer.is_const) @compileError("const not yet allowed");
            const thisTypeID = comptime typeID(ti.Pointer.child);
            return .{ .pointer = @ptrToInt(value), .typeID = thisTypeID };
        }
        pub fn readAs(any: AnyPtr, comptime RV: type) *RV {
            const thisTypeID = comptime typeIDMap.get(RV);
            if (any.typeID != thisTypeID)
                std.debug.panic(
                    "\x1b[31mError!\x1b(B\x1b[m Item is of type {}, but was read as type {}.\n",
                    .{ typeIDMap.infoStrings[any.typeID], typeIDMap.infoStrings[thisTypeID] },
                );
            return @intToPtr(*RV, any.pointer);
        }
        pub fn typeID(comptime Type: type) u64 {
            return comptime typeIDMap.get(Type);
        }
        fn typeName(any: AnyPtr) []const u8 {
            return typeIDMap.infoStrings[any.typeID];
        }
    };
};

pub fn expectEqualStrings(str1: []const u8, str2: []const u8) void {
    if (std.mem.eql(u8, str1, str2)) return;
    std.debug.panic("\nExpected `{}`, got `{}`\n", .{ str1, str2 });
}

pub fn fixedCoerce(comptime Container: type, asl: anytype) Container {
    if (@typeInfo(@TypeOf(asl)) != .Struct) {
        return @as(Container, asl);
    }
    if (@TypeOf(asl) == Container) {
        return asl;
    }
    var result: Container = undefined;
    switch (@typeInfo(Container)) {
        .Struct => |ti| {
            comptime var setFields: [ti.fields.len]bool = [_]bool{false} ** ti.fields.len;
            inline for (@typeInfo(@TypeOf(asl)).Struct.fields) |rmfld| {
                comptime const i = for (ti.fields) |fld, i| {
                    if (std.mem.eql(u8, fld.name, rmfld.name)) break i;
                } else @compileError("Field " ++ rmfld.name ++ " is not in " ++ @typeName(Container));
                comptime setFields[i] = true;
                const field = ti.fields[i];
                @field(result, rmfld.name) = fixedCoerce(field.field_type, @field(asl, field.name));
            }
            comptime for (setFields) |bol, i| if (!bol) {
                comptime const field = ti.fields[i];
                if (field.default_value) |defv|
                    @field(result, field.name) = defv
                else
                    @compileError("Did not set field " ++ field.name);
            };
        },
        .Enum => @compileError("enum niy"),
        else => @compileError("cannot coerce anon struct literal to " ++ @typeName(Container)),
    }
    return result;
}

test "fixedCoerce" {
    const SomeValue = struct { b: u32 = 4, a: u16 };
    const OtherValue = struct { a: u16, b: u32 = 4 };
    std.testing.expectEqual(SomeValue{ .a = 5, .b = 4 }, fixedCoerce(SomeValue, .{ .a = 5 }));
    std.testing.expectEqual(SomeValue{ .a = 5, .b = 10 }, fixedCoerce(SomeValue, .{ .a = 5, .b = 10 }));
    std.testing.expectEqual(@as(u32, 25), fixedCoerce(u32, 25));
    std.testing.expectEqual(SomeValue{ .a = 5 }, SomeValue{ .a = 5 });

    // should fail:
    // unfortunately, since there is no way of detecting anon literals vs real structs, this may not be possible
    // *: maybe check if @TypeOf(&@as(@TypeOf(asl)).someField) is const? idk. that is a bug though
    //    that may be fixed in the future.
    std.testing.expectEqual(SomeValue{ .a = 5 }, fixedCoerce(SomeValue, OtherValue{ .a = 5 }));

    const InnerStruct = struct { b: u16 };
    const DoubleStruct = struct { a: InnerStruct };
    std.testing.expectEqual(DoubleStruct{ .a = InnerStruct{ .b = 10 } }, fixedCoerce(DoubleStruct, .{ .a = .{ .b = 10 } }));
}

test "anyptr" {
    var number: u32 = 25;
    var longlonglong: u64 = 25;
    var anyPtr = AnyPtr.fromPtr(&number);
    std.testing.expectEqual(AnyPtr.typeID(u32), AnyPtr.typeID(u32));
    var anyPtrLonglong = AnyPtr.fromPtr(&longlonglong);
    std.testing.expectEqual(AnyPtr.typeID(u64), AnyPtr.typeID(u64));

    // type names only work after they have been used at least once,
    // so typeName will probably be broken most of the time.
    expectEqualStrings("u32", anyPtr.typeName());
    expectEqualStrings("u64", anyPtrLonglong.typeName());
}

test "enum array" {
    const Enum = enum { One, Two, Three };
    const EnumArr = EnumArray(Enum, bool);

    var val = EnumArr.initDefault(false);
    std.testing.expect(!val.get(.One));
    std.testing.expect(!val.get(.Two));
    std.testing.expect(!val.get(.Three));

    _ = val.set(.Two, true);
    _ = val.set(.Three, true);

    std.testing.expect(!val.get(.One));
    std.testing.expect(val.get(.Two));
    std.testing.expect(val.get(.Three));
}

test "enum array initialization" {
    const Enum = enum { One, Two, Three };
    const EnumArr = EnumArray(Enum, bool);

    var val = EnumArr.init(.{ .One = true, .Two = false, .Three = true });
    std.testing.expect(val.get(.One));
    std.testing.expect(!val.get(.Two));
    std.testing.expect(val.get(.Three));
}

test "union array" {
    const Union = union(enum) { One: bool, Two: []const u8, Three: i64 };
    const UnionArr = UnionArray(Union);

    // var val = UnionArr.init(.{ .One = true, .Two = "hi!", .Three = 27 });
    var val = UnionArr.initUndefined();
    _ = val.set(.{ .One = true });
    _ = val.set(.{ .Two = "hi!" });
    _ = val.set(.{ .Three = 27 });

    std.testing.expect(val.get(.One).One);
    std.testing.expect(std.mem.eql(u8, val.get(.Two).Two, "hi!"));
    std.testing.expect(val.get(.Three).Three == 27);

    _ = val.set(.{ .Two = "bye!" });
    _ = val.set(.{ .Three = 54 });

    std.testing.expect(val.get(.One).One);
    std.testing.expect(std.mem.eql(u8, val.get(.Two).Two, "bye!"));
    std.testing.expect(val.get(.Three).Three == 54);
}

test "unionCall" {
    const Union = union(enum) {
        TwentyFive: struct {
            fn init() i64 {
                return 25;
            }
        }, FiftySix: struct {
            fn init() i64 {
                return 56;
            }
        }
    };
    std.testing.expectEqual(unionCall(Union, "init", .TwentyFive, .{}), 25);
    std.testing.expectEqual(unionCall(Union, "init", .FiftySix, .{}), 56);
}

test "unionCallReturnsThis" {
    const Union = union(enum) {
        number: Number,
        boolean: Boolean,
        const Number = struct {
            num: i64,
            pub fn init() Number {
                return .{ .num = 91 };
            }
        };
        const Boolean = struct {
            boo: bool,
            pub fn init() Boolean {
                return .{ .boo = true };
            }
        };
    };
    std.testing.expectEqual(unionCallReturnsThis(Union, "init", .number, .{}), Union{ .number = .{ .num = 91 } });
    std.testing.expectEqual(unionCallReturnsThis(Union, "init", .boolean, .{}), Union{ .boolean = .{ .boo = true } });
}

test "unionCallThis" {
    const Union = union(enum) {
        TwentyFive: struct {
            v: i32,
            v2: i64,
            fn print(value: @This()) i64 {
                return value.v2 + 25;
            }
        }, FiftySix: struct {
            v: i64,
            fn print(value: @This()) i64 {
                return value.v;
            }
        }
    };
    std.testing.expectEqual(unionCallThis("print", Union{ .TwentyFive = .{ .v = 5, .v2 = 10 } }, .{}), 35);
    std.testing.expectEqual(unionCallThis("print", Union{ .FiftySix = .{ .v = 28 } }, .{}), 28);
}

test "unionCallThis pointer arg" {
    const Union = union(enum) {
        TwentyFive: struct {
            v: i32,
            v2: i64,
            fn print(value: *@This()) i64 {
                return value.v2 + 25;
            }
        }, FiftySix: struct {
            v: i64,
            fn print(value: *@This()) i64 {
                return value.v;
            }
        }
    };
    var val = Union{ .TwentyFive = .{ .v = 5, .v2 = 10 } };
    std.testing.expectEqual(unionCallThis("print", &val, .{}), 35);
    val = Union{ .FiftySix = .{ .v = 28 } };
    std.testing.expectEqual(unionCallThis("print", &val, .{}), 28);
}

test "FieldType" {
    const Struct = struct {
        thing: u8,
        text: []const u8,
    };
    comptime std.testing.expectEqual(FieldType(Struct, "thing"), u8);
    comptime std.testing.expectEqual(FieldType(Struct, "text"), []const u8);
    const Union = union {
        a: f64,
        b: bool,
    };
    comptime std.testing.expectEqual(FieldType(Union, "a"), f64);
    comptime std.testing.expectEqual(FieldType(Union, "b"), bool);
}

// ====
// iteration experiments
// ====

pub fn IteratorFns(comptime Iter: type) type {
    return struct {
        // pub fn pipe(other: anytype, args: anytype) anytype {}
    };
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
    usingnamespace IteratorFns(@This());
};
/// you own the returned slice
pub fn stringMerge(alloc: *std.mem.Allocator, striter: anytype) ![]const u8 {
    var res = std.ArrayList(u8).init(alloc);
    errdefer res.deinit();
    var itcpy = striter;
    while (itcpy.next()) |itm| try res.appendSlice(itm);
    return res.toOwnedSlice();
}

fn IteratorJoinType(comptime OITQ: type) type {
    return struct {
        pub const ItItem = OITQ.ItItem;
        const Me = @This();
        oiter: OITQ,
        join: ItItem,
        nextv: ?ItItem = null,
        mode: enum { oiter, join } = .oiter,
        pub fn next(me: *Me) ?ItItem {
            switch (me.mode) {
                .oiter => {
                    me.mode = .join;
                    if (me.nextv == null) me.nextv = me.oiter.next();
                    defer me.nextv = me.oiter.next();
                    return me.nextv;
                },
                .join => {
                    if (me.nextv == null) return null;
                    me.mode = .oiter;
                    return me.join;
                },
            }
        }
        usingnamespace IteratorFns(@This());
    };
}

fn suspendIterator(string: []const u8, out: anytype) void {
    for (string) |_, i| {
        out.emit(string[i .. i + 1]);
    }
}

pub fn FunctionIterator(comptime fnction: anytype, comptime Data: type, comptime Out: type) type {
    return struct {
        const SuspIterCllr = @This();

        fn iteratorCaller(string: Data, out: *[]const u8, resfr: *?anyframe) void {
            suspend resfr.* = @frame();
            fnction(string, struct {
                out: *Out,
                resfr: *?anyframe,
                pub fn emit(me: @This(), val: Out) void {
                    me.out.* = val;
                    suspend me.resfr.* = @frame();
                    me.out.* = undefined; // in case any other suspends happen, eg async io
                }
            }{ .out = out, .resfr = resfr });
            resfr.* = null;
        }

        frame: ?anyframe,
        funcfram: @Frame(iteratorCaller),
        out: Out,
        text: Data,
        pub fn init(text: Data) SuspIterCllr {
            return .{ .frame = undefined, .funcfram = undefined, .out = undefined, .text = text };
        }
        pub fn start(sic: *SuspIterCllr) void {
            // this cannot be done in init until @resultLocation is available I think
            sic.funcfram = async iteratorCaller(sic.text, &sic.out, &sic.frame);
        }

        pub fn next(sic: *SuspIterCllr) ?Out {
            resume sic.frame orelse return null;
            _ = sic.frame orelse return null;
            const res = sic.out;
            return res;
        }

        pub const ItItem = Out;
    };
}

test "suspend iterator" {
    var si = FunctionIterator(suspendIterator, []const u8, []const u8).init("Hello, World!");
    si.start();
    while (si.next()) |v| {
        std.debug.warn("V: `{}`\n", .{v});
    }
}

/// Join every other item of an iterator with a value
/// EG iteratorJoin(iteratorArray("One", "Two", "Three"), ", ") == ["One", ", ", "Two", ", ", "Three"]
pub fn iteratorJoin(oiter: anytype, join: @TypeOf(oiter).ItItem) IteratorJoinType(@TypeOf(oiter)) {
    return IteratorJoinType(@TypeOf(oiter)){ .oiter = oiter, .join = join };
}

fn testStringSplit(comptime str: []const u8, comptime at: []const u8, comptime expdt: []const []const u8) void {
    var split = StringSplitIterator.split(str, at);
    var i: usize = 0;
    while (split.next()) |section| : (i += 1) {
        if (!std.mem.eql(u8, section, expdt[i])) {
            std.debug.panic("Expected `{}`, got `{}`\n", .{ expdt[i], section });
        }
    }
}

test "string split" {
    testStringSplit("testing:-:string:-huh:-:interesting:-::-:a", ":-:", &[_][]const u8{ "testing", "string:-huh", "interesting", "", "a" });
    testStringSplit("evrychar", "", &[_][]const u8{ "e", "v", "r", "y", "c", "h", "a", "r" });
}

test "string join" {
    const alloc = std.testing.allocator;
    const res = try stringMerge(alloc, iteratorJoin(StringSplitIterator.split("testing", ""), ","));
    defer alloc.free(res);
    std.testing.expectEqualStrings("t,e,s,t,i,n,g", res);
}

// goal: integrate this with my printing lib
// so you can print a string iterator
// want to replace some text and print it? print(split("some text", "e").pipe(join, .{"E"}))
// or even better, replace("some text", "e", "E")

// want to print every item of an arraylist with each item <one>, <two>?
// sliceIter(al.items).pipe(map, fn(out, value) void {out("<"); out(value); out(">")} ).pipe(join, ", ")
// remove the items starting with a capital letter?
// .pipe(filter, fn(value) bool (value.len > 0 and !std.text.isCapital(value[0]) ))
// fun with streams

pub fn scale(val: anytype, from: [2]@TypeOf(val), to: [2]@TypeOf(val)) @TypeOf(val) {
    std.debug.assert(from[0] < from[1]);
    std.debug.assert(to[0] < to[1]);
    return (val - from[0]) * (to[1] - to[0]) / (from[1] - from[0]) + to[0];
}

test "math.scale" {
    std.testing.expectEqual(scale(@as(f64, 25), [_]f64{ 0, 100 }, [_]f64{ 0, 1 }), 0.25);
    std.testing.expectEqual(scale(@as(f64, 25), [_]f64{ 0, 100 }, [_]f64{ 10, 11 }), 10.25);
}
