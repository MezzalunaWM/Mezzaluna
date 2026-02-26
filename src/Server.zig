const Server = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Root             = @import("Root.zig");
const Seat             = @import("Seat.zig");
const Cursor           = @import("Cursor.zig");
const Keyboard         = @import("Keyboard.zig");
const LayerSurface     = @import("LayerSurface.zig");
const Output           = @import("Output.zig");
const View             = @import("View.zig");
const Keymap           = @import("types/Keymap.zig");
const Mousemap         = @import("types/Mousemap.zig");
const Hook             = @import("types/Hook.zig");
const Events           = @import("types/Events.zig");
const Popup            = @import("Popup.zig");
const RemoteLua        = @import("RemoteLua.zig");
const RemoteLuaManager = @import("RemoteLuaManager.zig");
const Utils            = @import("Utils.zig");
const SceneNodeData    = @import("SceneNodeData.zig").SceneNodeData;

const gpa = std.heap.c_allocator;
const server = &@import("main.zig").server;

wl_server: *wl.Server,
compositor: *wlr.Compositor,
renderer: *wlr.Renderer,
backend: *wlr.Backend,
event_loop: *wl.EventLoop,
session: ?*wlr.Session,
remote_lua_manager: ?*RemoteLuaManager,

shm: *wlr.Shm,
xdg_shell: *wlr.XdgShell,
layer_shell: *wlr.LayerShellV1,
xdg_toplevel_decoration_manager: *wlr.XdgDecorationManagerV1,
xdg_activation: *wlr.XdgActivationV1,

allocator: *wlr.Allocator,

root: Root,
seat: Seat,
cursor: Cursor,

// Lua data
keymaps: std.AutoHashMap(u64, Keymap),
mousemaps: std.AutoHashMap(u64, Mousemap),
hooks: std.AutoHashMap(i32, *Hook),
events: Events,
remote_lua_clients: std.DoublyLinkedList,

// Backend listeners
new_input: wl.Listener(*wlr.InputDevice) = .init(handleNewInput),
new_output: wl.Listener(*wlr.Output) = .init(handleNewOutput),
// backend.events.destroy
new_xdg_toplevel: wl.Listener(*wlr.XdgToplevel) = .init(handleNewXdgToplevel),
new_xdg_popup: wl.Listener(*wlr.XdgPopup) = .init(handleNewXdgPopup),
new_xdg_toplevel_decoration: wl.Listener(*wlr.XdgToplevelDecorationV1) = .init(handleNewXdgToplevelDecoration),
new_layer_surface: wl.Listener(*wlr.LayerSurfaceV1) = .init(handleNewLayerSurface),
request_activate: wl.Listener(*wlr.XdgActivationV1.event.RequestActivate) = .init(handleRequestActivate),

pub fn init(self: *Server) void {
  errdefer Utils.oomPanic();

  const wl_server = wl.Server.create() catch {
    std.log.err("Server create failed, exiting with 2", .{});
    std.process.exit(2);
  };

  const event_loop = wl_server.getEventLoop();

  var session: ?*wlr.Session = undefined;
  const backend = wlr.Backend.autocreate(event_loop, &session) catch {
    std.log.err("Backend create failed, exiting with 3", .{});
    std.process.exit(3);
  };

  const renderer = wlr.Renderer.autocreate(backend) catch {
    std.log.err("Renderer create failed, exiting with 4", .{});
    std.process.exit(4);
  };

  self.* = .{
    .wl_server = wl_server,
    .backend = backend,
    .renderer = renderer,
    .allocator = wlr.Allocator.autocreate(backend, renderer) catch {
      std.log.err("Allocator create failed, exiting with 5", .{});
      std.process.exit(5);
    },
    .xdg_shell = try wlr.XdgShell.create(wl_server, 2),
    .layer_shell = try wlr.LayerShellV1.create(wl_server, 4),
    .xdg_toplevel_decoration_manager = try wlr.XdgDecorationManagerV1.create(self.wl_server),
    .xdg_activation = try wlr.XdgActivationV1.create(self.wl_server),
    .event_loop = event_loop,
    .session = session,
    .compositor = try wlr.Compositor.create(wl_server, 6, renderer),
    .shm = try wlr.Shm.createWithRenderer(wl_server, 1, renderer),
    // TODO: let the user configure a cursor theme and side lua
    .root = undefined,
    .seat = undefined,
    .cursor = undefined,
    .remote_lua_manager = RemoteLuaManager.init() catch Utils.oomPanic(),
    .keymaps = .init(gpa),
    .mousemaps = .init(gpa),
    .hooks = .init(gpa),
    .events = try .init(gpa),
    .remote_lua_clients = .{},
  };

  self.renderer.initServer(wl_server) catch {
      std.log.err("Renderer init failed, exiting with 6", .{});
      std.process.exit(6);
  };

  self.root.init();
  self.seat.init();
  self.cursor.init();

  _ = try wlr.Subcompositor.create(self.wl_server);
  _ = try wlr.DataDeviceManager.create(self.wl_server);
  _ = try wlr.ExportDmabufManagerV1.create(self.wl_server);
  _ = try wlr.Viewporter.create(self.wl_server);
  _ = try wlr.Presentation.create(self.wl_server, self.backend, 2);
  _ = try wlr.ScreencopyManagerV1.create(self.wl_server);
  _ = try wlr.AlphaModifierV1.create(self.wl_server);
  _ = try wlr.DataControlManagerV1.create(self.wl_server);
  _ = try wlr.PrimarySelectionDeviceManagerV1.create(self.wl_server);
  _ = try wlr.SinglePixelBufferManagerV1.create(self.wl_server);
  _ = try wlr.FractionalScaleManagerV1.create(self.wl_server, 1);
  _ = try wlr.XdgOutputManagerV1.create(self.wl_server, self.root.output_layout);
  self.root.scene.setGammaControlManagerV1(try wlr.GammaControlManagerV1.create(self.wl_server));

  // Add event listeners to events
  self.backend.events.new_input.add(&self.new_input);
  self.backend.events.new_output.add(&self.new_output);
  self.xdg_shell.events.new_toplevel.add(&self.new_xdg_toplevel);
  self.xdg_shell.events.new_popup.add(&self.new_xdg_popup);
  self.xdg_toplevel_decoration_manager.events.new_toplevel_decoration.add(&self.new_xdg_toplevel_decoration);
  self.layer_shell.events.new_surface.add(&self.new_layer_surface);
  self.xdg_activation.events.request_activate.add(&self.request_activate);

  self.events.exec("ServerStartPost", .{});
}

pub fn deinit(self: *Server) noreturn {
  self.new_input.link.remove();
  self.new_output.link.remove();
  self.new_xdg_toplevel.link.remove();
  self.new_xdg_popup.link.remove();
  self.new_xdg_toplevel_decoration.link.remove();
  self.new_layer_surface.link.remove();

  self.seat.deinit();
  self.root.deinit();
  self.cursor.deinit();

  self.backend.destroy();

  self.wl_server.destroyClients();
  self.wl_server.destroy();

  std.log.debug("Exiting mez succesfully", .{});
  std.process.exit(0);
}

// --------- Backend event handlers ---------
fn handleNewInput(
  _: *wl.Listener(*wlr.InputDevice),
  device: *wlr.InputDevice
) void {
  switch (device.type) {
    .keyboard => _ = Keyboard.init(device),
    .pointer => server.cursor.wlr_cursor.attachInputDevice(device),
    else => {
      std.log.err(
        "New input request for input that is not a keyboard or pointer: {s}",
        .{device.name orelse "(null)"}
      );
    },
  }

  // We should really only set true capabilities
  server.seat.wlr_seat.setCapabilities(.{
    .pointer = true,
    .keyboard = true,
  });
}

fn handleNewOutput(
  _: *wl.Listener(*wlr.Output),
  wlr_output: *wlr.Output
) void {
  _ = Output.init(wlr_output);
}

fn handleNewXdgToplevel(
  _: *wl.Listener(*wlr.XdgToplevel),
  xdg_toplevel: *wlr.XdgToplevel
) void {
  _ = View.init(xdg_toplevel);
}

fn handleNewXdgToplevelDecoration(
  _: *wl.Listener(*wlr.XdgToplevelDecorationV1),
  decoration: *wlr.XdgToplevelDecorationV1
) void {
  if(server.root.viewById(@intFromPtr(decoration.toplevel))) |view| {
    view.xdg_toplevel_decoration = decoration;
  }
}

fn handleNewXdgPopup(_: *wl.Listener(*wlr.XdgPopup), _: *wlr.XdgPopup) void {
  std.log.debug("Unimplemented Server.handleNewXdgPopup\n", .{});
}

fn handleNewLayerSurface(
  _: *wl.Listener(*wlr.LayerSurfaceV1),
  layer_surface: *wlr.LayerSurfaceV1
) void {
  std.log.debug("requested layer shell\n", .{});
  if (layer_surface.output == null) {
    if (server.seat.focused_output == null) {
      std.log.err("No output available for new layer surface", .{});
      layer_surface.destroy();
      return;
    }

    layer_surface.output = server.seat.focused_output.?.wlr_output;
  }

  _ = LayerSurface.init(layer_surface);
}

fn handleRequestActivate(
    _: *wl.Listener(*wlr.XdgActivationV1.event.RequestActivate),
    event: *wlr.XdgActivationV1.event.RequestActivate,
) void {
  if(event.surface.data == null) return;

  const scene_node_data: *SceneNodeData = @ptrCast(@alignCast(event.surface.data.?));

  if(scene_node_data.* == .view) {
    if(server.seat.focused_output) |output| {
      if(output.fullscreen) |fullscreen| {
        server.seat.focusSurface(.{ .view = fullscreen });
        return;
      }
    }
    server.seat.focusSurface(Seat.FocusData{ .view = scene_node_data.view });
  } else {
    std.log.warn("Ignoring request to activate non-view", .{});
  }
}
