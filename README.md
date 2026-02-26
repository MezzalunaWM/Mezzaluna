# Mezzaluna

A utensil for chopping herbs, vegetables, or pizza, with a large, semicircular blade and handles at each end.

Mezzaluna is a Wayland compositor written in Zig, shouldering the complexities of compositor development, leaving configuration, windowing behavior and plugin extensibility to be expressed in easy to write, lovable Lua.

## Installation

As of now, we don't package or distribute ready made binaries whatsoever.

But **don't let that stop you from playing around**. You can really easily build `mez` for yourself, ensuring you have the following dependencies:
* Zig 0.15.x
* wlroots-0.19
* pixman
* xkbcommon

Clone The Repository
```
git clone https://github.com/MezzalunaWM/Mezzaluna
```

Build with Zig
```
zig build
```

Run the binary
```
./zig-out/bin/mez
```

## Configuration

### Default Config

As of now, we have a default configuration located at `./runtime/share/mezzaluna/init.lua` and the basics for a tiler plugin following [dwm's](https://dwm.suckless.org/) "master/stack" layout located at `./runtime/share/mezzaluna/master.lua`.

Additionally `mez` will also look in `$XDG_CONFIG/mez` for an `init.lua` to kickstart configuration

### Custom Config

Although a default configuration is provided, you are, of course, encouraged to get creative with how your desktop experience behaves! To add custom functionality and plugins, Mezzaluna has a similar Lua configuration API to [Neovim](https://neovim.io). 

#### Interacting with Windows

Windows in Mezzaluna are called "views", and you can interface with the properties of views using `mez.view`. Views also all have unique ids associated with them. Examples are the best way to see what this means to the user.

```lua
mez.view.get_all_ids() -- Returns a list containing all active view ids

mez.view.get_focused_id() -- Returns the id of the currently focused view

mez.view.get_position(1011980528) -- Return the position of a view as { x = 640 , y = 360 }

-- Here 0 as a view id indicates to mez to use the current focused view id
-- 0 can replace anywhere a normal id would typically be entered
mez.view.set_position(0, 100, 250) -- Set the position of a view to be (100, 250)
```

These are just the basics as of right now. More exists, but that will have to be for you to discover in the example config until some official documentation is developed for the Lua API.

#### Events

There are a lot of events that you can interact with and attach functions to within mez. They currently exist as keymaps, mousemaps and hooks.

Keymaps simply attach a keyboard to a set of functions for when the keybind is pressed, repeated, or released.

```lua
mez.input.add_keymap("alt|shift", "return", {
    press = function ()
        mez.api.spawn("alacritty")
    end
})
```

Mousemaps are for mouse interaction and can attach functions to keyboard modifiers and mouse buttons. The mousemap API provides callbacks for pressing, releasing and dragging, while providing those callbacks with extra information about the cursor. The following mousemap will move views underneath the cursor with the mouse, effectively dragging windows around the screen.

```lua
mez.input.add_mousemap("alt", "BTN_LEFT", {
    drag = function (pos, drag)
        if drag.view ~= nil then
            mez.view.set_position(drag.view.id, pos.x, pos.y)
        end
    end
})
```

Finally there are hooks which allow functions to be used as callbacks to important compositor events. We interact with hooks using `mez.hooks`, and are able to hook into events such as `ViewMapPre` which indicates that a new window is being put on the screen or `ViewUnmapPost`, indicating a view is being removed from the screen. Here we focus any newly created windows like so, and we see that hooks pass unique function args depending on what the event is related to.

```lua
mez.hook.add("ViewMapPre", {
    callback = function(view_id)
        mez.view.set_focused(view_id)
    end
})
```
