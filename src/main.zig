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
    // access tree
    const root = tree.value;
    const profiles = root.object.get("profiles") orelse {
        return error.MissingField;
    };
    const defaults = profiles.object.get("defaults") orelse {
        return error.MissingField;
    };
    var background_img = defaults.object.get("backgroundImage") orelse return error.MissingField;
    background_img.string = img_path;
    // turn into file
    const out_file = try std.fs.createFileAbsolute(
        "C:\\Users\\bphil\\AppData\\Local\\Packages\\Microsoft.WindowsTerminal_8wekyb3d8bbwe\\LocalState\\settings2.json",
        .{},
    );
    defer out_file.close();
    var write_stream: std.json.Stringify = .{
        .writer = &out_file.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try write_stream.beginObject();
    try write_stream.objectField("foo");
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
    print("{s}\n", .{home});
    const new_filepath = try std.fs.path.join(
        allo,
        &.{ home, "AppData\\Local\\Packages\\Microsoft.WindowsTerminal_8wekyb3d8bbwe\\LocalState\\settings.json" },
    );
    return new_filepath;
}
