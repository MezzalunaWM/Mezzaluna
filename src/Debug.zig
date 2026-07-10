const Debug = @This();

const std = @import("std");
const wlr = @import("wlroots");

const server = &@import("main.zig").server;
const gpa = std.heap.c_allocator;

const Utils = @import("Utils.zig");
const SceneNode = @import("SceneNode.zig");

pub fn debugPrintSceneTree(root: *wlr.SceneNode) void {
    std.log.debug("=== SCENE TREE DEBUG ===", .{});
    printNode(root, 0);
    std.log.debug("=== END SCENE TREE ===", .{});
}

fn printNode(node: *wlr.SceneNode, depth: usize) void {
    errdefer Utils.oomPanic();

    var buffer: std.ArrayList(u8) = try .initCapacity(gpa, 512);
    defer buffer.deinit(gpa);
    const writer = buffer.writer(gpa);

    // Add indentation
    for (0..depth) |_| {
        writer.writeAll("     ") catch unreachable;
    }

    // Print node type and position
    const type_name = switch (node.type) {
        .tree => "TREE",
        .rect => "RECT",
        .buffer => "BUFFER",
    };

    writer.print("{s} @ ({d}, {d}) enabled={}", .{ type_name, node.x, node.y, node.enabled }) catch unreachable;

    var stop_recurse: bool = false;

    // Add associated data if present
    const snd: *SceneNode.Data = .fromSceneNode(node);
    switch (snd.*) {
        .root => {
            writer.print(" → Root Scene Tree", .{}) catch unreachable;
        },
        .hidden_tree => {
            writer.print(" → Hidden tree", .{}) catch unreachable;
        },
        .output => |output| {
            writer.print(" → Output: {s} (focused={}, id={})", .{
                output.wlr_output.name,
                output.focused,
                output.id,
            }) catch unreachable;
        },
        .output_layer => {
            writer.print(" → Output Layer", .{}) catch unreachable;
        },
        .view => |view| {
            writer.print(" → View: id={} mapped={}", .{
                view.id,
                view.xdg_toplevel.base.surface.mapped
            }) catch unreachable;
            if (view.xdg_toplevel.title) |title| {
                writer.print(" title=\"{s}\"", .{title}) catch unreachable;
            }
            stop_recurse = true;
        },
        .view_border => {
            writer.print(" → View border" , .{}) catch unreachable;
        },
        .view_surface_tree => {
            writer.print(" → View surface tree", .{}) catch unreachable;
        },
        .view_saved_tree => {
            writer.print(" → View saved tree", .{}) catch unreachable;
        },
        .view_surface => {
            writer.print(" → View surface", .{}) catch unreachable;
        },
        .layer_surface => |layer| {
            const layer_name = switch (layer.wlr_layer_surface.current.layer) {
                .background => "background",
                .bottom => "bottom",
                .top => "top",
                .overlay => "overlay",
                else => "unknown",
            };
            writer.print(" → LayerSurface: layer={s} mapped={}", .{
                layer_name,
                layer.wlr_layer_surface.surface.mapped,
            }) catch unreachable;
            const namespace = std.mem.span(layer.wlr_layer_surface.namespace);
            if (namespace.len > 0) {
                writer.print(" namespace=\"{s}\"", .{namespace}) catch unreachable;
            }
        },
    }

    // Add buffer-specific info
    if (node.type == .buffer) {
        const scene_buffer = wlr.SceneBuffer.fromNode(node);
        writer.print(" buffer: {d}x{d}", .{
            if (scene_buffer.buffer == null) -1 else scene_buffer.buffer.?.width,
            if (scene_buffer.buffer == null) -1 else scene_buffer.buffer.?.height,
        }) catch unreachable;

        // Check if it's a surface
        if (wlr.SceneSurface.tryFromBuffer(scene_buffer)) |scene_surface| {
            writer.print(" → Surface: {*}", .{scene_surface.surface}) catch unreachable;
        }
    }

    // Print the complete line
    std.log.debug("{s}", .{buffer.items});

    if(stop_recurse) {
        writer.print("Recurse stopped prematurely\n", .{}) catch unreachable;
        return;
    }

    // Recursively print children if this is a tree
    if (node.type == .tree) {
        const tree = wlr.SceneTree.fromNode(node);
        var it = tree.children.iterator(.forward);
        var child_count: usize = 0;
        while (it.next()) |child| {
            child_count += 1;
            printNode(child, depth + 1);
        }
        if (child_count == 0) {
            var empty_buffer: std.ArrayList(u8) = try .initCapacity(gpa, 512);
            defer empty_buffer.deinit(gpa);
            for (0..depth) |_| {
                empty_buffer.writer(gpa).writeAll("\t") catch unreachable;
            }
            empty_buffer.writer(gpa).writeAll("     (no children)") catch unreachable;
            std.log.debug("{s}", .{empty_buffer.items});
        }
    }
}
