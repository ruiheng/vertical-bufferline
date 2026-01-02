-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/state.lua
-- Centralized state management for vertical-bufferline

local M = {}

local api = vim.api
local config_module = require('vertical-bufferline.config')

-- Private state object
local state = {
    win_id = nil,
    buf_id = nil,
    is_sidebar_open = false,
    last_width = nil, -- Remember the last width before closing sidebar
    last_height = nil, -- Remember the last height before closing sidebar (top/bottom)
    current_position = nil, -- Track current sidebar position ("left"/"right"/"top"/"bottom")
    line_to_buffer_id = {}, -- Maps a line number in our window to a buffer ID
    hint_to_buffer_id = {}, -- Maps a hint character to a buffer ID
    line_group_context = {}, -- Maps a line number to the group ID it belongs to
    line_buffer_ranges = {}, -- Maps a line to buffer ranges for hit testing
    group_header_lines = {}, -- Maps line numbers to group header information
    line_offset = 0, -- Cursor alignment offset for rendered lines
    was_picking = false, -- Track picking mode state to avoid spam
    session_loading = false, -- Flag to prevent interference during session loading
    highlight_timer = nil, -- Timer for picking highlights

    -- Extended picking mode state
    extended_picking = {
        is_active = false,
        pick_mode = nil,  -- "switch" or "close"
        line_hints = {},  -- line_number -> hint_char
        hint_lines = {},  -- hint_char -> line_number
        bufferline_hints = {}  -- existing bufferline hints for reference
    },

    -- Pin state (fallback when bufferline.nvim is not available)
    pinned_buffers = {},
    pinned_pick_chars = {},

    -- Horizontal overlay placeholder state
    placeholder_win_id = nil,
    placeholder_buf_id = nil,

    -- Layout mode: "vertical" (left/right) or "horizontal" (top/bottom)
    layout_mode = "vertical",
}

-- State validation functions
local function is_valid_win_id(win_id)
    return win_id and api.nvim_win_is_valid(win_id)
end

local function is_valid_buf_id(buf_id)
    return buf_id and api.nvim_buf_is_valid(buf_id)
end

-- Window management
function M.get_win_id()
    return state.win_id
end

function M.set_win_id(win_id)
    if win_id and not is_valid_win_id(win_id) then
        error("Invalid window ID: " .. tostring(win_id))
    end
    state.win_id = win_id
end

function M.get_placeholder_win_id()
    return state.placeholder_win_id
end

function M.set_placeholder_win_id(win_id)
    if win_id and not is_valid_win_id(win_id) then
        error("Invalid placeholder window ID: " .. tostring(win_id))
    end
    state.placeholder_win_id = win_id
end

function M.get_placeholder_buf_id()
    return state.placeholder_buf_id
end

function M.set_placeholder_buf_id(buf_id)
    if buf_id and not is_valid_buf_id(buf_id) then
        error("Invalid placeholder buffer ID: " .. tostring(buf_id))
    end
    state.placeholder_buf_id = buf_id
end

function M.is_valid_window()
    return is_valid_win_id(state.win_id)
end

-- Buffer management
function M.get_buf_id()
    return state.buf_id
end

function M.set_buf_id(buf_id)
    if buf_id and not is_valid_buf_id(buf_id) then
        error("Invalid buffer ID: " .. tostring(buf_id))
    end
    state.buf_id = buf_id
end

function M.is_valid_buffer()
    return is_valid_buf_id(state.buf_id)
end

-- Sidebar state management
function M.is_sidebar_open()
    -- Check if sidebar is marked as open AND the window still exists
    if not state.is_sidebar_open then
        return false
    end
    
    -- Verify the window still exists and is valid
    if not state.win_id or not api.nvim_win_is_valid(state.win_id) then
        -- Window was closed externally (e.g., by Ctrl-W o), update our state
        state.is_sidebar_open = false
        state.win_id = nil
        return false
    end
    
    return true
end

function M.set_sidebar_open(is_open)
    if type(is_open) ~= "boolean" then
        error("is_sidebar_open must be boolean, got: " .. type(is_open))
    end
    state.is_sidebar_open = is_open
end

function M.open_sidebar()
    state.is_sidebar_open = true
end

function M.close_sidebar()
    state.is_sidebar_open = false
    state.win_id = nil
    state.placeholder_win_id = nil
    state.placeholder_buf_id = nil
end

-- Last width management
function M.get_last_width()
    return state.last_width
end

function M.set_last_width(width)
    if width and (type(width) ~= "number" or width <= 0) then
        error("last_width must be a positive number, got: " .. tostring(width))
    end
    state.last_width = width
end

function M.get_last_height()
    return state.last_height
end

function M.set_last_height(height)
    if height and (type(height) ~= "number" or height <= 0) then
        error("last_height must be a positive number, got: " .. tostring(height))
    end
    state.last_height = height
end

function M.get_current_position()
    return state.current_position
end

function M.set_current_position(position)
    if position ~= nil and type(position) ~= "string" then
        error("current_position must be string or nil, got: " .. type(position))
    end
    state.current_position = position
end

-- Line to buffer mapping
function M.get_line_to_buffer_id()
    return state.line_to_buffer_id
end

function M.set_line_to_buffer_id(mapping)
    if type(mapping) ~= "table" then
        error("line_to_buffer_id must be table, got: " .. type(mapping))
    end
    state.line_to_buffer_id = mapping
end

function M.get_buffer_for_line(line_number)
    return state.line_to_buffer_id[line_number]
end

function M.clear_line_mapping()
    state.line_to_buffer_id = {}
end

-- Line buffer range mapping
function M.get_line_buffer_ranges()
    return state.line_buffer_ranges
end

function M.set_line_buffer_ranges(mapping)
    if type(mapping) ~= "table" then
        error("line_buffer_ranges must be table, got: " .. type(mapping))
    end
    state.line_buffer_ranges = mapping
end

function M.clear_line_buffer_ranges()
    state.line_buffer_ranges = {}
end

-- Hint to buffer mapping
function M.get_hint_to_buffer_id()
    return state.hint_to_buffer_id
end

function M.set_hint_to_buffer_id(mapping)
    if type(mapping) ~= "table" then
        error("hint_to_buffer_id must be table, got: " .. type(mapping))
    end
    state.hint_to_buffer_id = mapping
end

function M.clear_hint_mapping()
    state.hint_to_buffer_id = {}
end

-- Line group context mapping
function M.get_line_group_context()
    return state.line_group_context
end

function M.set_line_group_context(mapping)
    if type(mapping) ~= "table" then
        error("line_group_context must be table, got: " .. type(mapping))
    end
    state.line_group_context = mapping
end

function M.clear_line_group_context()
    state.line_group_context = {}
end

-- Group header lines management
function M.get_group_header_lines()
    return state.group_header_lines
end

function M.set_group_header_lines(group_headers)
    if type(group_headers) ~= "table" then
        error("group_header_lines must be table, got: " .. type(group_headers))
    end
    state.group_header_lines = group_headers
end

function M.clear_group_header_lines()
    state.group_header_lines = {}
end

-- Line offset management (for cursor alignment)
function M.get_line_offset()
    return state.line_offset or 0
end

function M.set_line_offset(offset)
    if type(offset) ~= "number" then
        error("line_offset must be number, got: " .. type(offset))
    end
    state.line_offset = offset
end

function M.get_layout_mode()
    return state.layout_mode
end

function M.set_layout_mode(mode)
    if mode ~= "vertical" and mode ~= "horizontal" then
        error("layout_mode must be 'vertical' or 'horizontal', got: " .. tostring(mode))
    end
    state.layout_mode = mode
end

-- Picking mode state
function M.was_picking()
    return state.was_picking
end

function M.set_was_picking(was_picking)
    if type(was_picking) ~= "boolean" then
        error("was_picking must be boolean, got: " .. type(was_picking))
    end
    state.was_picking = was_picking
end

-- Expand all groups mode

-- Session loading state
function M.is_session_loading()
    return state.session_loading
end

function M.set_session_loading(loading)
    if type(loading) ~= "boolean" then
        error("session_loading must be boolean, got: " .. type(loading))
    end
    state.session_loading = loading
end

-- Highlight timer management
function M.get_highlight_timer()
    return state.highlight_timer
end

function M.set_highlight_timer(timer)
    state.highlight_timer = timer
end

-- Pin state management (fallback when bufferline.nvim is unavailable)
function M.is_buffer_pinned(buf_id)
    return state.pinned_buffers[buf_id] == true
end

function M.set_buffer_pinned(buf_id, pinned)
    if pinned then
        state.pinned_buffers[buf_id] = true
    else
        state.pinned_buffers[buf_id] = nil
        state.pinned_pick_chars[buf_id] = nil
    end
end

function M.set_pinned_buffers(pinned_list)
    local new_pins = {}
    if type(pinned_list) ~= "table" then
        state.pinned_buffers = {}
        state.pinned_pick_chars = {}
        return
    end
    for _, buf_id in ipairs(pinned_list) do
        new_pins[buf_id] = true
    end
    state.pinned_buffers = new_pins
    for buf_id, _ in pairs(state.pinned_pick_chars) do
        if not new_pins[buf_id] then
            state.pinned_pick_chars[buf_id] = nil
        end
    end
end

function M.get_pinned_buffers()
    local result = {}
    for buf_id, pinned in pairs(state.pinned_buffers) do
        if pinned then
            table.insert(result, buf_id)
        end
    end
    return result
end

function M.clear_pinned_buffers()
    state.pinned_buffers = {}
    state.pinned_pick_chars = {}
end

function M.set_buffer_pin_char(buf_id, pick_char)
    if pick_char == nil or pick_char == "" then
        state.pinned_pick_chars[buf_id] = nil
        return
    end
    state.pinned_pick_chars[buf_id] = pick_char
end

function M.get_buffer_pin_char(buf_id)
    return state.pinned_pick_chars[buf_id]
end

function M.get_pinned_pick_chars()
    return state.pinned_pick_chars
end

function M.stop_highlight_timer()
    if state.highlight_timer then
        if not state.highlight_timer:is_closing() then
            state.highlight_timer:stop()
            state.highlight_timer:close()
        end
        state.highlight_timer = nil
    end
end

function M.has_highlight_timer()
    return state.highlight_timer ~= nil
end

-- Extended picking mode state management
function M.get_extended_picking_state()
    return state.extended_picking
end

function M.set_extended_picking_active(is_active)
    state.extended_picking.is_active = is_active
    if not is_active then
        -- Clear state when deactivating
        state.extended_picking.pick_mode = nil
        state.extended_picking.line_hints = {}
        state.extended_picking.hint_lines = {}
        state.extended_picking.bufferline_hints = {}
    end
end

function M.set_extended_picking_mode(pick_mode)
    state.extended_picking.pick_mode = pick_mode
end

function M.set_extended_picking_hints(line_hints, hint_lines, bufferline_hints)
    state.extended_picking.line_hints = line_hints or {}
    state.extended_picking.hint_lines = hint_lines or {}
    state.extended_picking.bufferline_hints = bufferline_hints or {}
end

-- Composite state checks
function M.is_ready_for_refresh()
    return state.is_sidebar_open and is_valid_win_id(state.win_id) and is_valid_buf_id(state.buf_id)
end

function M.is_picking_mode_active()
    return state.was_picking and state.highlight_timer ~= nil
end

-- State reset and cleanup
function M.reset_state()
    M.stop_highlight_timer()
    state.win_id = nil
    state.buf_id = nil
    state.is_sidebar_open = false
    state.last_width = nil
    state.last_height = nil
    state.current_position = nil
    state.line_to_buffer_id = {}
    state.hint_to_buffer_id = {}
    state.line_buffer_ranges = {}
    state.was_picking = false
    state.session_loading = false
    state.layout_mode = "vertical"
end

function M.cleanup_invalid_state()
    -- Clean up invalid window references
    if state.win_id and not is_valid_win_id(state.win_id) then
        state.win_id = nil
        state.is_sidebar_open = false
    end

    -- Clean up invalid buffer references
    if state.buf_id and not is_valid_buf_id(state.buf_id) then
        state.buf_id = nil
    end

    -- Clean up invalid line mappings
    local valid_mapping = {}
    for line, buf_id in pairs(state.line_to_buffer_id) do
        if is_valid_buf_id(buf_id) then
            valid_mapping[line] = buf_id
        end
    end
    state.line_to_buffer_id = valid_mapping

    -- Clean up invalid range mappings
    local valid_ranges = {}
    for line, ranges in pairs(state.line_buffer_ranges) do
        if type(ranges) == "table" then
            local valid_line_ranges = {}
            for _, range in ipairs(ranges) do
                if range and (is_valid_buf_id(range.buffer_id) or range.is_group_entry) then
                    table.insert(valid_line_ranges, range)
                end
            end
            if #valid_line_ranges > 0 then
                valid_ranges[line] = valid_line_ranges
            end
        end
    end
    state.line_buffer_ranges = valid_ranges
end

-- Debug and introspection
function M.get_state_summary()
    return {
        win_id = state.win_id,
        buf_id = state.buf_id,
        is_sidebar_open = state.is_sidebar_open,
        last_width = state.last_width,
        was_picking = state.was_picking,
        session_loading = state.session_loading,
        has_highlight_timer = state.highlight_timer ~= nil,
        line_mappings_count = vim.tbl_count(state.line_to_buffer_id),
        hint_mappings_count = vim.tbl_count(state.hint_to_buffer_id),
        is_valid_window = is_valid_win_id(state.win_id),
        is_valid_buffer = is_valid_buf_id(state.buf_id),
    }
end

-- Export direct state access for backwards compatibility (use sparingly)
function M.get_raw_state()
    return state
end

return M
