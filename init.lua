-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/init.lua

-- Anti-reload protection
if _G._vertical_bufferline_init_loaded then
    return _G._vertical_bufferline_init_instance
end

local M = {}

local api = vim.api

-- Configuration and constants
local config_module = require('vertical-bufferline.config')

-- State management
local state_module = require('vertical-bufferline.state')

-- Group management modules
local groups = require('vertical-bufferline.groups')
local commands = require('vertical-bufferline.commands')
local bufferline_integration = require('vertical-bufferline.bufferline-integration')
local session = require('vertical-bufferline.session')
local filename_utils = require('vertical-bufferline.filename_utils')

-- Namespace for our highlights
local ns_id = api.nvim_create_namespace("VerticalBufferline")

-- Extended picking mode state
local extended_picking_state = {
    active = false,
    mode_type = nil, -- "switch" or "close"
    extended_hints = {}, -- line_num -> hint_char mapping
    bufferline_used_chars = {},
    original_commands = {} -- Store original commands for restoration
}

-- Setup highlight groups function
local function setup_highlights()
    -- Buffer state highlights using semantic nvim highlight groups for theme compatibility
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.CURRENT, { link = "CursorLine", bold = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.VISIBLE, { link = "PmenuSel" })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.INACTIVE, { link = "Comment" })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.MODIFIED, { link = "WarningMsg", italic = true })
    
    -- Path highlights - should be subtle and low-key
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PATH, { link = "Comment", italic = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PATH_CURRENT, { link = "NonText", italic = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PATH_VISIBLE, { link = "Comment", italic = true })
    
    -- Prefix highlights - for minimal prefixes, should be consistent
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PREFIX, { link = "Comment", italic = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PREFIX_CURRENT, { link = "Directory", bold = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PREFIX_VISIBLE, { link = "String", italic = true })
    
    -- Filename highlights - should be consistent between prefixed and non-prefixed
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.FILENAME, { link = "Normal" })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.FILENAME_CURRENT, { link = "Title", bold = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.FILENAME_VISIBLE, { link = "String", bold = true })
    
    -- Dual numbering highlights - different styles for easy distinction
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.NUMBER_LOCAL, { link = "Number", bold = true })      -- Local: bright, bold
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.NUMBER_GLOBAL, { link = "Comment" })                -- Global: subdued
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.NUMBER_SEPARATOR, { link = "Operator" })            -- Separator: distinct
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.NUMBER_HIDDEN, { link = "NonText" })                -- Hidden: very subtle
    
    -- Group header highlights - use semantic colors for theme compatibility
    -- Get background from PmenuSel/Pmenu but foreground/style from Title/Comment
    local pmenusel_attrs = vim.api.nvim_get_hl(0, {name = 'PmenuSel'})
    local pmenu_attrs = vim.api.nvim_get_hl(0, {name = 'Pmenu'})
    local title_attrs = vim.api.nvim_get_hl(0, {name = 'Title'})
    local comment_attrs = vim.api.nvim_get_hl(0, {name = 'Comment'})
    
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_ACTIVE, { 
        bg = pmenusel_attrs.bg,
        fg = title_attrs.fg or pmenusel_attrs.fg,
        bold = title_attrs.bold,
        italic = title_attrs.italic
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_INACTIVE, { 
        bg = pmenu_attrs.bg,
        fg = comment_attrs.fg or pmenu_attrs.fg,
        italic = comment_attrs.italic
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_NUMBER, { link = "Number", bold = true, default = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_SEPARATOR, { link = "Comment", default = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_MARKER, { link = "Special", bold = true, default = true })
end

-- Call setup function immediately
setup_highlights()
api.nvim_set_hl(0, config_module.HIGHLIGHTS.ERROR, { fg = config_module.COLORS.RED, default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.WARNING, { fg = config_module.COLORS.YELLOW, default = true })

-- Auto-refresh highlights when colorscheme changes
vim.api.nvim_create_autocmd("ColorScheme", {
    pattern = "*",
    callback = function()
        setup_highlights()
    end,
    desc = "Refresh vertical-bufferline highlights on colorscheme change"
})

-- Auto-refresh when buffer modification state changes
vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI", "BufWritePost"}, {
    pattern = "*",
    callback = function()
        local state_module = require('vertical-bufferline.state')
        if state_module.is_sidebar_open() then
            -- Use a timer to avoid too frequent updates
            if vim.g.vertical_bufferline_update_timer then
                vim.fn.timer_stop(vim.g.vertical_bufferline_update_timer)
            end
            vim.g.vertical_bufferline_update_timer = vim.fn.timer_start(100, function()
                local vertical_bufferline = require('vertical-bufferline')
                if vertical_bufferline and vertical_bufferline.refresh then
                    vertical_bufferline.refresh()
                end
            end)
        end
    end,
    desc = "Refresh vertical-bufferline when buffer content changes"
})


-- Extended picking mode utilities
local function get_bufferline_used_characters()
    local used_chars = {}
    local bufferline_state = require('bufferline.state')
    
    if bufferline_state.components then
        for _, component in ipairs(bufferline_state.components) do
            local ok, element = pcall(function() return component:as_element() end)
            local letter = nil
            if ok and element and element.letter then
                letter = element.letter
            elseif component.letter then
                letter = component.letter
            end
            
            if letter then
                used_chars[letter] = true
            end
        end
    end
    
    return used_chars
end

-- Enhanced buffer modification detection
local function is_buffer_actually_modified(buf_id)
    if not api.nvim_buf_is_valid(buf_id) then
        return false
    end
    
    -- Check basic modified flag first
    local basic_modified = api.nvim_buf_get_option(buf_id, "modified")
    
    -- For more accurate detection, also check changedtick
    local current_changedtick = api.nvim_buf_get_changedtick(buf_id)
    
    -- Store previous changedtick values to detect actual changes
    if not vim.g.vertical_bufferline_changedticks then
        vim.g.vertical_bufferline_changedticks = {}
    end
    
    local stored_tick = vim.g.vertical_bufferline_changedticks[buf_id]
    
    -- If this is the first time we see this buffer, store its tick and use basic modified
    if not stored_tick then
        vim.g.vertical_bufferline_changedticks[buf_id] = current_changedtick
        return basic_modified
    end
    
    -- If changedtick hasn't changed, trust the basic modified flag
    if current_changedtick == stored_tick then
        return basic_modified
    end
    
    -- If changedtick changed, update stored tick and check for real modification
    vim.g.vertical_bufferline_changedticks[buf_id] = current_changedtick
    
    -- Use a combination of checks for accuracy
    local buf_modified = api.nvim_buf_get_option(buf_id, "modified")
    local buf_readonly = api.nvim_buf_get_option(buf_id, "readonly")
    local buf_modifiable = api.nvim_buf_get_option(buf_id, "modifiable")
    
    -- Don't show modified for readonly or non-modifiable buffers
    if buf_readonly or not buf_modifiable then
        return false
    end
    
    return buf_modified
end

-- Extended picking mode implementation
local PICK_ALPHABET = "asdfjkl;ghqwertyuiopzxcvbnm1234567890ASDFJKL;GHQWERTYUIOPZXCVBNM"

-- Generate multi-character hint for overflow cases
local function generate_multi_char_hint(overflow_index)
    -- Use two-character combinations: aa, ab, ac, ..., ba, bb, bc, ...
    local base_chars = "asdfjklghq"  -- Use first 10 chars as base for multi-char hints
    local base = #base_chars
    local first_char_index = math.floor((overflow_index - 1) / base) + 1
    local second_char_index = ((overflow_index - 1) % base) + 1
    
    local first_char = base_chars:sub(first_char_index, first_char_index)
    local second_char = base_chars:sub(second_char_index, second_char_index)
    
    return first_char .. second_char
end

-- Generate extended hints for all sidebar buffers
local function generate_extended_hints(bufferline_components, line_to_buffer, line_group_context, active_group_id)
    local line_hints = {}
    local hint_lines = {}
    local bufferline_hints = {}
    
    -- Extract existing bufferline hints
    local used_chars = {}
    for _, component in ipairs(bufferline_components or {}) do
        local ok, element = pcall(function() return component:as_element() end)
        local letter = nil
        if ok and element and element.letter then
            letter = element.letter
        elseif component.letter then
            letter = component.letter
        end
        
        if letter then
            used_chars[letter] = true
            bufferline_hints[component.id] = letter
        end
    end
    
    -- Generate available character pool
    local available_chars = {}
    for i = 1, #PICK_ALPHABET do
        local char = PICK_ALPHABET:sub(i, i)
        if not used_chars[char] then
            table.insert(available_chars, char)
        end
    end
    
    -- Assign hints to non-active group lines with deterministic ordering
    local char_index = 1
    
    -- Create sorted list of line numbers for deterministic ordering
    local sorted_lines = {}
    for line_num, buffer_id in pairs(line_to_buffer) do
        local line_group_id = line_group_context[line_num]
        if line_group_id ~= active_group_id then
            table.insert(sorted_lines, line_num)
        end
    end
    table.sort(sorted_lines)
    
    -- Assign hints in deterministic order
    for _, line_num in ipairs(sorted_lines) do
        if char_index <= #available_chars then
            local hint_char = available_chars[char_index]
            line_hints[line_num] = hint_char
            hint_lines[hint_char] = line_num
            char_index = char_index + 1
        else
            -- Handle overflow: assign multi-character hints
            local multi_char_hint = generate_multi_char_hint(char_index - #available_chars)
            if not used_chars[multi_char_hint] and not hint_lines[multi_char_hint] then
                line_hints[line_num] = multi_char_hint
                hint_lines[multi_char_hint] = line_num
                used_chars[multi_char_hint] = true
            end
            char_index = char_index + 1
        end
    end
    
    return line_hints, hint_lines, bufferline_hints
end

-- Extended picking mode management
local function start_extended_picking(mode_type)
    extended_picking_state.active = true
    extended_picking_state.mode_type = mode_type
    
    -- Generate hints directly instead of relying on refresh timing
    if state_module.is_sidebar_open() then
        -- Get current bufferline components and state
        local bufferline_state = require('bufferline.state')
        local components = bufferline_state.components or {}
        
        local active_group = groups.get_active_group()
        local active_group_id = active_group and active_group.id or nil
        local line_to_buffer = state_module.get_line_to_buffer_id()
        local line_group_context = state_module.get_line_group_context()
        
        -- Generate hints directly
        local line_hints, hint_lines, bufferline_hints = generate_extended_hints(
            components, line_to_buffer, line_group_context, active_group_id
        )
        
        -- Store hints in both state systems
        state_module.set_extended_picking_active(true)
        state_module.set_extended_picking_mode(mode_type)
        state_module.set_extended_picking_hints(line_hints, hint_lines, bufferline_hints)
        extended_picking_state.extended_hints = line_hints
    end
    
    -- Apply extended picking highlights immediately
    vim.schedule(function()
        M.apply_extended_picking_highlights()
    end)
end

local function exit_extended_picking()
    extended_picking_state.active = false
    extended_picking_state.mode_type = nil
    extended_picking_state.extended_hints = {}
    extended_picking_state.bufferline_used_chars = {}
    
    -- Deactivate extended picking in state module
    state_module.set_extended_picking_active(false)
end

local function find_line_by_hint(hint_char)
    for line_num, char in pairs(extended_picking_state.extended_hints) do
        if char == hint_char then
            return line_num
        end
    end
    return nil
end

-- Cross-group buffer actions
local function switch_to_buffer_and_group(buffer_id, target_group_id)
    -- Save current state
    groups.save_current_buffer_state()
    
    -- Switch to target group first
    groups.set_active_group(target_group_id)
    
    -- Then switch to buffer
    vim.schedule(function()
        api.nvim_set_current_buf(buffer_id)
        -- Restore buffer state in new group context
        groups.restore_buffer_state_for_current_group(buffer_id)
    end)
end

local function close_buffer_from_group(buffer_id, group_id)
    -- Remove buffer from the specific group only
    groups.remove_buffer_from_group(buffer_id, group_id)
    
    -- Check if buffer exists in other groups
    local all_groups_with_buffer = groups.find_buffer_groups(buffer_id)
    if #all_groups_with_buffer <= 1 then
        -- This was the only group with this buffer, actually close the buffer
        pcall(vim.cmd, "bd " .. buffer_id)
    end
    
    -- Refresh the display
    vim.schedule(function()
        M.refresh("buffer_close")
    end)
end

-- Key handling for extended picking
local function handle_extended_picking_key(key)
    if not extended_picking_state.active then
        return false
    end
    
    -- First check if this key belongs to bufferline's hints (current group)
    local extended_picking = state_module.get_extended_picking_state()
    if extended_picking.bufferline_hints then
        for buffer_id, hint_char in pairs(extended_picking.bufferline_hints) do
            if hint_char == key then
                -- This is a bufferline hint, let bufferline handle it
                return false
            end
        end
    end
    
    -- Check if this key is for our extended hints (cross-group)
    local line_num = find_line_by_hint(key)
    if not line_num then
        return false  -- Not our key either, let bufferline handle it
    end
    
    local buffer_id = state_module.get_buffer_for_line(line_num)
    if not buffer_id or not api.nvim_buf_is_valid(buffer_id) then
        return false
    end
    
    local line_group_context = state_module.get_line_group_context()
    local target_group_id = line_group_context[line_num]
    if not target_group_id then
        return false
    end
    
    -- Perform the action based on mode type
    if extended_picking_state.mode_type == "switch" then
        switch_to_buffer_and_group(buffer_id, target_group_id)
    elseif extended_picking_state.mode_type == "close" then
        close_buffer_from_group(buffer_id, target_group_id)
    end
    
    -- Exit picking mode
    exit_extended_picking()
    return true
end

local function setup_extended_picking_hooks()
    -- Hook into bufferline's pick module directly
    vim.defer_fn(function()
        local ok, pick_module = pcall(require, 'bufferline.pick')
        if not ok or not pick_module then
            return
        end
        
        -- Hook the choose_then function
        if pick_module.choose_then then
            local original_choose_then = pick_module.choose_then
            pick_module.choose_then = function(func)
                start_extended_picking("switch")
                
                -- Use our own implementation instead of intercepting getchar
                local bufferline_state = require('bufferline.state')
                local ui = require('bufferline.ui')
                local fn = vim.fn
                
                bufferline_state.is_picking = true
                ui.refresh()
                
                local char = fn.getchar()
                
                if char then
                    local letter = fn.nr2char(char)
                    
                    -- Check if this is one of our extended keys first
                    if handle_extended_picking_key(letter) then
                        bufferline_state.is_picking = false
                        ui.refresh()
                        exit_extended_picking()
                        return
                    end
                    
                    -- Otherwise, let bufferline handle it
                    for _, item in ipairs(bufferline_state.components) do
                        local element = item:as_element()
                        if element and letter == element.letter then 
                            func(element.id)
                            break
                        end
                    end
                end
                
                bufferline_state.is_picking = false
                ui.refresh()
                exit_extended_picking()
            end
        end
    end, 100)
end

local function apply_extended_picking_highlights()
    -- This function is no longer needed since hints are already embedded during line creation
    -- Just let the normal highlight system handle it
    return
end


-- Pick highlights matching bufferline's style
-- Copy the exact colors from BufferLine groups
local function setup_pick_highlights()
    -- Get the actual BufferLine highlight groups
    local bufferline_pick = vim.api.nvim_get_hl(0, {name = "BufferLinePick"})
    local bufferline_pick_visible = vim.api.nvim_get_hl(0, {name = "BufferLinePickVisible"})
    local bufferline_pick_selected = vim.api.nvim_get_hl(0, {name = "BufferLinePickSelected"})

    -- Set our highlights to match exactly
    if next(bufferline_pick) then
        api.nvim_set_hl(0, config_module.HIGHLIGHTS.PICK, bufferline_pick)
    else
        api.nvim_set_hl(0, config_module.HIGHLIGHTS.PICK, { fg = config_module.COLORS.RED, bold = true, italic = true })
    end

    if next(bufferline_pick_visible) then
        api.nvim_set_hl(0, config_module.HIGHLIGHTS.PICK_VISIBLE, bufferline_pick_visible)
    else
        api.nvim_set_hl(0, config_module.HIGHLIGHTS.PICK_VISIBLE, { fg = config_module.COLORS.RED, bold = true, italic = true })
    end

    if next(bufferline_pick_selected) then
        api.nvim_set_hl(0, config_module.HIGHLIGHTS.PICK_SELECTED, bufferline_pick_selected)
    else
        api.nvim_set_hl(0, config_module.HIGHLIGHTS.PICK_SELECTED, { fg = config_module.COLORS.RED, bold = true, italic = true })
    end
end

-- Set up highlights initially
setup_pick_highlights()

-- Configuration is now managed through config_module.DEFAULTS

-- Check if buffer is special (based on buftype)
local function is_special_buffer(buf_id)
    if not api.nvim_buf_is_valid(buf_id) then
        return true -- Invalid buffers are also considered special
    end
    local buftype = api.nvim_buf_get_option(buf_id, 'buftype')
    return buftype ~= config_module.SYSTEM.EMPTY_BUFTYPE -- Non-empty means special buffer (nofile, quickfix, help, terminal, etc.)
end

-- State is now managed by the state_module, no direct state object needed

-- Helper function to get the current buffer from main window, not sidebar
local function get_main_window_current_buffer()
    for _, win_id in ipairs(api.nvim_list_wins()) do
        if win_id ~= state_module.get_win_id() and api.nvim_win_is_valid(win_id) then
            -- Check if this window is not a floating window
            local win_config = api.nvim_win_get_config(win_id)
            if win_config.relative == "" then  -- Not a floating window
                return api.nvim_win_get_buf(win_id)
            end
        end
    end

    -- Fallback to global current buffer if no main window found
    return api.nvim_get_current_buf()
end

-- Validate and initialize refresh state
local function validate_and_initialize_refresh()
    if not state_module.is_sidebar_open() or not api.nvim_win_is_valid(state_module.get_win_id()) then
        return nil
    end

    local bufferline_state = require('bufferline.state')
    if not bufferline_state or not bufferline_state.components then
        return nil
    end

    -- Ensure buf_id is valid
    if not state_module.get_buf_id() or not api.nvim_buf_is_valid(state_module.get_buf_id()) then
        return nil
    end

    local components = bufferline_state.components
    local current_buffer_id = get_main_window_current_buffer()

    -- Filter out invalid components and special buffers
    local valid_components = {}
    for _, comp in ipairs(components) do
        if comp.id and api.nvim_buf_is_valid(comp.id) and not is_special_buffer(comp.id) then
            table.insert(valid_components, comp)
        end
    end

    -- Get group information
    local group_info = bufferline_integration.get_group_buffer_info()
    local active_group = groups.get_active_group()

    return {
        bufferline_state = bufferline_state,
        components = valid_components,
        current_buffer_id = current_buffer_id,
        group_info = group_info,
        active_group = active_group
    }
end
-- Detect pick mode type from bufferline state
local function detect_pick_mode()
    local bufferline_state = require('bufferline.state')
    
    if not bufferline_state.is_picking then
        return nil
    end
    
    -- Try to detect the picking mode by analyzing the call stack
    local info = debug.getinfo(4, "n")
    if info and info.name then
        if info.name:find("close") then
            return "close"
        end
    end
    
    -- Default to switch mode
    return "switch"
end

-- Detect picking mode and manage picking state and timers
local function detect_and_manage_picking_mode(bufferline_state, components)
    local is_picking = false

    -- Try different ways to detect picking mode
    if bufferline_state.is_picking then
        is_picking = true
    end

    -- Check if any component has picking-related text
    for _, comp in ipairs(components) do
        if comp.text and comp.text:match("^%w") and #comp.text == 1 then
            is_picking = true
            break
        end
    end

    -- Detect picking mode state changes
    if is_picking and not state_module.was_picking() then
        state_module.set_was_picking(true)

        -- Stop existing timer if any
        state_module.stop_highlight_timer()
        
        -- Generate extended hints for all sidebar buffers
        local active_group = groups.get_active_group()
        local active_group_id = active_group and active_group.id or nil
        local line_to_buffer = state_module.get_line_to_buffer_id()
        local line_group_context = state_module.get_line_group_context()
        
        local line_hints, hint_lines, bufferline_hints = generate_extended_hints(
            components, line_to_buffer, line_group_context, active_group_id
        )
        
        -- Activate extended picking mode
        local pick_mode = detect_pick_mode()
        state_module.set_extended_picking_active(true)
        state_module.set_extended_picking_mode(pick_mode)
        state_module.set_extended_picking_hints(line_hints, hint_lines, bufferline_hints)

        -- Start highlight application timer during picking mode
        local timer = vim.loop.new_timer()
        timer:start(0, config_module.UI.HIGHLIGHT_UPDATE_INTERVAL, vim.schedule_wrap(function()
            local current_state = require('bufferline.state')
            if current_state.is_picking and state_module.is_sidebar_open() then
                M.apply_extended_picking_highlights()
            else
                state_module.stop_highlight_timer()
            end
        end))
        state_module.set_highlight_timer(timer)
    elseif not is_picking and state_module.was_picking() then
        state_module.set_was_picking(false)
        -- Clean up timer when exiting picking mode
        state_module.stop_highlight_timer()
        -- Deactivate extended picking mode
        state_module.set_extended_picking_active(false)
    end

    return is_picking
end

-- Determine if path should be shown for a buffer based on configuration
local function should_show_path_for_buffer(buffer_id)
    local show_path_setting = config_module.DEFAULTS.show_path
    
    if show_path_setting == "no" then
        return false
    elseif show_path_setting == "yes" then
        return true
    elseif show_path_setting == "auto" then
        -- Auto mode: show path only when there are filename conflicts
        if not buffer_id or not api.nvim_buf_is_valid(buffer_id) then
            return false
        end
        
        local current_filename = vim.fn.fnamemodify(api.nvim_buf_get_name(buffer_id), ":t")
        if current_filename == "" then
            return false
        end
        
        -- Check if there are other buffers in the current group with the same filename
        local active_group = groups.get_active_group()
        if not active_group then
            return false
        end
        
        local conflicts = 0
        for _, other_buffer_id in ipairs(active_group.buffers) do
            if other_buffer_id ~= buffer_id and api.nvim_buf_is_valid(other_buffer_id) then
                local other_filename = vim.fn.fnamemodify(api.nvim_buf_get_name(other_buffer_id), ":t")
                if other_filename == current_filename then
                    conflicts = conflicts + 1
                end
            end
        end
        
        return conflicts > 0
    end
    
    return false
end

-- Extract and format path information for buffer display
local function get_buffer_path_info(component)
    if not api.nvim_buf_is_valid(component.id) then
        return nil, component.name
    end
    
    local full_path = api.nvim_buf_get_name(component.id)
    if full_path == "" then
        return nil, component.name
    end
    
    local filename = vim.fn.fnamemodify(full_path, ":t")
    local directory = vim.fn.fnamemodify(full_path, ":h")
    
    -- Convert to relative path if possible
    local cwd = vim.fn.getcwd()
    local relative_dir = directory
    if directory:sub(1, #cwd) == cwd then
        relative_dir = directory:sub(#cwd + 2) -- +2 to skip the trailing slash
        if relative_dir == "" then
            relative_dir = "."
        end
    elseif directory:sub(1, #vim.fn.expand("~")) == vim.fn.expand("~") then
        relative_dir = "~" .. directory:sub(#vim.fn.expand("~") + 1)
    end
    
    -- Limit path length if too long
    if #relative_dir > config_module.DEFAULTS.path_max_length then
        local parts = vim.split(relative_dir, "/")
        if #parts > 2 then
            relative_dir = ".../" .. table.concat({parts[#parts-1], parts[#parts]}, "/")
        end
    end
    
    return relative_dir, filename
end

local renderer = require('vertical-bufferline.renderer')
local components = require('vertical-bufferline.components')

-- Create individual buffer line with proper formatting and highlights
local function create_buffer_line(component, j, total_components, current_buffer_id, is_picking, line_number, group_id, max_local_digits, max_global_digits, has_any_local_info, should_hide_local_numbering)
    local is_last = (j == total_components)
    local is_current = (component.id == current_buffer_id)
    local is_visible = component.focused or false  -- Assuming focused means visible
    
    -- Check if this buffer is in the currently active group
    local groups = require('vertical-bufferline.groups')
    local active_group = groups.get_active_group()
    local is_in_active_group = active_group and (group_id == active_group.id)
    
    -- Build line parts using component system
    local parts = {}
    
    -- 1. Tree prefix (optional, but always show for current buffer in history)
    if config_module.DEFAULTS.show_tree_lines then
        local tree_parts = components.create_tree_prefix(is_last, is_current, is_in_active_group)
        for _, part in ipairs(tree_parts) do
            table.insert(parts, part)
        end
    elseif group_id == "history" and is_current then
        -- For history group, always show current buffer marker
        local renderer = require('vertical-bufferline.renderer')
        local current_marker = renderer.create_part(config_module.UI.CURRENT_BUFFER_MARKER, config_module.HIGHLIGHTS.PREFIX_CURRENT)
        table.insert(parts, current_marker)
    end
    
    -- 2. Pick letter (if in picking mode)
    if is_picking then
        local letter = nil
        -- Check if we're in extended picking mode
        local extended_picking = state_module.get_extended_picking_state()
        if extended_picking.is_active and line_number and extended_picking.line_hints[line_number] then
            letter = extended_picking.line_hints[line_number]
        else
            -- Fallback to bufferline hints
            local ok, element = pcall(function() return component:as_element() end)
            if ok and element and element.letter then
                letter = element.letter
            elseif component.letter then
                letter = component.letter
            end
        end
        
        if letter then
            local pick_parts = components.create_pick_letter(letter, is_current, is_visible)
            for _, part in ipairs(pick_parts) do
                table.insert(parts, part)
            end
        end
    end
    
    -- 3. Smart numbering (intelligent display logic)
    local bl_integration = require('vertical-bufferline.bufferline-integration')
    -- 2. Numbering (skip if position is 0, and only show for active group)
    if j > 0 and is_in_active_group then
        local ok, position_info = pcall(bl_integration.get_buffer_position_info, group_id)
        if ok and position_info then
            local local_pos = position_info[component.id]  -- nil if not visible in bufferline
            local global_pos = j  -- Global position is just the index in current group
            local numbering_parts = components.create_smart_numbering(local_pos, global_pos, max_local_digits or 1, max_global_digits or 1, has_any_local_info, should_hide_local_numbering)
            for _, part in ipairs(numbering_parts) do
                table.insert(parts, part)
            end
        else
            -- Fallback to simple numbering
            local numbering_parts = components.create_simple_numbering(j, max_global_digits or 1)
            for _, part in ipairs(numbering_parts) do
                table.insert(parts, part)
            end
        end
    end
    
    -- 4. Space after numbering (only if there was numbering)
    if j > 0 and is_in_active_group then
        local space_parts = components.create_space(1)
        for _, part in ipairs(space_parts) do
            table.insert(parts, part)
        end
    end
    
    -- 5. Icon (moved before filename) - only if enabled
    if config_module.DEFAULTS.show_icons then
        local icon = component.icon or ""
        if icon == "" then
            local extension = component.name:match("%.([^%.]+)$")
            if extension then
                icon = config_module.ICONS[extension] or config_module.ICONS.default
            end
        end
        local icon_parts = components.create_icon(icon)
        for _, part in ipairs(icon_parts) do
            table.insert(parts, part)
        end
    end
    
    -- 6. Filename with optional prefix
    local path_dir, display_name = get_buffer_path_info(component)
    local final_name = display_name or component.name
    
    local prefix_info = nil
    if component.minimal_prefix and component.minimal_prefix.prefix and component.minimal_prefix.prefix ~= "" then
        prefix_info = {
            prefix = component.minimal_prefix.prefix,
            filename = component.minimal_prefix.filename
        }
        final_name = prefix_info.prefix .. prefix_info.filename
    end
    
    local filename_parts = components.create_filename(prefix_info, final_name, is_current, is_visible)
    for _, part in ipairs(filename_parts) do
        table.insert(parts, part)
    end
    
    -- 7. Modified indicator (moved to end)
    local is_modified = is_buffer_actually_modified(component.id)
    local modified_parts = components.create_modified_indicator(is_modified)
    for _, part in ipairs(modified_parts) do
        table.insert(parts, part)
    end
    
    -- Render the complete line
    local rendered_line = renderer.render_line(parts)
    
    -- Create path line if needed
    local path_line = nil
    local should_show_path = should_show_path_for_buffer(component.id)
    if path_dir and should_show_path then
        local show_path_setting = config_module.DEFAULTS.show_path
        if show_path_setting == "yes" or path_dir ~= "." then
            -- Calculate dynamic indentation to align with filename
            -- Use the same component calculation as filename lines for perfect alignment
            local base_indent = 0
            
            -- Tree prefix: only if show_tree_lines is enabled
            if config_module.DEFAULTS.show_tree_lines then
                base_indent = base_indent + 4  -- " " + tree_chars (4 chars total)
            elseif group_id == "history" and is_current then
                base_indent = base_indent + 2  -- current marker for history
            end
            
            -- Add pick letter space if in picking mode
            if is_picking then
                base_indent = base_indent + 2  -- "a "
            end
            
            -- Add numbering width - only if j > 0 and in active group
            if j > 0 and is_in_active_group then
                local numbering_width
                if not has_any_local_info or should_hide_local_numbering then
                    -- Case 1 & 2: Only global number shown
                    numbering_width = (max_global_digits or 1) + 1  -- "global "
                else
                    -- Case 3: Dual numbering shown
                    numbering_width = (max_local_digits or 1) + 1 + (max_global_digits or 1) + 1  -- "local|global "
                end
                base_indent = base_indent + numbering_width
                
                -- Add space after numbering (create_space(1))
                -- base_indent = base_indent + 1  -- Skip this space to fix alignment
            end
            
            -- Add icon width if icons are enabled (emoji + space)
            if config_module.DEFAULTS.show_icons then
                base_indent = base_indent + 2  -- "🌙 " (emoji + space)
            end
            
            local display_path = path_dir == "." and "./" or path_dir .. "/"
            
            -- Only add tree continuation if tree lines are enabled
            if config_module.DEFAULTS.show_tree_lines then
                -- Use different continuation character for active vs inactive groups
                local continuation_char = is_in_active_group and "┃" or "│"
                local tree_continuation = is_last and string.rep(" ", base_indent) or (" " .. continuation_char .. string.rep(" ", base_indent - 2))
                path_line = tree_continuation .. display_path
            else
                -- Simple indentation without tree lines
                path_line = string.rep(" ", base_indent) .. display_path
            end
        end
    end
    
    return {
        text = rendered_line.text,
        rendered_line = rendered_line,  -- Store the complete rendered line
        path_line = path_line,
        has_path = path_line ~= nil,
        prefix_info = prefix_info,
        -- Legacy fields for compatibility
        tree_prefix = parts[1] and parts[1].text or "",
        pick_highlight_group = nil,  -- Now handled by renderer
        pick_highlight_end = 0,
        number_highlights = nil  -- Now handled by renderer
    }
end

-- Apply all highlighting for a single buffer line (unified highlighting function)
local function apply_buffer_highlighting(line_info, component, actual_line_number, current_buffer_id, is_picking, is_in_active_group)
    if not line_info or not component then return end
    
    -- Use new renderer system if available
    if line_info.rendered_line then
        renderer.apply_highlights(state_module.get_buf_id(), ns_id, actual_line_number - 1, line_info.rendered_line)
        return
    end
    
    -- Legacy highlighting fallback (can be removed later)
    
    local line_text = line_info.text
    local tree_prefix = line_info.tree_prefix or ""
    local prefix_info = line_info.prefix_info
    
    -- Note: Highlight groups are set up once in main refresh function
    -- Remove debug code that was causing highlight group conflicts
    
    -- Determine buffer state for highlighting
    local is_current = component.id == current_buffer_id
    local is_visible = component.focused or false
    
    -- Choose appropriate highlight groups based on buffer state and group context
    local tree_highlight_group, filename_highlight_group, prefix_highlight_group
    
    if is_current and is_in_active_group then
        -- Current buffer in active group: most prominent
        tree_highlight_group = config_module.HIGHLIGHTS.CURRENT
        filename_highlight_group = config_module.HIGHLIGHTS.FILENAME_CURRENT
        prefix_highlight_group = config_module.HIGHLIGHTS.PREFIX_CURRENT
    elseif is_current then
        -- Current buffer but NOT in active group: should not be highlighted as current
        tree_highlight_group = config_module.HIGHLIGHTS.INACTIVE
        filename_highlight_group = config_module.HIGHLIGHTS.FILENAME
        prefix_highlight_group = config_module.HIGHLIGHTS.PREFIX
    elseif is_visible and is_in_active_group then
        -- Visible buffer in active group: medium prominence
        tree_highlight_group = config_module.HIGHLIGHTS.VISIBLE
        filename_highlight_group = config_module.HIGHLIGHTS.FILENAME_VISIBLE
        prefix_highlight_group = config_module.HIGHLIGHTS.PREFIX_VISIBLE
    elseif is_in_active_group then
        -- Non-visible buffer in active group: normal
        tree_highlight_group = config_module.HIGHLIGHTS.INACTIVE
        filename_highlight_group = config_module.HIGHLIGHTS.FILENAME
        prefix_highlight_group = config_module.HIGHLIGHTS.PREFIX
    else
        -- Buffer in non-active group: most subdued
        tree_highlight_group = config_module.HIGHLIGHTS.INACTIVE
        filename_highlight_group = config_module.HIGHLIGHTS.FILENAME
        prefix_highlight_group = config_module.HIGHLIGHTS.PREFIX
    end
    
    -- Highlight groups are ensured to exist by main refresh function
    
    -- Apply tree/prefix highlighting to the beginning part (tree branches, numbers, icons)
    -- Find where the actual filename starts
    local filename_start_pos = nil
    local icon_pos = line_text:find("[🌙📄🐍🟢🦀📝📋]")
    if icon_pos then
        -- Find first character after the icon and space
        filename_start_pos = line_text:find("%S", icon_pos + 2)
    else
        -- Fallback: find filename after tree prefix and common markers
        local after_tree = #tree_prefix + 1
        local marker_pattern = "[►]?%s*%d+%s+"  -- Optional arrow, space, number, space
        local marker_end = line_text:find(marker_pattern, after_tree)
        if marker_end then
            filename_start_pos = line_text:find("%S", marker_end + string.len(line_text:match(marker_pattern, after_tree)))
        else
            filename_start_pos = line_text:find("%S", after_tree)
        end
    end
    
    -- Apply tree/prefix highlighting (everything before filename)
    if filename_start_pos and filename_start_pos > 1 then
        api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, tree_highlight_group, actual_line_number - 1, 0, filename_start_pos - 1)
    end
    
    -- Find and highlight the modified indicator "●" if present
    local modified_pos = line_text:find("●")
    if modified_pos then
        api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, config_module.HIGHLIGHTS.MODIFIED, actual_line_number - 1, modified_pos - 1, modified_pos)
    end
    
    -- Apply dual numbering highlighting by parsing the line text
    -- Look for dual numbering pattern like "3|5" in the line
    local number_start = #tree_prefix  -- Numbers come right after tree prefix
    local number_pattern = "([-%d]+)|([%d]+)"  -- Match "3|5" or "-|5" patterns
    local line_substr = line_text:sub(number_start + 1)  -- Get text after tree prefix
    local local_num, global_num = line_substr:match("^%s*" .. number_pattern)
    
    if local_num and global_num then
        -- Found dual numbering pattern, apply highlighting
        local pattern_start = line_text:find(number_pattern, number_start + 1)
        if pattern_start then
            -- Highlight local number
            if local_num == "-" then
                api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, config_module.HIGHLIGHTS.NUMBER_HIDDEN, 
                                           actual_line_number - 1, pattern_start - 1, pattern_start - 1 + #local_num)
            else
                api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, config_module.HIGHLIGHTS.NUMBER_LOCAL, 
                                           actual_line_number - 1, pattern_start - 1, pattern_start - 1 + #local_num)
            end
            
            -- Highlight separator "|"
            local separator_pos = pattern_start - 1 + #local_num
            api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, config_module.HIGHLIGHTS.NUMBER_SEPARATOR, 
                                       actual_line_number - 1, separator_pos, separator_pos + 1)
            
            -- Highlight global number
            local global_pos = separator_pos + 1
            api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, config_module.HIGHLIGHTS.NUMBER_GLOBAL, 
                                       actual_line_number - 1, global_pos, global_pos + #global_num)
        end
    end
    
    -- Apply filename highlighting (from filename_start_pos to end of line)
    if filename_start_pos and filename_start_pos <= #line_text then
        if prefix_info and prefix_info.prefix and prefix_info.prefix ~= "" then
            -- Handle buffers WITH prefix: highlight prefix and filename separately
            local prefix_start = line_text:find(vim.pesc(prefix_info.prefix), filename_start_pos)
            if prefix_start then
                local prefix_end = prefix_start + #prefix_info.prefix - 1
                
                -- Highlight prefix part
                api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, prefix_highlight_group, actual_line_number - 1, prefix_start - 1, prefix_end)
                
                -- Highlight filename part (after prefix)
                local filename_part_start = prefix_end + 1
                if filename_part_start <= #line_text then
                    api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, filename_highlight_group, actual_line_number - 1, filename_part_start - 1, -1)
                end
            else
                -- Fallback: highlight entire filename part
                api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, filename_highlight_group, actual_line_number - 1, filename_start_pos - 1, -1)
            end
        else
            -- Handle buffers WITHOUT prefix: highlight entire filename part
            api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, filename_highlight_group, actual_line_number - 1, filename_start_pos - 1, -1)
        end
    end
end

-- Apply path-specific highlighting for path lines
local function apply_path_highlighting(component, path_line_number, current_buffer_id, is_in_active_group)
    local path_highlight_group = config_module.HIGHLIGHTS.PATH
    
    -- Only highlight current buffer's path differently if it's in the active group
    if component.id == current_buffer_id and is_in_active_group then
        -- Current buffer's path in active group: slightly different (NonText)
        path_highlight_group = config_module.HIGHLIGHTS.PATH_CURRENT
    else
        -- ALL other paths: exactly the same style (Comment)
        -- This includes: 
        -- 1. Non-current buffers in any group
        -- 2. Current buffer in non-active groups
        path_highlight_group = config_module.HIGHLIGHTS.PATH
    end
    
    -- Apply path highlighting with determined group
    
    -- Apply consistent highlighting to all paths: highlight the entire line with the same style
    -- This eliminates any inconsistencies in range calculation
    api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, path_highlight_group, path_line_number - 1, 0, -1)
end

-- Render buffers within a single group
local function render_group_buffers(group_components, current_buffer_id, is_picking, lines_text, new_line_map, line_types, line_components, line_group_context, line_infos)
    
    -- Calculate max digits for alignment
    local max_global_digits = string.len(tostring(#group_components))
    
    -- Calculate max local digits and analyze if local numbering should be shown
    local max_local_digits = 1  -- At least 1 for "-"
    local has_any_local_info = false
    local should_hide_local_numbering = false  -- Hide local if first local equals 1
    local bl_integration = require('vertical-bufferline.bufferline-integration')
    local ok, position_info = pcall(bl_integration.get_buffer_position_info, line_group_context.current_group_id)
    if ok and position_info then
        -- Check first component to determine if local numbering should be hidden
        if #group_components > 0 then
            local first_component = group_components[1]
            local first_local_pos = position_info[first_component.id]
            if first_local_pos and first_local_pos == 1 then
                should_hide_local_numbering = true
            end
        end
        
        -- Calculate max digits for all components
        for _, component in ipairs(group_components) do
            local local_pos = position_info[component.id]
            if local_pos then
                has_any_local_info = true
                local digits = string.len(tostring(local_pos))
                if digits > max_local_digits then
                    max_local_digits = digits
                end
            end
        end
    end
    
    for j, component in ipairs(group_components) do
        if component.id and component.name and api.nvim_buf_is_valid(component.id) then
            -- Calculate the line number this buffer will be on
            local main_line_number = #lines_text + 1
            local line_info = create_buffer_line(component, j, #group_components, current_buffer_id, is_picking, main_line_number, line_group_context.current_group_id, max_local_digits, max_global_digits, has_any_local_info, should_hide_local_numbering)

            -- Add main buffer line
            table.insert(lines_text, line_info.text)
            new_line_map[main_line_number] = component.id
            line_types[main_line_number] = "buffer"  -- Record this as a buffer line
            line_components[main_line_number] = component  -- Store specific component for this line
            line_infos[main_line_number] = line_info  -- Store complete line_info for highlighting
            line_group_context[main_line_number] = line_group_context.current_group_id  -- Store which group this line belongs to

            -- Note: Buffer highlighting will be applied later in the main refresh loop
            
            -- Add path line if it exists
            if line_info.has_path and line_info.path_line then
                table.insert(lines_text, line_info.path_line)
                local path_line_number = #lines_text
                
                -- Path line also maps to the same buffer for click handling
                new_line_map[path_line_number] = component.id
                line_types[path_line_number] = "path"  -- Record this as a path line
                line_components[path_line_number] = component  -- Store specific component for this line
                line_group_context[path_line_number] = line_group_context.current_group_id  -- Store which group this line belongs to
                
                -- Note: Path highlighting will be applied later in the main refresh loop
            end
        end
    end
end

-- Render header for a single group
local function render_group_header(group, i, is_active, buffer_count, lines_text, group_header_lines)
    local group_marker = is_active and config_module.UI.ACTIVE_GROUP_MARKER or config_module.UI.INACTIVE_GROUP_MARKER
    local group_name_display = group.name == "" and config_module.UI.UNNAMED_GROUP_DISPLAY or group.name

    -- Add spacing between groups (except for first group)
    if i > config_module.SYSTEM.FIRST_INDEX then
        table.insert(lines_text, "")  -- Empty line separator
        local separator_line_num = #lines_text
        table.insert(group_header_lines, {line = separator_line_num, type = "separator"})
    end

    local group_line = string.format("[%d] %s %s (%d buffers)",
        group.display_number, group_marker, group_name_display, buffer_count)
    table.insert(lines_text, group_line)

    -- Record group header line info
    table.insert(group_header_lines, {
        line = #lines_text - config_module.SYSTEM.ZERO_BASED_OFFSET,  -- 0-based line number
        type = "header",
        is_active = is_active,
        group_id = group.id,
        group_number = group.display_number
    })
end

-- Render current group's history as a unified group
local function render_current_group_history(active_group, current_buffer_id, is_picking, lines_text, new_line_map, group_header_lines, line_types, all_components, line_components, line_group_context, line_infos)
    if not active_group or not groups.should_show_history(active_group.id) then
        return
    end
    
    -- Get history from current active group only
    local history = groups.get_group_history(active_group.id)
    if not history or #history == 0 then
        return
    end
    
    -- Filter valid history items
    local valid_history = {}
    for _, buffer_id in ipairs(history) do
        if api.nvim_buf_is_valid(buffer_id) then
            table.insert(valid_history, buffer_id)
        end
    end
    
    -- Only render if we have valid history items
    if #valid_history > 0 then
        -- Render history group header
        local header_text = string.format("[H] 📋 Recent Files (%d)", math.min(#valid_history, config_module.DEFAULTS.history_display_count))
        table.insert(lines_text, header_text)
        local header_line_num = #lines_text
        group_header_lines[header_line_num] = {
            group_id = "history",
            group_number = "H"
        }
        
        -- Render history items
        for i, buffer_id in ipairs(valid_history) do
            if i > config_module.DEFAULTS.history_display_count then break end
            
            local buf_name = api.nvim_buf_get_name(buffer_id)
            local filename = vim.fn.fnamemodify(buf_name, ":t")
            local is_current = buffer_id == current_buffer_id
            local is_last = (i == math.min(#valid_history, config_module.DEFAULTS.history_display_count))
            
            -- Create component object for history buffer
            local history_component = {
                id = buffer_id,
                name = filename,
                focused = is_current  -- Current buffer should be focused for proper highlighting
            }
            
            -- Create buffer line - first item (current) has no number, rest have numbers
            local display_pos = (i == 1) and 0 or (i - 1)  -- First item has no number, rest are numbered 1, 2, 3...
            local line_info = create_buffer_line(history_component, display_pos, #valid_history, current_buffer_id, is_picking, #lines_text + 1, "history", 1, 1, false, false)
            table.insert(lines_text, line_info.text)
            local line_num = #lines_text
            
            -- Map this line to the buffer
            new_line_map[line_num] = buffer_id
            line_types[line_num] = "history"
            line_components[line_num] = history_component
            line_group_context[line_num] = active_group.id
            line_infos[line_num] = line_info
            
            -- Add to all components for highlighting
            all_components[buffer_id] = history_component
        end
        
        -- Add empty line after history
        table.insert(lines_text, "")
        local empty_line_num = #lines_text
        line_types[empty_line_num] = "empty"
    end
end

-- Render all groups with their buffers
local function render_all_groups(active_group, components, current_buffer_id, is_picking, lines_text, new_line_map, group_header_lines, line_types, all_components, line_components, line_group_context, line_infos)
    if not active_group then
        return components
    end

    local all_groups = groups.get_all_groups()
    local remaining_components = components

    for i, group in ipairs(all_groups) do
        local is_active = group.id == active_group.id
        local group_buffers = groups.get_group_buffers(group.id) or {}

        -- Calculate valid buffer count (filter out unnamed and special buffers)
        local valid_buffer_count = 0
        for _, buf_id in ipairs(group_buffers) do
            if vim.api.nvim_buf_is_valid(buf_id) and not is_special_buffer(buf_id) then
                local buf_name = vim.api.nvim_buf_get_name(buf_id)
                if buf_name ~= "" then
                    valid_buffer_count = valid_buffer_count + 1
                end
            end
        end
        local buffer_count = valid_buffer_count

        -- Render group header
        render_group_header(group, i, is_active, buffer_count, lines_text, group_header_lines)

        -- Decide whether to expand group based on mode
        local should_expand = state_module.get_expand_all_groups() or is_active
        if should_expand then
            -- Get current group buffers and display them
            local group_components = {}
            if is_active then
                -- For active group, filter out unnamed and special buffers for consistency
                for _, comp in ipairs(components) do
                    if comp.id and comp.name then
                        local buf_name = api.nvim_buf_get_name(comp.id)
                        -- Filter out unnamed and special buffers
                        if buf_name ~= "" and not is_special_buffer(comp.id) then
                            table.insert(group_components, comp)
                        end
                    end
                end
            end

            -- Apply smart filenames for current active group too (if needed)
            if is_active and #group_components > 0 then
                -- Check if there are duplicate filenames that need smart handling
                local buffer_ids = {}
                for _, comp in ipairs(group_components) do
                    if comp.id then
                        table.insert(buffer_ids, comp.id)
                    end
                end

                if #buffer_ids > 1 then
                    local minimal_prefixes = filename_utils.generate_minimal_prefixes(buffer_ids)
                    -- Update component names with minimal prefixes
                    for j, comp in ipairs(group_components) do
                        if comp.id and minimal_prefixes[j] then
                            comp.minimal_prefix = minimal_prefixes[j]
                        end
                    end
                end
            end

            -- For expand-all mode and non-active groups, manually construct components
            if state_module.get_expand_all_groups() and not is_active then
                group_components = {}

                -- First collect all valid buffer information
                local valid_buffers = {}
                for _, buf_id in ipairs(group_buffers) do
                    if api.nvim_buf_is_valid(buf_id) then
                        local buf_name = api.nvim_buf_get_name(buf_id)
                        if buf_name ~= "" then
                            table.insert(valid_buffers, buf_id)
                        end
                    end
                end

                -- Generate minimal prefixes for conflict resolution
                local minimal_prefixes = filename_utils.generate_minimal_prefixes(valid_buffers)

                -- Construct components
                for j, buf_id in ipairs(valid_buffers) do
                    local filename = vim.fn.fnamemodify(api.nvim_buf_get_name(buf_id), ":t")
                    table.insert(group_components, {
                        id = buf_id,
                        name = filename,
                        minimal_prefix = minimal_prefixes[j],
                        icon = "",
                        focused = false
                    })
                end
            end

            -- If group is empty, show clean empty group hint
            if #group_components == 0 then
                local empty_line = config_module.DEFAULTS.show_tree_lines and 
                    ("  " .. config_module.UI.TREE_LAST .. config_module.UI.TREE_EMPTY) or 
                    ("  " .. config_module.UI.TREE_EMPTY)
                table.insert(lines_text, empty_line)
                local empty_group_line = #lines_text
                line_types[empty_group_line] = "empty_group"
            end

            -- Render group buffers
            line_group_context.current_group_id = group.id  -- Set current group context
            
            -- Determine current buffer for this specific group
            local group_current_buffer_id = nil
            if is_active then
                -- For active group, use global current buffer if it's in the group, otherwise use group's remembered current_buffer
                local global_current = current_buffer_id
                if global_current and vim.tbl_contains(group.buffers, global_current) then
                    group_current_buffer_id = global_current
                elseif group.current_buffer and vim.tbl_contains(group.buffers, group.current_buffer) then
                    group_current_buffer_id = group.current_buffer
                end
            else
                -- For non-active groups, always use the group's remembered current_buffer
                if group.current_buffer and vim.tbl_contains(group.buffers, group.current_buffer) then
                    group_current_buffer_id = group.current_buffer
                end
            end
            
            render_group_buffers(group_components, group_current_buffer_id, is_picking, lines_text, new_line_map, line_types, line_components, line_group_context, line_infos)
            
            -- Collect all components for highlighting
            for _, comp in ipairs(group_components) do
                all_components[comp.id] = comp
            end

            -- If current active group and not expand-all mode, clear remaining components
            if is_active and not state_module.get_expand_all_groups() then
                remaining_components = {}
            end
        end
    end

    return remaining_components
end

-- Apply group header highlights
local function apply_group_highlights(group_header_lines, lines_text)
    for _, header_info in ipairs(group_header_lines) do
        if header_info.type == "separator" then
            -- Empty separator line - no highlight needed
            -- Just a space line for visual separation
        elseif header_info.type == "header" then
            -- Group title line overall highlight with background
            local group_highlight = header_info.is_active and config_module.HIGHLIGHTS.GROUP_ACTIVE or config_module.HIGHLIGHTS.GROUP_INACTIVE
            api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, group_highlight, header_info.line, 0, -1)

            -- Note: We no longer highlight individual parts (number, marker) to preserve the background color
            -- The overall group highlight already provides the visual distinction
        elseif header_info.type == "separator_visual" then
            -- This type is no longer used since we removed visual separators
        end
    end
end

-- Finalize buffer display with lines and mapping
local function finalize_buffer_display(lines_text, new_line_map, line_group_context, group_header_lines)
    api.nvim_buf_set_option(state_module.get_buf_id(), "modifiable", true)
    api.nvim_buf_set_lines(state_module.get_buf_id(), 0, -1, false, lines_text)
    
    state_module.set_line_to_buffer_id(new_line_map)
    state_module.set_line_group_context(line_group_context or {})
    state_module.set_group_header_lines(group_header_lines or {})
end

-- Complete buffer setup and make it read-only
local function complete_buffer_setup()
    api.nvim_buf_set_option(state_module.get_buf_id(), "modifiable", false)
end

--- Refreshes the sidebar content with the current list of buffers.
function M.refresh(reason)
    local refresh_data = validate_and_initialize_refresh()
    if not refresh_data then 
        return 
    end

    local components = refresh_data.components
    local current_buffer_id = refresh_data.current_buffer_id
    local active_group = refresh_data.active_group

    -- Handle picking mode detection and timer management
    local is_picking = detect_and_manage_picking_mode(refresh_data.bufferline_state, components)

    local lines_text = {}
    local new_line_map = {}
    local group_header_lines = {}  -- Record group header line positions and info
    local line_types = {}  -- Record what type each line is: "buffer", "path", "group_header", "group_separator"
    local all_components = {}  -- Collect all components from all groups for highlighting
    local line_components = {}  -- Store specific component for each line (handles multi-group buffers)
    local line_infos = {}  -- Store complete line_info for each line (includes number_highlights)
    local line_group_context = {}  -- Store which group each line belongs to

    -- Render current group's history first (at the top)
    render_current_group_history(active_group, current_buffer_id, is_picking, lines_text, new_line_map, group_header_lines, line_types, all_components, line_components, line_group_context, line_infos)
    
    -- Render all groups with their buffers (without applying highlights yet)
    local remaining_components = render_all_groups(active_group, components, current_buffer_id, is_picking, lines_text, new_line_map, group_header_lines, line_types, all_components, line_components, line_group_context, line_infos)

    -- Finalize buffer display (set lines but keep modifiable) - this clears highlights
    finalize_buffer_display(lines_text, new_line_map, line_group_context, group_header_lines)
    
    -- Clear old highlights and apply all highlights AFTER buffer content is set
    api.nvim_buf_clear_namespace(state_module.get_buf_id(), ns_id, 0, -1)
    
    -- Re-setup highlights after clearing to ensure they're available
    setup_highlights()
    
    -- Force set path highlights if they're empty (fix for reload protection issue)
    local path_hl = api.nvim_get_hl(0, {name = config_module.HIGHLIGHTS.PATH})
    local path_current_hl = api.nvim_get_hl(0, {name = config_module.HIGHLIGHTS.PATH_CURRENT})
    
    if not next(path_hl) then
        api.nvim_set_hl(0, config_module.HIGHLIGHTS.PATH, { link = "Comment", italic = true })
    end
    
    if not next(path_current_hl) then
        api.nvim_set_hl(0, config_module.HIGHLIGHTS.PATH_CURRENT, { link = "NonText", italic = true })
    end
    
    -- Apply group header highlights
    apply_group_highlights(group_header_lines, lines_text)
    
    -- Apply all buffer highlights using the line type table
    for line_num, buffer_id in pairs(new_line_map) do
        local line_type = line_types[line_num]
        
        -- Find the component for this specific line (handles multi-group buffers correctly)
        local component = line_components[line_num]
        
        if component then
            -- Determine if this line belongs to the active group and get group-specific current buffer
            local line_group_id = line_group_context[line_num]
            local is_in_active_group = false
            local group_current_buffer_id = nil
            
            if active_group and line_group_id then
                is_in_active_group = (line_group_id == active_group.id)
                
                -- Get the group this line belongs to
                local line_group = groups.find_group_by_id(line_group_id)
                if line_group then
                    if is_in_active_group then
                        -- For active group, use global current buffer if it's in the group, otherwise use group's remembered current_buffer
                        if current_buffer_id and vim.tbl_contains(line_group.buffers, current_buffer_id) then
                            group_current_buffer_id = current_buffer_id
                        elseif line_group.current_buffer and vim.tbl_contains(line_group.buffers, line_group.current_buffer) then
                            group_current_buffer_id = line_group.current_buffer
                        end
                    else
                        -- For non-active groups, always use the group's remembered current_buffer
                        if line_group.current_buffer and vim.tbl_contains(line_group.buffers, line_group.current_buffer) then
                            group_current_buffer_id = line_group.current_buffer
                        end
                    end
                end
            end
            
            if line_type == "path" then
                -- This is a path line - apply path-specific highlighting
                apply_path_highlighting(component, line_num, group_current_buffer_id, is_in_active_group)
            elseif line_type == "buffer" then
                -- This is a main buffer line - apply buffer highlighting
                -- Use the stored line_info that contains number_highlights
                local line_info = line_infos[line_num]
                
                if not line_info then
                    -- Fallback: create a minimal line_info if not found
                    local line_text = api.nvim_buf_get_lines(state_module.get_buf_id(), line_num - 1, line_num, false)[1] or ""
                    line_info = {
                        text = line_text,
                        tree_prefix = " ├─ ",
                        prefix_info = component.minimal_prefix
                    }
                end
                
                -- Apply highlighting with group context
                apply_buffer_highlighting(line_info, component, line_num, group_current_buffer_id, is_picking, is_in_active_group)
            elseif line_type == "history" then
                -- This is a history line - apply proper highlighting using the component system
                local component = line_components[line_num]
                local line_info = line_infos[line_num]
                if component and line_info then
                    local buffer_id = new_line_map[line_num]
                    local is_current_buffer = (buffer_id == current_buffer_id)
                    -- Apply highlighting with proper group context (history group is considered active)
                    apply_buffer_highlighting(line_info, component, line_num, current_buffer_id, is_picking, true)
                end
            elseif line_type == "history_header" then
                -- This is a history header line - apply header highlighting
                local highlight_group = config_module.HIGHLIGHTS.GROUP_NUMBER  -- Same as group number
                api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, highlight_group, line_num - 1, 0, -1)
            end
            -- Note: group headers and separators are handled by apply_group_highlights above
        end
    end
    
    
    -- Complete buffer setup (make read-only)
    complete_buffer_setup()
end


--- Detect pick mode type from bufferline state

-- Make setup_pick_highlights available globally
M.setup_pick_highlights = setup_pick_highlights

--- Apply extended picking highlights for all sidebar buffers
function M.apply_extended_picking_highlights()
    if not state_module.is_sidebar_open() then return end

    local bufferline_state = require('bufferline.state')
    if not bufferline_state.is_picking then return end

    -- Re-setup highlights to ensure they're current
    setup_pick_highlights()

    local extended_picking = state_module.get_extended_picking_state()
    if not extended_picking.is_active then
        -- Fall back to original picking highlights
        M.apply_picking_highlights()
        return
    end

    local current_buffer_id = get_main_window_current_buffer()
    local line_to_buffer = state_module.get_line_to_buffer_id()
    local line_group_context = state_module.get_line_group_context()
    local active_group = groups.get_active_group()
    local active_group_id = active_group and active_group.id or nil

    -- Apply highlights to all lines with hints
    for line_num, hint_char in pairs(extended_picking.line_hints) do
        local buffer_id = line_to_buffer[line_num]
        if buffer_id then
            -- Choose appropriate pick highlight based on buffer state
            local pick_highlight_group
            if buffer_id == current_buffer_id then
                pick_highlight_group = config_module.HIGHLIGHTS.PICK_SELECTED
            else
                pick_highlight_group = config_module.HIGHLIGHTS.PICK
            end

            -- Get the actual line text to find the hint position
            local line_text = api.nvim_buf_get_lines(state_module.get_buf_id(), line_num - 1, line_num, false)[1] or ""
            local hint_pos = line_text:find(vim.pesc(hint_char))
            
            if hint_pos then
                local highlight_start = hint_pos - 1  -- Convert to 0-based
                local highlight_end = hint_pos  -- Highlight just the hint character
                
                -- Apply highlight with both namespace and without
                api.nvim_buf_add_highlight(state_module.get_buf_id(), 0, pick_highlight_group, line_num - 1, highlight_start, highlight_end)
                api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, pick_highlight_group, line_num - 1, highlight_start, highlight_end)
            end
        end
    end

    -- Also apply original bufferline highlights for active group buffers
    M.apply_picking_highlights()

    vim.cmd("redraw!")
end

--- Apply picking highlights continuously during picking mode
function M.apply_picking_highlights()
    if not state_module.is_sidebar_open() then return end

    local bufferline_state = require('bufferline.state')
    if not bufferline_state.is_picking then return end

    -- Re-setup highlights to ensure they're current
    setup_pick_highlights()

    -- Get current components
    local components = bufferline_state.components

    local current_buffer_id = get_main_window_current_buffer()

    -- We need to find the actual line number for each component
    -- Find through line_to_buffer_id mapping
    for i, component in ipairs(components) do
        if component.id and component.name then
            local ok, element = pcall(function() return component:as_element() end)
            local letter = nil
            if ok and element and element.letter then
                letter = element.letter
            elseif component.letter then
                letter = component.letter
            end

            if letter then
                -- Only highlight buffers in the active group
                local active_group = groups.get_active_group()
                if not active_group then return end
                
                local active_group_buffers = groups.get_group_buffers(active_group.id)
                if vim.tbl_contains(active_group_buffers, component.id) then
                    -- Find the actual line number of this buffer in the active group context
                    local actual_line_number = nil
                    local line_to_buffer = state_module.get_line_to_buffer_id()
                    local line_group_context = state_module.get_line_group_context()
                    
                    for line_num, buffer_id in pairs(line_to_buffer) do
                        if buffer_id == component.id and line_group_context and line_group_context[line_num] == active_group.id then
                            actual_line_number = line_num
                            break
                        end
                    end

                    if actual_line_number then
                        -- Choose appropriate pick highlight based on buffer state
                        local pick_highlight_group
                        if component.id == current_buffer_id then
                            pick_highlight_group = config_module.HIGHLIGHTS.PICK_SELECTED
                        elseif component.focused then
                            pick_highlight_group = config_module.HIGHLIGHTS.PICK_VISIBLE
                        else
                            pick_highlight_group = config_module.HIGHLIGHTS.PICK
                        end

                        -- Get the actual line text to find the letter position
                        local line_text = api.nvim_buf_get_lines(state_module.get_buf_id(), actual_line_number - 1, actual_line_number, false)[1] or ""
                        local letter_pos = line_text:find(vim.pesc(letter))
                        
                        if letter_pos then
                            local highlight_start = letter_pos - 1  -- Convert to 0-based
                            local highlight_end = letter_pos  -- Highlight just the letter
                            
                            -- Apply highlight with both namespace and without
                            api.nvim_buf_add_highlight(state_module.get_buf_id(), 0, pick_highlight_group, actual_line_number - 1, highlight_start, highlight_end)
                            api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, pick_highlight_group, actual_line_number - 1, highlight_start, highlight_end)
                        end
                    end
                end
            end
        end
    end
    
    -- Apply extended hints for non-active group buffers
    if extended_picking_state.active then
        apply_extended_picking_highlights()
    end

    vim.cmd("redraw!")
end



--- Closes the sidebar window.
function M.close_sidebar()
    if not state_module.is_sidebar_open() or not api.nvim_win_is_valid(state_module.get_win_id()) then return end

    local current_win = api.nvim_get_current_win()
    local all_windows = api.nvim_list_wins()
    local sidebar_win_id = state_module.get_win_id()

    -- Check if only one window remains (sidebar is the last window)
    if #all_windows == 1 then
        -- If only sidebar window remains, exit nvim completely
        vim.cmd("qall")
    else
        -- Normal case: multiple windows, safe to close sidebar
        api.nvim_set_current_win(sidebar_win_id)
        vim.cmd("close")

        -- Return to previous window
        if api.nvim_win_is_valid(current_win) and current_win ~= sidebar_win_id then
            api.nvim_set_current_win(current_win)
        else
            -- If previous window is invalid, find first valid non-sidebar window
            for _, win_id in ipairs(api.nvim_list_wins()) do
                if win_id ~= sidebar_win_id and api.nvim_win_is_valid(win_id) then
                    api.nvim_set_current_win(win_id)
                    break
                end
            end
        end
    end

    -- Clean up autocmd group for sidebar protection
    pcall(api.nvim_del_augroup_by_name, "VerticalBufferlineSidebarProtection")
    
    state_module.close_sidebar()
end

--- Setup standard keymaps for sidebar buffer
local function setup_sidebar_keymaps(buf_id)
    local keymap_opts = { noremap = true, silent = true }
    
    -- Navigation
    api.nvim_buf_set_keymap(buf_id, "n", "j", "j", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "k", "k", keymap_opts)
    
    -- Actions
    api.nvim_buf_set_keymap(buf_id, "n", "<CR>", ":lua require('vertical-bufferline').handle_selection()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "d", ":lua require('vertical-bufferline').smart_close_buffer()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "x", ":lua require('vertical-bufferline').remove_from_group()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "D", ":lua require('vertical-bufferline').smart_close_buffer()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "q", ":lua require('vertical-bufferline').close_sidebar()<CR>", keymap_opts)
    
    -- Settings
    api.nvim_buf_set_keymap(buf_id, "n", "p", ":lua require('vertical-bufferline').cycle_show_path_setting()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "h", ":lua require('vertical-bufferline').cycle_show_history_setting()<CR>", keymap_opts)
    
    -- Mouse support
    api.nvim_buf_set_keymap(buf_id, "n", "<LeftRelease>", ":lua require('vertical-bufferline').handle_mouse_click()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "<LeftMouse>", "<LeftMouse>", keymap_opts)
    
    -- Disable problematic keymaps
    api.nvim_buf_set_keymap(buf_id, "n", "<C-W>o", "<Nop>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "<C-W><C-O>", "<Nop>", keymap_opts)
end

--- Opens the sidebar window.
local function open_sidebar()
    if state_module.is_sidebar_open() then return end
    local buf_id = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf_id, 'bufhidden', 'wipe')
    local current_win = api.nvim_get_current_win()
    -- Create sidebar window based on configured position
    if config_module.DEFAULTS.position == "left" then
        vim.cmd("topleft vsplit")
    else
        vim.cmd("botright vsplit")
    end
    local new_win_id = api.nvim_get_current_win()
    api.nvim_win_set_buf(new_win_id, buf_id)
    api.nvim_win_set_width(new_win_id, config_module.DEFAULTS.width)
    api.nvim_win_set_option(new_win_id, 'winfixwidth', true)  -- Prevent window from auto-resizing width
    api.nvim_win_set_option(new_win_id, 'number', false)
    api.nvim_win_set_option(new_win_id, 'relativenumber', false)
    api.nvim_win_set_option(new_win_id, 'cursorline', false)
    api.nvim_win_set_option(new_win_id, 'cursorcolumn', false)
    
    -- Ensure mouse support is enabled for this window
    if vim.o.mouse == '' then
        vim.notify("Mouse support disabled. Enable with :set mouse=a for sidebar mouse interaction", vim.log.levels.INFO)
    end
    
    -- Note: We don't use winfixbuf as it completely blocks file opening
    -- Instead, we rely on autocmd protection below for smart handling
    
    -- Additional protection: monitor buffer changes in sidebar window
    local group_name = "VerticalBufferlineSidebarProtection"
    api.nvim_create_augroup(group_name, { clear = true })
    api.nvim_create_autocmd("BufWinEnter", {
        group = group_name,
        callback = function(ev)
            -- Only respond if the event is happening in the sidebar window specifically
            local current_win = ev.buf and vim.fn.win_findbuf(ev.buf)[1]
            if not current_win or current_win ~= new_win_id then
                return -- Event not related to sidebar window
            end
            
            -- Check if sidebar buffer was replaced with a real file
            local sidebar_buf = api.nvim_win_get_buf(new_win_id)
            local buf_name = api.nvim_buf_get_name(ev.buf)
            local buf_type = api.nvim_buf_get_option(ev.buf, 'buftype')
            local is_legitimate_file = buf_name ~= "" and vim.fn.filereadable(buf_name) == 1 and buf_type == ""
            
            
            if sidebar_buf == ev.buf and is_legitimate_file then
                -- User wants to open a file, help them by opening it in main window
                local main_win_id = nil
                for _, win in ipairs(api.nvim_list_wins()) do
                    if win ~= new_win_id and api.nvim_win_is_valid(win) then
                        local win_config = api.nvim_win_get_config(win)
                        if win_config.relative == "" then  -- Not floating window
                            main_win_id = win
                            break
                        end
                    end
                end
                
                if main_win_id then
                    -- Open file in main window and restore sidebar
                    api.nvim_win_set_buf(main_win_id, ev.buf)
                    api.nvim_set_current_win(main_win_id)
                    
                    -- The original sidebar buffer was wiped, create a new one
                    local new_sidebar_buf = api.nvim_create_buf(false, true)
                    api.nvim_buf_set_option(new_sidebar_buf, 'bufhidden', 'wipe')
                    api.nvim_win_set_buf(new_win_id, new_sidebar_buf)
                    
                    -- Update state with new buffer ID
                    state_module.set_buf_id(new_sidebar_buf)
                    
                    -- CRITICAL: Re-setup keymaps for the new sidebar buffer
                    setup_sidebar_keymaps(new_sidebar_buf)
                    
                    M.refresh("file_redirect")
                else
                    -- No main window available, restore sidebar
                    local new_sidebar_buf = api.nvim_create_buf(false, true)
                    api.nvim_buf_set_option(new_sidebar_buf, 'bufhidden', 'wipe')
                    api.nvim_win_set_buf(new_win_id, new_sidebar_buf)
                    state_module.set_buf_id(new_sidebar_buf)
                    
                    -- CRITICAL: Re-setup keymaps for the new sidebar buffer
                    setup_sidebar_keymaps(new_sidebar_buf)
                    
                    M.refresh("file_redirect")
                end
            end
        end,
        desc = "Protect sidebar from external buffer changes"
    })
    state_module.set_win_id(new_win_id)
    state_module.set_buf_id(buf_id)
    state_module.set_sidebar_open(true)

    setup_sidebar_keymaps(buf_id)

    api.nvim_set_current_win(current_win)
    M.refresh("sidebar_open")
end

--- Handle mouse click in sidebar
function M.handle_mouse_click()
    if not state_module.is_sidebar_open() then 
        return 
    end
    
    -- Get mouse position
    local mouse_pos = vim.fn.getmousepos()
    if not mouse_pos or mouse_pos.winid ~= state_module.get_win_id() then
        return -- Click not in sidebar window
    end
    
    -- Ensure we're in the sidebar window and set cursor position
    local sidebar_win = state_module.get_win_id()
    local was_in_sidebar = api.nvim_get_current_win() == sidebar_win
    
    if not was_in_sidebar then
        api.nvim_set_current_win(sidebar_win)
    end
    
    -- Set cursor to click position
    api.nvim_win_set_cursor(sidebar_win, {mouse_pos.line, 0})
    
    -- Call handle_selection normally
    M.handle_selection()
end

--- Cycle through show_path settings (yes -> no -> auto -> yes)
function M.cycle_show_path_setting()
    if not state_module.is_sidebar_open() then 
        return 
    end
    
    local current_setting = config_module.DEFAULTS.show_path
    local next_setting
    
    if current_setting == "yes" then
        next_setting = "no"
    elseif current_setting == "no" then
        next_setting = "auto"
    else -- "auto" or any other value
        next_setting = "yes"
    end
    
    -- Update the configuration
    config_module.DEFAULTS.show_path = next_setting
    
    -- Provide visual feedback
    local mode_descriptions = {
        yes = "Always show paths",
        no = "Never show paths", 
        auto = "Show paths only for conflicts"
    }
    
    vim.notify(string.format("Path display: %s (%s)", next_setting, mode_descriptions[next_setting] or "Unknown"), vim.log.levels.INFO)
    
    -- Refresh sidebar to show immediate changes
    M.refresh("path_display_cycle")
end

--- Cycle through show_history settings (auto -> yes -> no -> auto)
function M.cycle_show_history_setting()
    if not state_module.is_sidebar_open() then 
        return 
    end
    
    local groups = require('vertical-bufferline.groups')
    local new_setting = groups.cycle_show_history()
    
    -- Provide visual feedback
    local mode_descriptions = {
        auto = "Auto show history (≥3 files)",
        yes = "Always show history",
        no = "Never show history"
    }
    
    vim.notify(string.format("History display: %s (%s)", new_setting, mode_descriptions[new_setting] or "Unknown"), vim.log.levels.INFO)
    
    -- Refresh sidebar to show immediate changes
    M.refresh("history_display_cycle")
end

--- Handle buffer selection from sidebar
function M.handle_selection(captured_buffer_id, captured_line_number)
    if not state_module.is_sidebar_open() then 
        return 
    end
    
    -- Use passed parameters if available, otherwise fallback to cursor position
    local line_number = captured_line_number or api.nvim_win_get_cursor(state_module.get_win_id())[1]
    local bufnr = captured_buffer_id
    
    -- If no captured buffer ID provided, get it from current mapping (fallback for backwards compatibility)
    if not bufnr then
        local line_to_buffer = state_module.get_line_to_buffer_id()
        bufnr = line_to_buffer[line_number]
    end
    
    
    -- Check if this is a group header line or separator
    local group_header_lines = state_module.get_group_header_lines()
    
    for i, header_info in ipairs(group_header_lines) do
        if header_info and header_info.line == line_number - 1 then  -- Convert to 0-based
            if header_info.group_id then
                local target_group = groups.find_group_by_id(header_info.group_id)
                local group_name = target_group and target_group.name or "Unknown"
                
                groups.set_active_group(header_info.group_id)
                vim.notify("Switched to group: " .. group_name, vim.log.levels.INFO)
                return
            elseif header_info.type == "separator" or header_info.type == "separator_visual" then
                -- Ignore clicks on separator lines
                return
            end
        end
    end
    
    -- If no buffer mapping found, this might be a non-clickable line
    if not bufnr then
        return
    end
    
    -- Load buffer if not already loaded (for cross-group buffer access)
    if not api.nvim_buf_is_loaded(bufnr) then
        pcall(vim.fn.bufload, bufnr)
    end
    
    -- Check if this is a history line click for visual feedback
    local line_group_context = state_module.get_line_group_context()
    local clicked_group_id = line_group_context[line_number]
    local current_active_group = groups.get_active_group()
    local is_history_click = false
    
    if clicked_group_id and current_active_group and clicked_group_id == current_active_group.id then
        -- Check if this buffer is in the history
        local history = groups.get_group_history(current_active_group.id)
        for _, hist_buf_id in ipairs(history) do
            if hist_buf_id == bufnr then
                is_history_click = true
                break
            end
        end
    end
    
    -- Save current buffer state before switching (for within-group buffer state preservation)
    groups.save_current_buffer_state()
    
    -- STEP 1: Determine buffer group management
    local buffer_group = groups.find_buffer_group(bufnr)
    
    if clicked_group_id and current_active_group and clicked_group_id == current_active_group.id then
        -- Clicking within current active group - ensure buffer is in the group
        if not buffer_group or buffer_group.id ~= current_active_group.id then
            -- Add the buffer to current active group (useful for history items)
            groups.add_buffer_to_group(bufnr, current_active_group.id)
        end
    elseif buffer_group then
        -- Switch to the group containing this buffer
        if not current_active_group or current_active_group.id ~= buffer_group.id then
            groups.set_active_group(buffer_group.id)
        end
    else
        -- Buffer doesn't belong to any group - add it to current active group
        if current_active_group then
            groups.add_buffer_to_group(bufnr, current_active_group.id)
        end
    end
    
    -- STEP 2: Find the main window (not the sidebar) and switch to buffer
    local main_win_id = nil
    for _, win_id in ipairs(api.nvim_list_wins()) do
        if win_id ~= state_module.get_win_id() and api.nvim_win_is_valid(win_id) then
            -- Check if this window is not a floating window or special window
            local win_config = api.nvim_win_get_config(win_id)
            if win_config.relative == "" then  -- Not a floating window
                main_win_id = win_id
                break
            end
        end
    end

    if main_win_id then
        -- Switch to the main window and set the buffer there
        local success, err = pcall(function()
            api.nvim_set_current_win(main_win_id)
            api.nvim_set_current_buf(bufnr)
        end)
        if not success then
            vim.notify("Error switching to buffer: " .. err, vim.log.levels.ERROR)
            return
        end
    else
        -- Fallback: if no main window found, create a new split
        local success, err = pcall(function()
            vim.cmd("wincmd p")  -- Go to previous window
            api.nvim_set_current_buf(bufnr)
        end)
        if not success then
            vim.notify("Error switching to buffer: " .. err, vim.log.levels.ERROR)
            return
        end
    end

    -- STEP 3: Update group's current_buffer tracking
    -- Get the updated active group (might have changed after group switching)
    local updated_active_group = groups.get_active_group()
    if updated_active_group then
        updated_active_group.current_buffer = bufnr
    end
    
    -- Provide visual feedback for history clicks
    if is_history_click then
        local buf_name = api.nvim_buf_get_name(bufnr)
        local filename = vim.fn.fnamemodify(buf_name, ":t")
        vim.notify("Switched to recent file: " .. filename, vim.log.levels.INFO)
    end
    
    -- Restore buffer state for the newly selected buffer (for within-group state preservation)
    vim.schedule(function()
        groups.restore_buffer_state_for_current_group(bufnr)
    end)
end


--- Remove buffer from current group via sidebar
function M.remove_from_group()
    if not state_module.is_sidebar_open() then return end
    local line_number = api.nvim_win_get_cursor(state_module.get_win_id())[1]
    local bufnr = state_module.get_buffer_for_line(line_number)
    if bufnr and api.nvim_buf_is_valid(bufnr) then
        -- Find which group contains this buffer
        local buffer_group = groups.find_buffer_group(bufnr)
        if buffer_group then
            -- Remove buffer from the group it belongs to
            local success = groups.remove_buffer_from_group(bufnr, buffer_group.id)
            if success then
                vim.notify("Buffer removed from group: " .. buffer_group.name, vim.log.levels.INFO)
                
                -- If this was the active group, sync the change to bufferline
                local active_group = groups.get_active_group()
                if active_group and active_group.id == buffer_group.id then
                    -- Pause sync, update bufferline, then resume sync
                    bufferline_integration.set_sync_target(nil)
                    bufferline_integration.set_bufferline_buffers(active_group.buffers)
                    bufferline_integration.set_sync_target(active_group.id)
                end
                
                -- Refresh display
                vim.schedule(function()
                    M.refresh("buffer_remove")
                end)
            end
        else
            vim.notify("Buffer not found in any group", vim.log.levels.WARN)
        end
    end
end

--- Smart close buffer with group-aware logic
function M.smart_close_buffer()
    if not state_module.is_sidebar_open() then return end
    local line_number = api.nvim_win_get_cursor(state_module.get_win_id())[1]
    local bufnr = state_module.get_buffer_for_line(line_number)
    if bufnr and api.nvim_buf_is_valid(bufnr) then
        -- Save current window before calling smart_close_buffer
        local current_win = api.nvim_get_current_win()
        local sidebar_win = state_module.get_win_id()
        
        -- Switch to main window before closing buffer to avoid sidebar buffer change
        local main_win_id = nil
        for _, win_id in ipairs(api.nvim_list_wins()) do
            if win_id ~= sidebar_win and api.nvim_win_is_valid(win_id) then
                local win_config = api.nvim_win_get_config(win_id)
                if win_config.relative == "" then  -- Not a floating window
                    main_win_id = win_id
                    break
                end
            end
        end
        
        if main_win_id then
            api.nvim_set_current_win(main_win_id)
        end
        
        -- Now safely call smart_close_buffer
        bufferline_integration.smart_close_buffer(bufnr)
        
        -- Restore original window (sidebar)
        if api.nvim_win_is_valid(current_win) then
            api.nvim_set_current_win(current_win)
        end
        
        -- Add delayed cleanup and refresh
        vim.schedule(function()
            groups.cleanup_invalid_buffers()
            M.refresh("buffer_cleanup")
        end)
    end
end

--- Toggle expand all groups mode
function M.toggle_expand_all()
    local new_status = state_module.toggle_expand_all_groups()
    local status = new_status and "enabled" or "disabled"
    vim.notify("Expand all groups mode " .. status, vim.log.levels.INFO)

    -- Refresh display
    if state_module.is_sidebar_open() then
        vim.schedule(function()
            M.refresh("expand_toggle")
        end)
    end
end

--- Hook into bufferline's UI refresh to mirror its state
local function setup_bufferline_hook()
    -- Try to hook into bufferline's UI refresh
    local bufferline_ui = require('bufferline.ui')
    local original_refresh = bufferline_ui.refresh

    bufferline_ui.refresh = function(...)
        local result = original_refresh(...)
        -- Immediately update our sidebar synchronously during picking
        if state_module.is_sidebar_open() then
            local bufferline_state = require('bufferline.state')
            if bufferline_state.is_picking then
                -- Force immediate refresh during picking mode
                M.refresh("picking_mode")
                -- Apply highlights multiple times to fight bufferline's overwrites
                vim.schedule(function()
                    M.apply_picking_highlights()
                end)
                vim.cmd("redraw!")  -- Force immediate redraw
            else
                -- Use schedule for normal updates
                vim.schedule(function()
                    M.refresh("bufferline_hook")
                end)
            end
        end
        return result
    end
end

-- Plugin initialization function (called on load)
local function initialize_plugin()
    -- Setup commands
    commands.setup()

    -- Initialize group functionality
    groups.setup({
        auto_create_groups = config_module.DEFAULTS.auto_create_groups,
        auto_add_new_buffers = config_module.DEFAULTS.auto_add_new_buffers
    })

    -- Enable bufferline integration
    bufferline_integration.enable()

    -- Initialize session module
    session.setup({
        auto_save = config_module.DEFAULTS.auto_save,
        auto_load = config_module.DEFAULTS.auto_load,
    })
    
    -- Setup global variable session integration (for mini.sessions and native mksession)
    session.setup_session_integration()

    -- Setup global autocmds (not dependent on sidebar state)
    api.nvim_command("augroup VerticalBufferlineGlobal")
    api.nvim_command("autocmd!")
    -- TEMP DISABLED: api.nvim_command("autocmd BufEnter,BufDelete,BufWipeout * lua require('vertical-bufferline').refresh_if_open()")
    api.nvim_command("autocmd BufWritePost * lua require('vertical-bufferline').refresh_if_open()")
    api.nvim_command("autocmd WinClosed * lua require('vertical-bufferline').check_quit_condition()")
    api.nvim_command("augroup END")

    -- Setup extended picking mode hooks
    setup_extended_picking_hooks()
    
    -- Setup bufferline hooks
    setup_bufferline_hook()

    -- Setup highlights
    setup_highlights()
    setup_pick_highlights()
end

--- Wrapper function to refresh only when sidebar is open
function M.refresh_if_open()
    if state_module.is_sidebar_open() then
        M.refresh("autocmd_trigger")
    end
end

--- Check if should exit nvim (when only sidebar window remains)
function M.check_quit_condition()
    if not state_module.is_sidebar_open() then
        return
    end

    -- Delayed check to ensure window close events are processed
    vim.schedule(function()
        local all_windows = api.nvim_list_wins()
        local non_sidebar_windows = 0
        local sidebar_win_id = state_module.get_win_id()

        -- Count non-sidebar windows
        for _, win_id in ipairs(all_windows) do
            if api.nvim_win_is_valid(win_id) and win_id ~= sidebar_win_id then
                non_sidebar_windows = non_sidebar_windows + 1
            end
        end

        -- If only sidebar window remains, auto-exit nvim
        if non_sidebar_windows == 0 and #all_windows == 1 then
            vim.cmd("qall")
        end
    end)
end

--- Toggles the visibility of the sidebar.
function M.toggle()
    if state_module.is_sidebar_open() then
        M.close_sidebar()
    else
        open_sidebar()

        -- Manually add existing buffers to default group
        -- Use multiple delayed attempts to ensure buffers are correctly identified
        for _, delay in ipairs(config_module.UI.STARTUP_DELAYS) do
            vim.defer_fn(function()
                -- If loading session, skip auto-add to avoid conflicts
                if state_module.is_session_loading() then
                    return
                end

                local all_buffers = vim.api.nvim_list_bufs()
                local default_group = groups.get_active_group()
                if default_group then
                    local added_count = 0
                    for _, buf in ipairs(all_buffers) do
                        if vim.api.nvim_buf_is_valid(buf) then
                            local buf_name = vim.api.nvim_buf_get_name(buf)
                            local buf_type = vim.api.nvim_buf_get_option(buf, 'buftype')
                            -- Only add normal file buffers not already in groups
                            if buf_name ~= "" and not buf_name:match("^%s*$") and
                               buf_type == config_module.SYSTEM.EMPTY_BUFTYPE and
                               not vim.tbl_contains(default_group.buffers, buf) then
                                groups.add_buffer_to_group(buf, default_group.id)
                                added_count = added_count + 1
                            end
                        end
                    end
                    if added_count > 0 then
                        -- Refresh interface
                        M.refresh("auto_add_buffers")
                    end
                end
            end, delay)
        end

        -- Ensure initial state displays correctly
        vim.schedule(function()
            M.refresh("initialization")
        end)
    end
end

-- Export group management functions
M.groups = groups
M.commands = commands
M.bufferline_integration = bufferline_integration
M.session = session
M.state = state_module.get_raw_state()  -- Export state for session module use

-- Convenient group operation functions
M.create_group = function(name)
    return commands.create_group({args = name or ""})
end
M.delete_current_group = function() commands.delete_current_group() end
M.switch_to_next_group = function() commands.next_group() end
M.switch_to_prev_group = function() commands.prev_group() end
M.add_current_buffer_to_group = function(group_name)
    commands.add_buffer_to_group({args = group_name})
end
M.move_group_up = function() commands.move_group_up() end
M.move_group_down = function() commands.move_group_down() end
M.clear_history = function(group_id) 
    local groups = require('vertical-bufferline.groups')
    local success = groups.clear_group_history(group_id)
    if success then
        M.refresh("clear_history")
    end
    return success
end
M.cycle_show_path = M.cycle_show_path_setting
M.cycle_show_history = M.cycle_show_history_setting

--- Setup function for user configuration (e.g., from lazy.nvim)
function M.setup(user_config)
    if user_config then
        -- Merge user configuration with defaults
        for key, value in pairs(user_config) do
            if config_module.DEFAULTS[key] ~= nil then
                config_module.DEFAULTS[key] = value
            end
        end
        
        -- Handle nested session configuration
        if user_config.session then
            for key, value in pairs(user_config.session) do
                if config_module.DEFAULTS.session[key] ~= nil then
                    config_module.DEFAULTS.session[key] = value
                end
            end
        end
    end
end

--- Switch to history file by position (1-9)
--- @param position number History position (1-9)
--- @return boolean success
function M.switch_to_history_file(position)
    local groups = require('vertical-bufferline.groups')
    local active_group = groups.get_active_group()
    if not active_group then
        vim.notify("No active group", vim.log.levels.WARN)
        return false
    end
    
    local history = groups.get_group_history(active_group.id)
    if not history or #history <= 1 then
        vim.notify("No history available in current group", vim.log.levels.WARN)
        return false
    end
    
    -- Skip first item (current buffer) and access history items
    -- position 1 -> history[2], position 2 -> history[3], etc.
    local history_index = position + 1
    
    if history_index > #history then
        vim.notify(string.format("History position %d not available (1-%d)", position, #history - 1), vim.log.levels.WARN)
        return false
    end
    
    local buffer_id = history[history_index]
    if not buffer_id or not api.nvim_buf_is_valid(buffer_id) then
        vim.notify("History buffer is no longer valid", vim.log.levels.WARN)
        return false
    end
    
    -- Load buffer if not already loaded
    if not api.nvim_buf_is_loaded(buffer_id) then
        pcall(vim.fn.bufload, buffer_id)
    end
    
    -- Save current buffer state before switching
    groups.save_current_buffer_state()
    
    -- Find the main window and switch to buffer
    local main_win_id = nil
    for _, win_id in ipairs(api.nvim_list_wins()) do
        if win_id ~= state_module.get_win_id() and api.nvim_win_is_valid(win_id) then
            local win_config = api.nvim_win_get_config(win_id)
            if win_config.relative == "" then  -- Not a floating window
                main_win_id = win_id
                break
            end
        end
    end
    
    if main_win_id then
        local success, err = pcall(function()
            api.nvim_set_current_win(main_win_id)
            api.nvim_set_current_buf(buffer_id)
        end)
        if not success then
            vim.notify("Error switching to history buffer: " .. err, vim.log.levels.ERROR)
            return false
        end
    else
        vim.notify("No main window found", vim.log.levels.ERROR)
        return false
    end
    
    -- Update group's current_buffer tracking
    active_group.current_buffer = buffer_id
    
    -- Restore buffer state
    vim.schedule(function()
        groups.restore_buffer_state_for_current_group(buffer_id)
    end)
    
    return true
end

-- Initialize immediately on plugin load
initialize_plugin()

-- Save global instance and set loaded flag
_G._vertical_bufferline_init_loaded = true
_G._vertical_bufferline_init_instance = M

return M
