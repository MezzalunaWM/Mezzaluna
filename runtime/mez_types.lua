---@meta [mez]
mez = {}

mez.api = {}

---Spawn new application via the shell command. If you wish to pass in args
---to your command then you must use a table of strings.
---@param cmd []string|string Command to be run by a shell
mez.api.spawn = function(cmd) end

---Exit mezzaluna
mez.api.exit = function() end

---Change to a different virtual terminal
---@param vt_num integer virtual terminal number to switch to
mez.api.change_vt = function(vt_num) end

mez.fs = {}

---Join any number of paths into one path
---@param ... string Paths to join
---@return string?
mez.fs.joinpath = function(...) end

---List sub-directories given an abosolute parent path
---@param path string 
---@return string[] list of sub directories
mez.fs.subdirs = function(path) end

mez.hook = {}

---Create a new hook on an event
---@param events (string | string[])
---@param options { callback: fun(...), once: boolean? }
---@return number hook id
mez.hook.add = function(events, options) end

---Remove an existing hook
---@param id number
---@return boolean has it been deleted
mez.hook.del = function(id) end

mez.input = {}

---Create a new keymap
---@param modifiers string 
---@param keys string 
---@param options table { press: fun(), repeat: fun(), release: fun() }
mez.input.add_keymap = function(modifiers, keys, options) end

---@class Position
---@field x number
---@field y number

---@alias MousemapFunc fun(
--- view_id: integer,
--- pos: Position,
--- start: Position,
--- offset: Position): boolean?

---Create a new mousemap
---@param modifiers string 
---@param btn_name string button name (ex. "BTN_LEFT", "BTN_RIGHT")
---@param options { press: MousemapFunc?, drag: MousemapFunc?, release: MousemapFunc? }
mez.input.add_mousemap = function(modifiers, btn_name, options) end

---Remove an existing keymap
---@param modifiers string 
---@param keys string 
mez.input.del_keymap = function(modifiers, keys) end

---Remove an existing mousemap
---@param modifiers string 
---@param button string 
mez.input.del_mousemap = function(modifiers, button) end

---Get the repeat information
---@return integer[2]
mez.input.get_repeat_info = function() end

---Set the repeat information
---@param rate integer 
---@param delay integer 
mez.input.set_repeat_info = function(rate, delay) end

---Set the cursor type
---@param cursor string name
mez.input.set_cursor_type = function(cursor) end

mez.output = {}

---Get the ids for all available outputs
---@return integer[]
mez.output.get_all_ids = function() end

---Get the id for the focused output
---@return integer?
mez.output.get_focused_id = function() end

---Get refresh rate for the output
---@param output_id integer 0 maps to focused output
---@return integer?
mez.output.get_rate = function(output_id) end

---Get resolution in pixels of the output
---@param output_id integer 0 maps to focused output
---@return { width: integer, height: integer }?
mez.output.get_resolution = function(output_id) end

---Get the serial for the output
---@param output_id integer 0 maps to focused output
---@return string?
mez.output.get_serial = function(output_id) end

---Get the make for the output
---@param output_id integer 0 maps to focused output
---@return string?
mez.output.get_make = function(output_id) end

---Get the model for the output
---@param output_id integer 0 maps to focused output
---@return string?
mez.output.get_model = function(output_id) end

---Get the description for the output
---@param output_id integer 0 maps to focused output
---@return string?
mez.output.get_description = function(output_id) end

---Get the name of the output
---@param output_id integer 0 maps to focused output
---@return string 
mez.output.get_name = function(output_id) end

---@class box
---@field x integer
---@field y integer
---@field width integer
---@field height integer

---Get the space not exclusively occupied
---@param output_id output_id 0 maps to focused output
---@return box
mez.output.get_available_area = function(output_id) end

mez.remote = {}

mez.view = {}

---Get the id for the focused view
---@return integer?
mez.view.get_focused_id = function() end

---Close the view with view_id
---@param view_id integer 0 maps to focused view
mez.view.close = function(view_id) end

---position the view by it's top left corner
---@param view_id integer 0 maps to focused view
---@param x number x position for view
---@param y number y position for view
mez.view.set_position = function(view_id, x, y) end

---Get the position of the view
---@param view_id integer 0 maps to focused view
---@return { x: integer, y: integer }? Position of the view
mez.view.get_position = function(view_id) end

---Set the size of the spesified view. Will be resized relative to the view's top left corner.
---@param view_id integer 0 maps to focused view
---@param width integer
---@param height integer
mez.view.set_size = function(view_id, width, height) end

---Get the size of the view
---@param view_id integer 0 maps to focused view
---@return { width: integer, height: integer }? Size of the view
mez.view.get_size = function(view_id) end

---Remove focus from current view, and set to given id
---@param view_id integer Id of the view to be focused, or nil to remove focus
mez.view.set_focused = function(view_id) end

---Get the title of the view
---@param view_id integer 0 maps to focused view
---@return string?
mez.view.get_title = function(view_id) end

---Get the app_id of the view
---@param view_id integer 0 maps to focused view
---@return string?
mez.view.get_app_id = function(view_id) end

---Enable or disable a view
---@param view_id integer 0 maps to focused view
---@param enabled boolean
mez.view.set_enabled = function(view_id, enabled) end

---Check if a view is enabled
---@param view_id integer 0 maps to focused view
---@return boolean?
mez.view.get_enabled = function(view_id) end

---Set a view you intend to resize
---@param view_id integer 0 maps to focused view
---@param enable boolean
mez.view.set_resizing = function(view_id, enable) end

---Check if a view is resizing
---@param view_id integer 0 maps to focused view
---@return boolean? nil if view cannot be found
mez.view.get_resizing = function(view_id) end
