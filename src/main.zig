const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;

pub fn main() !void {
    // mem
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allo = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    // get home
    const home: []const u8 = try homeDir(allo);
    defer allo.free(home);
    // wallpapers
    const wallpapers_path = try wallpapersPath(allo, home);
    defer allo.free(wallpapers_path);
    // clone wallpapers
    if (!dirExists(wallpapers_path)) try cloneWallpapers(allo, wallpapers_path);
    // get image name
    const img_name = try pickImage(allo, wallpapers_path);
    defer allo.free(img_name);
    // full image name
    const img_path = try std.fs.path.join(allo, &.{ wallpapers_path, img_name });
    defer allo.free(img_path);
    // env var settings.json
    const settings_json_path = try settingsJson(allo, home);
    defer allo.free(settings_json_path);
    // parse json
    const in_file = try std.fs.openFileAbsolute(settings_json_path, .{});
    defer in_file.close();
    // read
    const contents = try in_file.readToEndAlloc(allo, 10 * 1024);
    defer allo.free(contents);
    // parse json
    var tree = try std.json.parseFromSlice(std.json.Value, allo, contents, .{});
    defer tree.deinit();
    // modify tree
    var root = tree.value;
    var profiles = root.object.get("profiles") orelse blk: {
        const value: std.json.Value = .{ .object = .init(allo) };
        try root.object.put("profiles", value);
        break :blk value;
    };
    var defaults = profiles.object.get("defaults") orelse blk: {
        const value: std.json.Value = .{ .object = .init(allo) };
        try profiles.object.put("defaults", value);
        break :blk value;
    };
    try defaults.object.put("backgroundImage", std.json.Value{ .string = img_path });
    // turn into file
    const out_file = try std.fs.createFileAbsolute(settings_json_path, .{});
    defer out_file.close();
    // walk tree
    var data: std.ArrayList(JsonData) = try .initCapacity(allo, 16);
    defer data.deinit(allo);
    defer for (data.items) |datum| if (datum.value) |value| allo.free(value);
    try walkJson(allo, root, 0, &data);
    // write tree
    try jsonStringify(&data, out_file);
}

fn dirExists(abs_path: []const u8) bool {
    std.fs.accessAbsolute(abs_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return true,
    };
    return true;
}

fn homeDir(allo: Allocator) ![]const u8 {
    const var_name = if (@import("builtin").os.tag == .windows) "USERPROFILE" else "HOME";
    return std.process.getEnvVarOwned(allo, var_name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => try allo.dupe(u8, "C:\\Users\\bphil"),
        else => err,
    };
}

fn match(name: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.eql(u8, name, needle)) return true;
    } else return false;
}

fn wallpapersPath(
    allo: Allocator,
    home: []const u8,
) ![]const u8 {
    // subpaths
    const dir_path_from_home: []const u8 = switch (@import("builtin").os.tag) {
        .windows => "\\Pictures\\Wallpapers",
        .linux, .macos => "/Pictures",
        else => unreachable,
    };
    return try std.fs.path.join(allo, &.{
        home,
        dir_path_from_home,
    });
}

fn cloneWallpapers(allo: Allocator, path: []const u8) !void {
    const args = [_][]const u8{
        "git",
        "clone",
        "https://github.com/bphilip777/Wallpapers",
        path,
    };
    var child = std.process.Child.init(&args, allo);
    const result = try child.spawnAndWait();
    switch (result) {
        .Exited => {},
        else => {
            print("Failed: {s}\n", .{@tagName(result)});
            print("{s} {s} {s} {s} failed.\n", .{
                args[0],
                args[1],
                args[2],
                path,
            });
        },
    }
}

fn pickImage(allo: Allocator, pics_path: []const u8) ![]const u8 {
    // walk dir - choose random image
    var dir = try std.fs.openDirAbsolute(pics_path, .{ .iterate = true });
    defer dir.close();
    // init pic mem
    var pics: std.ArrayList([]const u8) = try .initCapacity(allo, 16);
    defer pics.deinit(allo);
    defer for (pics.items) |pic| allo.free(pic);
    // get pics
    var it = dir.iterate();
    const whitelisted_exts = [_][]const u8{ "jpg", "jpeg", "png" };
    while (try it.next()) |item| {
        switch (item.kind) {
            .file => {
                const dot = std.mem.lastIndexOfScalar(u8, item.name, '.') orelse continue;
                const ext = item.name[dot + 1 .. item.name.len];
                if (!match(ext, &whitelisted_exts)) continue;
                const new_name = try allo.dupe(u8, item.name);
                try pics.append(allo, new_name);
            },
            else => continue,
        }
    }
    // select random pic
    var RndGen = std.Random.DefaultPrng.init(@as(u64, @abs(std.time.timestamp())));
    const rng = RndGen.random();
    const rnd = rng.intRangeLessThan(u8, 0, @truncate(pics.items.len));
    const name = pics.items[rnd];
    // return copy of the name
    return try allo.dupe(u8, name);
}

fn settingsJson(allo: Allocator, home: []const u8) ![]const u8 {
    const local_dir = std.process.getEnvVarOwned(allo, "LOCALAPPDATA") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            print("Local App Data not found.\n", .{});
            return err;
        },
        else => return err,
    };
    defer allo.free(local_dir);
    // look for settings.json
    const new_filepath = try std.fs.path.join(
        allo,
        &.{ home, "AppData\\Local\\Packages\\Microsoft.WindowsTerminal_8wekyb3d8bbwe\\LocalState\\settings.json" },
    );
    return new_filepath;
}

const JsonType = enum {
    object,
    object_key,
    object_end,
    array,
    array_end,
    string,
    integer,
    number_string,
    float,
    bool,
    null,
};

const JsonData = struct {
    type: JsonType,
    depth: usize,
    value: ?[]const u8,
};

fn walkJson(
    allo: Allocator,
    value: std.json.Value,
    depth: u8,
    data: *std.ArrayList(JsonData),
) !void {
    switch (value) {
        .object => |obj| {
            try data.append(allo, .{ .type = .object, .depth = depth, .value = null });
            var it = obj.iterator();
            while (it.next()) |entry| {
                const new_key = try allo.dupe(u8, entry.key_ptr.*);
                try data.append(allo, .{ .type = .object_key, .depth = depth + 1, .value = new_key });
                try walkJson(allo, entry.value_ptr.*, depth + 1, data);
            }
            try data.append(allo, .{ .type = .object_end, .depth = depth, .value = null });
        },
        .array => |arr| {
            try data.append(allo, .{ .type = .array, .depth = depth, .value = null });
            for (arr.items) |item| {
                try walkJson(allo, item, depth + 1, data);
            }
            try data.append(allo, .{ .type = .array_end, .depth = depth, .value = null });
        },
        .string => |s| {
            const new_str = try allo.dupe(u8, s);
            try data.append(allo, .{ .type = .string, .depth = depth, .value = new_str });
        },
        .integer => |n| {
            const new_str = try std.fmt.allocPrint(allo, "{}", .{n});
            try data.append(allo, .{ .type = .integer, .depth = depth, .value = new_str });
        },
        .float => |f| {
            const new_str = try std.fmt.allocPrint(allo, "{}", .{f});
            try data.append(allo, .{ .type = .float, .depth = depth, .value = new_str });
        },
        .number_string => |s| {
            const new_str = try std.fmt.allocPrint(allo, "{s}", .{s});
            try data.append(allo, .{ .type = .number_string, .depth = depth, .value = new_str });
        },
        .bool => |b| {
            const new_str = if (b) try allo.dupe(u8, "true") else try allo.dupe(u8, "false");
            try data.append(allo, .{ .type = .bool, .depth = depth, .value = new_str });
        },
        .null => {
            try data.append(allo, .{ .type = .null, .depth = depth, .value = null });
        },
    }
}

fn jsonStringify(
    data: *const std.ArrayList(JsonData),
    file: std.fs.File,
) !void {
    var buffer: [1024]u8 = undefined;
    const spaces = [_]u8{' '} ** 1024;
    var i: usize = 0;
    while (i < data.items.len) : (i += 1) {
        const datum = data.items[i];
        const indent = spaces[0..(datum.depth * 2)];
        var line: []const u8 = undefined;

        const new_indent = blk: {
            break :blk switch (data.items[i].type) {
                .object => if (i > 0) switch (data.items[i - 1].type) {
                    .object_key => "",
                    else => indent,
                } else "",
                .object_end => if (i > 0) switch (data.items[i - 1].type) {
                    .object => "",
                    else => indent,
                } else "",
                .array_end => if (i > 0) switch (data.items[i - 1].type) {
                    .array => "",
                    else => indent,
                } else "",
                else => break :blk "",
            };
        };
        const new_comma = blk: {
            if (i + 1 == data.items.len) break :blk "";
            break :blk switch (data.items[i + 1].type) {
                .object_end, .array_end => "",
                else => ",",
            };
        };
        const new_line = blk: {
            break :blk switch (data.items[i].type) {
                .object => switch (data.items[i + 1].type) {
                    .object_end => "",
                    else => "\n",
                },
                .object_end => if (i + 1 < data.items.len) "\n" else "",
                .array => switch (data.items[i + 1].type) {
                    .array_end => "",
                    else => "\n",
                },
                else => "\n",
            };
        };
        switch (datum.type) {
            .object => {
                line = try std.fmt.bufPrint(&buffer, "{s}{{{s}", .{ new_indent, new_line });
                // print("{s}{{{s}", .{ new_indent, new_line });
            },
            .object_key => {
                line = try std.fmt.bufPrint(&buffer, "{s}\"{s}\": ", .{ indent, datum.value.? });
                // print("{s}\"{s}\": ", .{ indent, datum.value.? });
            },
            .object_end => {
                line = try std.fmt.bufPrint(&buffer, "{s}}}{s}{s}", .{ new_indent, new_comma, new_line });
                // print("{s}}}{s}{s}", .{ new_indent, new_comma, new_line });
            },
            .array => {
                line = try std.fmt.bufPrint(&buffer, "{s}[{s}", .{ new_indent, new_line });
                // print("{s}[{s}", .{ new_indent, new_line });
            },
            .array_end => {
                line = try std.fmt.bufPrint(&buffer, "{s}]{s}{s}", .{ new_indent, new_comma, new_line });
                // print("{s}]{s}\n", .{ new_indent, new_comma });
            },
            .integer, .float, .bool => {
                line = try std.fmt.bufPrint(&buffer, "{s}{s}{s}", .{ datum.value.?, new_comma, new_line });
                // print("{s},\n", .{datum.value.?});
            },
            .number_string => {
                line = try std.fmt.bufPrint(&buffer, "\"{s}\"{s}{s}", .{ datum.value.?, new_comma, new_line });
                // print("\"{s}\",\n", .{datum.value.?});
            },
            .string => {
                var tmp: [1024]u8 = undefined;
                const old_line = datum.value.?;
                var k: usize = 1;
                tmp[0] = old_line[0];
                for (old_line[1..old_line.len], 1..) |ch, j| {
                    switch (ch) {
                        '\\' => {
                            switch (old_line[j - 1]) {
                                '\\' => { // second time
                                    tmp[k] = '\\';
                                },
                                else => { // first time
                                    switch (old_line[j + 1]) {
                                        '\\' => {
                                            tmp[k] = '\\';
                                        },
                                        else => {
                                            tmp[k] = '\\';
                                            tmp[k + 1] = '\\';
                                            k += 2;
                                        },
                                    }
                                },
                            }
                        },
                        else => { // normal case
                            tmp[k] = ch;
                            k += 1;
                        },
                    }
                }
                const tmp_line = tmp[0..k];
                line = try std.fmt.bufPrint(
                    &buffer,
                    "\"{s}\"{s}{s}",
                    .{ tmp_line, new_comma, new_line },
                );
            },
            .null => {
                line = try std.fmt.bufPrint(&buffer, "{s}", .{new_line});
                // print("\n", .{});
            },
        }
        _ = try file.write(line);
    }
}
