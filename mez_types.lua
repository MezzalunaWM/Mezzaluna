---@meta [mez]
mez = {}

mez.api = {}

---Spawn new application via the shell command
---@param cmd string Command to be run by a shell
mez.api.spawn = function() end

---Exit mezzaluna
mez.api.exit = function() end

---Change to a different virtual terminal
---@param vt_num integer virtual terminal number to switch to
mez.api.change_vt = function() end

--- Print the scene tree for debugging
mez.api.print_scene = function() end

mez.bridge = {}

mez.bridge.getNestedField = function() end

mez.fs = {}

---Join any number of paths into one path
---@vararg string paths to join
---@return string?
mez.fs.joinpath = function() end

mez.hook = {}

---Create a new hook on an event
---@param events string|string[]
---@param options table
---@return number id
mez.hook.add = function() end

---Create an existing hook
---@param id number
---@return boolean has it been deleted
mez.hook.del = function() end

mez.input = {}

---Create a new keymap
---@param string modifiers
---@param string keys
---@param table options
mez.input.add_keymap = function() end

---Create a new mousemap
---@param string modifiers
---@param string libevdev button name (ex. "BTN_LEFT", "BTN_RIGHT")
---@param table options
mez.input.add_mousemap = function() end

---Remove an existing keymap
---@param string modifiers
---@param string keys
mez.input.del_keymap = function() end

---Remove an existing mousemap
---@param string modifiers
---@param string button
mez.input.del_mousemap = function() end

---Get the repeat information
---@return integer[2]
mez.input.get_repeat_info = function() end

---Set the repeat information
---@param integer rate
---@param integer delay
mez.input.set_repeat_info = function() end

---Set the cursor type
---@param string cursor name
mez.input.set_cursor_type = function() end

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
mez.output.get_rate = function() end

---Get resolution in pixels of the output
---@param output_id integer 0 maps to focused output
---@return { width: integer, height: integer }?
mez.output.get_resolution = function() end

---Get the serial for the output
---@param output_id integer 0 maps to focused output
---@return string?
mez.output.get_serial = function() end

---Get the make for the output
---@param output_id integer 0 maps to focused output
---@return string?
mez.output.get_make = function() end

---Get the model for the output
---@param output_id integer 0 maps to focused output
---@return stirng?
mez.output.get_model = function() end

---Get the description for the output
---@param output_id integer 0 maps to focused output
---@return stirng?
mez.output.get_description = function() end

---Get the name of the output
---@param output_id integer 0 maps to focused output
---@return stirng
mez.output.get_name = function() end

mez.remote = {}

mez.remote.print = function() end

mez.view = {}

---Get the ids for all available views
---@return integer[]?
mez.view.get_all_ids = function() end

mez.view.check = function() end

---Get the id for the focused view
---@return integer?
mez.view.get_focused_id = function() end

---Close the view with view_id
---@param view_id integer 0 maps to focused view
mez.view.close = function() end

---position the view by it's top left corner
---@param view_id integer 0 maps to focused view
---@param x number x position for view
---@param y number y position for view
mez.view.set_position = function() end

---Get the position of the view
---@param view_id integer 0 maps to focused view
---@return { x: integer, y: integer }? Position of the view
mez.view.get_position = function() end

---Set the size of the spesified view. Will be resized relative to the view's top left corner.
---@param view_id integer 0 maps to focused view
mez.view.set_size = function() end

---Get the size of the view
---@param view_id integer 0 maps to focused view
---@return { width: integer, height: integer }? Size of the view
mez.view.get_size = function() end

---Remove focus from current view, and set to given id
---@param view_id integer Id of the view to be focused, or nil to remove focus
mez.view.set_focused = function() end

---Resize the view by it's top left corner
---@param view_id integer 0 maps to focused view
mez.view.toggle_fullscreen = function() end

---Get the title of the view
---@param view_id integer 0 maps to focused view
---@return string?
mez.view.get_title = function() end

---Get the app_id of the view
---@param view_id integer 0 maps to focused view
---@return string?
mez.view.get_app_id = function() end

---Enable or disable a view
---@param view_id integer 0 maps to focused view
---@param enabled boolean
mez.view.set_enabled = function() end

---Check if a view is enabled
---@param view_id integer 0 maps to focused view
---@return boolean?
mez.view.get_enabled = function() end

---Set a view you intend to resize
---@param view_id integer 0 maps to focused view
---@param enable boolean
mez.view.set_resizing = function() end

---Check if a view is resizing
---@param view_id integer 0 maps to focused view
---@return boolean? nil if view cannot be found
mez.view.get_resizing = function() end

mez.view.setWmCapabilities = function() end
