const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;

// TODO:
// 1. create dir containing your favorite wallpapers - done
// 2. push up to github - done
// 3. pull down through code onto different machines - done
// 4. change wallpapers programmatically -

pub fn main() !void {
    // mem
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allo = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    // subpaths
    const home: []const u8 = try getHomeDir(allo);
    defer allo.free(home);
    const dir_path_from_home: []const u8 = switch (@import("builtin").os.tag) {
        .windows => "\\Pictures\\Wallpapers",
        .linux, .macos => "/Pictures",
        else => unreachable,
    };
    // abs path
    const wallpapers_path = try std.fs.path.join(allo, &.{ home, dir_path_from_home });
    defer allo.free(wallpapers_path);
    print("Wallpapers Path: {s}\n", .{wallpapers_path});
    // clone wallpapers
    if (!dirExists(wallpapers_path)) {
        const args = [_][]const u8{
            "git",
            "clone",
            "https://github.com/bphilip777/Wallpapers",
            wallpapers_path,
        };
        var child = std.process.Child.init(&args, allo);
        const result = try child.spawnAndWait();
        switch (result) {
            .Exited => {},
            else => {
                print("{s} {s} {s} {s} failed.\n", .{
                    args[0],
                    args[1],
                    args[2],
                    wallpapers_path,
                });
                return;
            },
        }
    }
    // walk dir - choose random image
    var dir = try std.fs.openDirAbsolute(wallpapers_path, .{ .iterate = true });
    defer dir.close();
    // init pic mem
    var pics: std.ArrayList([]const u8) = try .initCapacity(allo, 8);
    defer pics.deinit(allo);
    defer for (pics.items) |pic| allo.free(pic);
    // get pics
    var it = dir.iterate();
    while (try it.next()) |item| {
        switch (item.kind) {
            .file => {
                print("{s}\n", .{item.name});
            },
            else => continue,
        }
    }

    // // env var settings.json
    // const local_dir = std.process.getEnvVarOwned(allo, "LOCALAPPDATA") catch |err| switch (err) {
    //     error.EnvironmentVariableNotFound => {
    //         print("Local App Data not found.\n", .{});
    //         return;
    //     },
    //     else => return err,
    // };
    // defer allo.free(local_dir);
    // // look for settings.json
    // const settings_json_path = try std.fs.path.join(
    //     allo,
    //     &.{ home, "AppData\\Local\\Packages\\Microsoft.WindowsTerminal_8wekyb3d8bbwe\\LocalState\\settings.json" },
    // );
    // defer allo.free(settings_json_path);

    // find new image

    // // read file line by line
    // var reader = try Reader.init(settings_json_path);
    // defer reader.deinit();
    // // init storage
    // var data: std.ArrayList([]const u8) = try .initCapacity(allo, 1024);
    // defer data.deinit(allo);
    // defer for (data.items) |item| allo.free(item);
    // // reader
    // while (reader.read()) |line| {
    //     const newline = try allo.dupe(u8, line);
    //     try data.append(allo, newline);
    // }
    // // write file
    // for (data.items, 0..) |line, i| {
    //     // print("{}: {s}\n", .{ i, line });
    //     if (std.mem.containsAtLeast(u8, line, 1, "\"backgroundImage\"")) {
    //         print("{}: {s}\n", .{ i, line });
    //     }
    // }
}

fn dirExists(abs_path: []const u8) bool {
    std.fs.accessAbsolute(abs_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return true,
    };
    return true;
}

fn getHomeDir(allo: Allocator) ![]const u8 {
    const var_name = if (@import("builtin").os.tag == .windows) "USERPROFILE" else "HOME";
    const home = std.process.getEnvVarOwned(allo, var_name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            print("Home directory not found.\n", .{});
            return err;
        },
        else => return err,
    };
    return home;
}

const Reader = struct {
    file: std.fs.File = undefined,
    reader: std.fs.File.Reader = undefined,

    read_buf: [4096]u8 = undefined,
    line_buf: [1024]u8 = undefined,

    start: u16 = 0,
    end: u16 = 0,
    n_bytes: u16 = 0,

    pub fn init(filename: []const u8) !@This() {
        var self: @This() = .{};
        self.file = try std.fs.openFileAbsolute(filename, .{});
        self.reader = self.file.reader(&self.read_buf);
        self.n_bytes = @truncate(try self.reader.read(&self.line_buf));
        return self;
    }

    pub fn deinit(self: *@This()) void {
        self.file.close();
    }

    pub fn read(self: *@This()) ?[]const u8 {
        // read line
        self.end = self.start;
        while (self.end < self.n_bytes) : (self.end += 1) {
            switch (self.line_buf[self.end]) {
                '\n' => {
                    const line = self.line_buf[self.start..self.end];
                    self.start += @truncate(line.len);
                    self.start += 1;
                    return line;
                },
                else => continue,
            }
        }
        // load next line
        // wrap
        const diff = self.end - self.start;
        if (diff < self.start) { // no alias
            @memcpy(self.line_buf[0..diff], self.line_buf[self.start..self.end]);
        } else { // alias
            var tmp: [1024]u8 = undefined;
            @memcpy(tmp[0..diff], self.line_buf[self.start..self.end]);
            @memcpy(self.line_buf[0..diff], tmp[0..diff]);
        }
        const n_bytes = self.reader.read(self.line_buf[diff..self.line_buf.len]) catch {
            if (self.start != self.end) {
                const line = self.line_buf[self.start..self.end];
                self.start = self.end;
                return line;
            }
            return null;
        };
        self.n_bytes = @truncate(n_bytes);
        self.n_bytes += diff;
        self.start = 0;
        self.end = diff;
        // read line
        while (self.end < self.n_bytes) : (self.end += 1) {
            switch (self.line_buf[self.end]) {
                '\n' => {
                    const line = self.line_buf[self.start..self.end];
                    self.start += @truncate(line.len);
                    self.start += 1;
                    return line;
                },
                else => continue,
            }
        }
        unreachable;
    }
};
