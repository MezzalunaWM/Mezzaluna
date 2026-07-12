const Server = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const xev = @import("xev");

const Root = @import("Root.zig");
const Seat = @import("Seat.zig");
const Keyboard = @import("Keyboard.zig");
const LayerSurface = @import("LayerSurface.zig");
const Output = @import("Output.zig");
const View = @import("View.zig");
const IdleInhibitor = @import("IdleInhibitor.zig");
const IdleNotifier = @import("IdleNotifer.zig");
const Hook = @import("lua/Hook.zig");
const Async = @import("lua/Async.zig");
const input_device = @import("input_device.zig");
const Popup = @import("Popup.zig");
const RemoteLua = @import("RemoteLua.zig");
const RemoteLuaManager = @import("RemoteLuaManager.zig");
const Utils = @import("Utils.zig");
const SceneNode = @import("SceneNode.zig");
const PointerConstraint = @import("PointerConstraint.zig");

const gpa = std.heap.c_allocator;

running: bool,
event_loop: *wl.EventLoop,
xev_event_loop: xev.Loop,

wl_server: *wl.Server,
session: ?*wlr.Session,
compositor: *wlr.Compositor,
shm: *wlr.Shm,
backend: *wlr.Backend,
renderer: *wlr.Renderer,
drm_lease_manager: ?*wlr.DrmLeaseManagerV1 = null,
linux_dmabuf: ?*wlr.LinuxDmabufV1 = null,
linux_drm_syncobj_manager: ?*wlr.LinuxDrmSyncobjManagerV1 = null,

idle_inhibit_manager: *wlr.IdleInhibitManagerV1,
idle_notifier: *IdleNotifier,
allocator: *wlr.Allocator,
root: Root,
seats: wl.list.Head(Seat, .link),

virtual_pointer_manager: *wlr.VirtualPointerManagerV1,
virtual_keyboard_manager: *wlr.VirtualKeyboardManagerV1,

xdg_shell: *wlr.XdgShell,
layer_shell: *wlr.LayerShellV1,
xdg_toplevel_decoration_manager: *wlr.XdgDecorationManagerV1,
xdg_activation: *wlr.XdgActivationV1,

relative_pointer_manager: *wlr.RelativePointerManagerV1,
pointer_constraints: *wlr.PointerConstraintsV1,

// Lua data
remote_lua_manager: ?*RemoteLuaManager,
remote_lua_clients: std.DoublyLinkedList,
hooks: std.AutoHashMap(i32, *Hook.HookData),
events: Hook.Events,
async_callbacks: std.AutoHashMap(usize, *Async.AsyncData),

// Backend listeners
new_input: wl.Listener(*wlr.InputDevice) = .init(handleNewInput),
new_output: wl.Listener(*wlr.Output) = .init(handleNewOutput),
// backend.events.destroy
new_xdg_toplevel: wl.Listener(*wlr.XdgToplevel) = .init(handleNewXdgToplevel),
new_xdg_popup: wl.Listener(*wlr.XdgPopup) = .init(handleNewXdgPopup),
new_xdg_toplevel_decoration: wl.Listener(*wlr.XdgToplevelDecorationV1) = .init(handleNewXdgToplevelDecoration),
new_layer_surface: wl.Listener(*wlr.LayerSurfaceV1) = .init(handleNewLayerSurface),
request_activate: wl.Listener(*wlr.XdgActivationV1.event.RequestActivate) = .init(handleRequestActivate),

new_virtual_pointer: wl.Listener(*wlr.VirtualPointerManagerV1.event.NewPointer) = .init(handleNewVirtualPointer),
new_virtual_keyboard: wl.Listener(*wlr.VirtualKeyboardV1) = .init(handleNewVirtualKeyboard),

new_idle_inhibitor: wl.Listener(*wlr.IdleInhibitorV1) = .init(handleNewIdleInhibitor),
drm_lease_request: wl.Listener(*wlr.DrmLeaseRequestV1) = .init(handleDrmRequest),

new_pointer_constraint: wl.Listener(*wlr.PointerConstraintV1) = .init(handleNewPointerConstraint),

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
        // event loop
        .running = true,
        .event_loop = event_loop,
        .xev_event_loop = try .init(.{}),

        // core wayland
        .wl_server = wl_server,
        .session = session,
        .compositor = try wlr.Compositor.create(wl_server, 6, renderer),
        .shm = try wlr.Shm.createWithRenderer(wl_server, 2, renderer),
        .backend = backend,
        .renderer = renderer,
        .allocator = wlr.Allocator.autocreate(backend, renderer) catch {
            std.log.err("Allocator create failed, exiting with 5", .{});
            std.process.exit(5);
        },
        .root = undefined,
        .seats = undefined,
        .drm_lease_manager = wlr.DrmLeaseManagerV1.create(self.wl_server, self.backend),

        // additional wayland protocols
        .idle_inhibit_manager = try wlr.IdleInhibitManagerV1.create(wl_server),
        .idle_notifier = .init(),

        .xdg_shell = try wlr.XdgShell.create(wl_server, 6),
        .layer_shell = try wlr.LayerShellV1.create(wl_server, 5),
        .xdg_toplevel_decoration_manager = try wlr.XdgDecorationManagerV1.create(self.wl_server),
        .xdg_activation = try wlr.XdgActivationV1.create(self.wl_server),

        .virtual_pointer_manager = try wlr.VirtualPointerManagerV1.create(self.wl_server),
        .virtual_keyboard_manager = try wlr.VirtualKeyboardManagerV1.create(self.wl_server),

        .relative_pointer_manager = try wlr.RelativePointerManagerV1.create(self.wl_server),
        .pointer_constraints = try wlr.PointerConstraintsV1.create(self.wl_server),

        // lua stuff
        .remote_lua_manager = RemoteLuaManager.init() catch Utils.oomPanic(),
        .remote_lua_clients = .{},
        .hooks = .init(gpa),
        .events = try .init(gpa),
        .async_callbacks = .init(gpa),
    };

    if (renderer.getTextureFormats(@intFromEnum(wlr.BufferCap.dmabuf)) != null) {
        self.linux_dmabuf = try wlr.LinuxDmabufV1.createWithRenderer(wl_server, 5, renderer);
    }
    if (renderer.features.timeline and backend.features.timeline) {
        const drm_fd = renderer.getDrmFd();
        if (drm_fd >= 0) {
            self.linux_drm_syncobj_manager = wlr.LinuxDrmSyncobjManagerV1.create(wl_server, 1, drm_fd);
        }
    }

    if (self.drm_lease_manager != null) {
        self.drm_lease_manager.?.events.request.add(&self.drm_lease_request);
    }

    self.renderer.initServer(wl_server) catch {
        std.log.err("Renderer init failed, exiting with 6", .{});
        std.process.exit(6);
    };

    self.root.init();

    // create the default seat
    self.seats.init();
    self.seats.append(try Seat.init("default"));

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

    self.virtual_pointer_manager.events.new_virtual_pointer.add(&self.new_virtual_pointer);
    self.virtual_keyboard_manager.events.new_virtual_keyboard.add(&self.new_virtual_keyboard);

    self.idle_inhibit_manager.events.new_inhibitor.add(&self.new_idle_inhibitor);

    self.pointer_constraints.events.new_constraint.add(&self.new_pointer_constraint);

    self.events.exec("ServerStartPost", .{}, "Just after Mezzaluna has successfully started.");
}

/// libwayland uses a bool which the event loop checks to see if the server
/// should be running, this is not included in our bindings, so we maintain our
/// own.
pub fn terminate(self: *Server) void {
    // we still call as libwayland does write some information to a fd about
    // termination
    self.wl_server.terminate();

    self.running = false;
}

pub fn run(self: *Server) void {
    // this polls the wayland event loop file descriptor to check for any
    // events we need to handle
    const stream = xev.Stream.initFd(self.event_loop.getFd());
    defer stream.deinit();

    var stream_c: xev.Completion = undefined;
    stream.poll(&self.xev_event_loop, &stream_c, .read, Server, self, &struct {
        fn callback(
            userdata: ?*Server,
            loop: *xev.Loop,
            _: *xev.Completion,
            _: xev.Stream,
            _: xev.PollError!xev.PollEvent,
        ) xev.CallbackAction {
            const s: *Server = userdata.?;
            if (!s.running) loop.stop();
            s.dispatchEvents(loop);
            return .rearm;
        }
    }.callback);

    self.xev_event_loop.run(.until_done) catch |err| {
        std.log.err("Failed to run wayland event loop: {}", .{ err });
    };
}

pub fn dispatchEvents(self: *Server, loop: *xev.Loop) void {
    // dispatch events then tell the clients that there's stuff for them to do
    self.event_loop.dispatch(0) catch loop.stop();
    self.wl_server.flushClients();
}

pub fn getDefaultSeat(self: *Server) *Seat {
    return self.seats.first() orelse unreachable; // shouldn't ever be null
}

pub fn deinit(self: *Server) noreturn {
    self.new_input.link.remove();
    self.new_output.link.remove();
    self.new_xdg_toplevel.link.remove();
    self.new_xdg_popup.link.remove();
    self.new_xdg_toplevel_decoration.link.remove();
    self.new_layer_surface.link.remove();

    self.root.deinit();

    self.backend.destroy();

    self.wl_server.destroyClients();
    self.wl_server.destroy();

    self.xev_event_loop.deinit();

    self.async_callbacks.deinit();

    std.log.debug("Exiting mez succesfully", .{});
    std.process.exit(0);
}

// --------- Backend event handlers ---------
fn handleNewInput(listener: *wl.Listener(*wlr.InputDevice), device: *wlr.InputDevice) void {
    const self: *Server = @fieldParentPtr("new_input", listener);

    // create the device
    input_device.init(device);

    self.events.exec("DeviceAddPre", .{ device }, "Called before a new device is added to the compositor.");
    const dev = input_device.get(device) orelse return;

    // has the user already given the device to a seat?
    const seated = switch (dev) {
        .keyboard => |keyboard| if (keyboard.group != null) true else false,
        .pointer => |pointer| if (pointer.base.data != null) true else false,
        else => false,
    };

    if (!seated) self.getDefaultSeat().addInputDevice(device);

    self.events.exec("DeviceAddPost", .{ device }, "Called after a new device is added to the compositor.");
}

fn handleNewOutput(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    const self: *Server = @fieldParentPtr("new_output", listener);
    const output = Output.init(wlr_output) orelse {
        std.log.err("Failed to create new output", .{});
        return;
    };

    // TODO: Allow user to define output positions
    const layout_output = self.root.output_layout.addAuto(output.wlr_output) catch {
        std.log.err("failed to add output to the output layout", .{});
        return;
    };

    output.scene_output.setPosition(layout_output.x, layout_output.y);

    // FIXME: without this the lua api can crash mez very easily. Thankfully we
    // don't have a case for not having any output selected, but it'd still be
    // better if we didn't crash.
    if (self.getDefaultSeat().focused_output == null) {
        self.getDefaultSeat().focusOutput(output);
    }

    Root.configureOutputs(&self.root);
    output.arrangeLayers();
}

fn handleNewXdgToplevel(_: *wl.Listener(*wlr.XdgToplevel), xdg_toplevel: *wlr.XdgToplevel) void {
    _ = View.init(xdg_toplevel);
}

fn handleNewXdgToplevelDecoration(listener: *wl.Listener(*wlr.XdgToplevelDecorationV1), decoration: *wlr.XdgToplevelDecorationV1) void {
    const self: *Server = @fieldParentPtr("new_xdg_toplevel_decoration", listener);

    if (self.root.viewById(@intFromPtr(decoration.toplevel))) |view| {
        view.xdg_toplevel_decoration = decoration;
    }
}

fn handleNewXdgPopup(_: *wl.Listener(*wlr.XdgPopup), _: *wlr.XdgPopup) void {
    std.log.debug("Unimplemented Server.handleNewXdgPopup\n", .{});
}

fn handleNewLayerSurface(listener: *wl.Listener(*wlr.LayerSurfaceV1), layer_surface: *wlr.LayerSurfaceV1) void {
    const self: *Server = @fieldParentPtr("new_layer_surface", listener);
    std.log.debug("requested layer shell\n", .{});
    if (layer_surface.output == null) {
        if (self.getDefaultSeat().focused_output == null) {
            std.log.err("No output available for new layer surface", .{});
            layer_surface.destroy();
            return;
        }

        layer_surface.output = self.getDefaultSeat().focused_output.?.wlr_output;
    }

    _ = LayerSurface.init(layer_surface);
}

fn handleRequestActivate(
    listener: *wl.Listener(*wlr.XdgActivationV1.event.RequestActivate),
    event: *wlr.XdgActivationV1.event.RequestActivate,
) void {
    const self: *Server = @fieldParentPtr("request_activate", listener);

    if (event.surface.data == null) return;
    const scene_node_data: *SceneNode.Data = @ptrCast(@alignCast(event.surface.data.?));

    if (scene_node_data.* == .view) {
        if (self.getDefaultSeat().focused_output) |output| {

            // If an enabled fullscreen view exists, ignore the activation
            if (output.getEnabledFullscreen()) |view| {
                self.getDefaultSeat().focusSurface(.{ .view = view });
                return;
            }
        }
        self.getDefaultSeat().focusSurface(.{ .view = scene_node_data.view });
    } else {
        std.log.warn("Ignoring request to activate non-view", .{});
    }
}

fn handleNewVirtualPointer(
    listener: *wl.Listener(*wlr.VirtualPointerManagerV1.event.NewPointer),
    event: *wlr.VirtualPointerManagerV1.event.NewPointer,
) void {
    const self: *Server = @fieldParentPtr("new_virtual_pointer", listener);
    handleNewInput(&self.new_input, &event.new_pointer.pointer.base);
}

fn handleNewVirtualKeyboard(
    listener: *wl.Listener(*wlr.VirtualKeyboardV1),
    event: *wlr.VirtualKeyboardV1,
) void {
    const self: *Server = @fieldParentPtr("new_virtual_keyboard", listener);
    handleNewInput(&self.new_input, &event.keyboard.base);
}

fn handleNewIdleInhibitor(
    _: *wl.Listener(*wlr.IdleInhibitorV1),
    inhibitor: *wlr.IdleInhibitorV1,
) void {
    _ = IdleInhibitor.init(inhibitor);
}

fn handleDrmRequest(
    _: *wl.Listener(*wlr.DrmLeaseRequestV1),
    request: *wlr.DrmLeaseRequestV1,
) void {
    const lease = request.grant();
    if (lease == null) {
        std.log.err("Failed to grant drm lease request.", .{});
        request.reject();
    }
}

fn handleNewPointerConstraint(
    _: *wl.Listener(*wlr.PointerConstraintV1),
    constraint: *wlr.PointerConstraintV1,
) void {
    _ = PointerConstraint.init(constraint);
}
