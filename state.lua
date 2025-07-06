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
    line_to_buffer_id = {}, -- Maps a line number in our window to a buffer ID
    hint_to_buffer_id = {}, -- Maps a hint character to a buffer ID
    was_picking = false, -- Track picking mode state to avoid spam
    expand_all_groups = true, -- Default mode: show all groups expanded
    session_loading = false, -- Flag to prevent interference during session loading
    highlight_timer = nil, -- Timer for picking highlights
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
    return state.is_sidebar_open
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
function M.get_expand_all_groups()
    return state.expand_all_groups
end

function M.set_expand_all_groups(expand_all)
    if type(expand_all) ~= "boolean" then
        error("expand_all_groups must be boolean, got: " .. type(expand_all))
    end
    state.expand_all_groups = expand_all
end

function M.toggle_expand_all_groups()
    state.expand_all_groups = not state.expand_all_groups
    return state.expand_all_groups
end

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
    state.line_to_buffer_id = {}
    state.hint_to_buffer_id = {}
    state.was_picking = false
    state.session_loading = false
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
end

-- Debug and introspection
function M.get_state_summary()
    return {
        win_id = state.win_id,
        buf_id = state.buf_id,
        is_sidebar_open = state.is_sidebar_open,
        expand_all_groups = state.expand_all_groups,
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