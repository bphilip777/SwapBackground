const std = @import("std");
const Reader = @This();

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
                const line = self.line_buf[self.start .. self.end + 1];
                self.start += @truncate(line.len);
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
                const line = self.line_buf[self.start .. self.end + 1];
                self.start += @truncate(line.len);
                return line;
            },
            else => continue,
        }
    }
    unreachable;
}
