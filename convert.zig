const std = @import("std");

const gpa = std.heap.page_allocator;

pub fn main() !void {
  const input =
  \\   /// ---Create a new hook on an event
\\ /// ---@param events string|string[]
\\  /// ---@param options table
\\ pub fn add(L: *zlua.Lua) i32 {
  ;

  var buf: [1048]u8 = undefined;
  var stdout = @constCast(&std.fs.File.stdout().writer(&buf).interface);

  var tokenizer = Tokenizer.init("test.zig", input);
  while (true) {
    const tok = tokenizer.next();
    try stdout.print("+++ {}\n", .{ tok });
    try stdout.print("--- {s}\n", .{ input[tok.loc.start..tok.loc.end] });

  }

  try stdout.flush();
}

const Token = struct {
  tag: Tag,
  loc: Loc,

  pub const Loc = struct {
    start: usize,
    end: usize,
  };

  pub const keywords = std.StaticStringMap(Tag).initComptime(.{
    .{ "@alias", .keyword_lua_doc_alias },
    .{ "@param", .keyword_lua_doc_param },
    .{ "@return", .keyword_lua_doc_return },
  });

  pub fn getKeyword(bytes: []const u8) ?Tag {
    return keywords.get(bytes);
  }

  const Tag = enum {
    identifier,

    // zig tags
    zig_doc_comment,

    // luadoc tags
    lua_doc_type,
    lua_doc_param_name,
    lua_doc_comment,
    keyword_lua_doc_alias,
    keyword_lua_doc_param,
    keyword_lua_doc_return,

    invalid,
    eof,
  };
};


const Tokenizer = struct {
  buffer: []const u8,
  index: usize,
  state: State,
  source_file_name: []const u8,

  const State = enum {
    start,
    expect_newline,
    slash,
    doc_comment_start,
    doc_comment,
    minus,
    lua_doc_start,
    lua_doc,
    identifier,

    invalid,
    eof,
  };

  fn init(source_file_name: []const u8, buffer: []const u8) Tokenizer {
    return Tokenizer{
      .buffer = buffer,
      .index = 0,
      .state = .start,
      .source_file_name = source_file_name,
    };
  }

  fn next(self: *Tokenizer) Token {
    var result = Token{
      .tag = .eof,
      .loc = .{
        .start = self.index,
        .end = undefined,
      },
    };
    state: switch (State.start) {
      .start => switch (self.buffer[self.index]) {
        0 => {
          if (self.index == self.buffer.len) {
            return .{
              .tag = .eof,
              .loc = .{
                .start = self.index,
                .end = self.index,
              },
            };
          } else {
            continue :state .invalid;
          }
        },
        'a'...'z', 'A'...'Z', '_' => {
          result.tag = .identifier;
          continue :state .identifier;
        },
        '/' => continue :state .slash,
        ' ', '\n', '\t', '\r' => {
          self.index += 1;
          result.loc.start = self.index;
          continue :state .start;
        },
        else => continue :state .invalid,
      },
      .expect_newline => {
        self.index += 1;
        switch (self.buffer[self.index]) {
          0 => {
            if (self.index == self.buffer.len) {
              result.tag = .invalid;
            } else {
              continue :state .invalid;
            }
          },
          '\n' => {
            self.index += 1;
            result.loc.start = self.index;
            continue :state .start;
          },
          else => continue :state .invalid,
        }
      },
      .slash => {
        self.index += 1;
        switch (self.buffer[self.index]) {
          '/' => continue :state .doc_comment_start,
          else => continue :state .invalid,
        }
      },
      .doc_comment_start => {
        self.index += 1;
        switch (self.buffer[self.index]) {
          0 => {
            if (self.index != self.buffer.len) {
              continue :state .invalid;
            } else return .{
              .tag = .eof,
              .loc = .{
                .start = self.index,
                .end = self.index,
              },
            };
          },
          '!', '/' => {
            result.tag = .zig_doc_comment;
            continue :state .doc_comment;
          },
          '\n' => {
            self.index += 1;
            result.loc.start = self.index;
            continue :state .start;
          },
          '\r' => continue :state .expect_newline,
          else => continue :state .invalid,
        }
      },
      .doc_comment => {
        self.index += 1;
        switch (self.buffer[self.index]) {
          0, '\n' => {},
          '-' => continue :state .minus,
          '\r' => if (self.buffer[self.index + 1] != '\n') {
            continue :state .invalid;
          },
          0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => {
            continue :state .invalid;
          },
          else => continue :state .doc_comment,
        }
      },
      .minus => {
        self.index += 1;
        switch (self.buffer[self.index]) {
          '-' => continue :state .lua_doc_start,
          else => continue :state .doc_comment,
        }
      },
      .lua_doc_start => {
        self.index += 1;
        switch (self.buffer[self.index]) {
          '-' => continue :state .lua_doc,
          else => continue :state .doc_comment,
        }
      },
      .lua_doc => {
        self.index += 1;
        switch (self.buffer[self.index]) {
          'a'...'z', 'A'...'Z', '_', '@', '-', '|', '[', ']' => {
            result.tag = .identifier;
            continue :state .identifier;
          },
          else => continue :state .doc_comment,
        }
      },
      .identifier => {
        self.index += 1;
        switch (self.buffer[self.index]) {
          'a'...'z', 'A'...'Z', '_', '0'...'9', '@', '-', '|', '[', ']' => continue :state .identifier,
          else => {
            const ident = self.buffer[result.loc.start..self.index];
            if (Token.getKeyword(ident)) |tag| result.tag = tag;
          },
        }
      },
      .invalid => {
        self.index += 1;
        switch (self.buffer[self.index]) {
          0 => if (self.index == self.buffer.len) {
            result.tag = .invalid;
          } else {
              continue :state .invalid;
            },
          '\n' => result.tag = .invalid,
          ' ' => continue :state .start,
          else => continue :state .invalid,
        }
      },

      .eof => unreachable,
    }

    result.loc.end = self.index;
    return result;
  }
};
