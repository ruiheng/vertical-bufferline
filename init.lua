-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/init.lua

---@class VerticalBufferline
---@field setup fun(config?: table): nil Setup the plugin with configuration
---@field toggle fun(): nil Toggle the sidebar on/off
---@field refresh fun(reason?: string): nil Refresh the sidebar display
---@field toggle_expand_all fun(): nil Toggle showing all groups expanded
---@field create_group fun(name?: string): table|nil Create a new buffer group
---@field delete_current_group fun(): nil Delete the currently active group
---@field switch_to_next_group fun(): nil Switch to the next group
---@field switch_to_prev_group fun(): nil Switch to the previous group
---@field add_current_buffer_to_group fun(group_name: string): nil Add current buffer to a group
---@field move_group_up fun(): nil Move current group up in the list
---@field move_group_down fun(): nil Move current group down in the list
---@field clear_history fun(group_id?: number|string): boolean Clear group history
---@field copy_groups_to_register fun(): nil Copy current window's groups to default register
---@field switch_to_history_file fun(position: number): boolean Switch to a file from history
---@field switch_to_group_buffer fun(position: number): boolean Switch to a file by group position
---@field groups table Group management functions
---@field commands table Command functions
---@field session table Session management functions

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
local logger = require('vertical-bufferline.logger')
local layout = require('vertical-bufferline.layout')

local capture_pick_display_state
local update_pick_display
local restore_pick_display

if not package.preload["telescope._extensions.vertical_bufferline"] then
    package.preload["telescope._extensions.vertical_bufferline"] = function()
        return require('vertical-bufferline.telescope_extension')
    end
end

-- Namespace for our highlights
local ns_id = api.nvim_create_namespace("VerticalBufferline")
local pick_input_ns_id = api.nvim_create_namespace("VerticalBufferlinePickInput")

local switch_to_buffer_in_main_window

-- Extended picking mode state
local extended_picking_state = {
    active = false,
    mode_type = nil, -- "switch" or "close"
    extended_hints = {}, -- line_num -> hint_char mapping
    bufferline_used_chars = {},
    original_commands = {}, -- Store original commands for restoration
    saved_offset = 0  -- Save scroll offset before entering pick mode
}

local function is_horizontal_position(position)
    return layout.is_horizontal(position or config_module.settings.position)
end

local menu_state = {
    win_id = nil,
    buf_id = nil,
    prev_win_id = nil,
    augroup = nil,
    title = nil,
    items = nil,
    filtered_items = nil,
    include_hint = false,
    title_offset = 0,
    max_digits = 1,
    input_buffer = "",
    input_mode = nil,
    current_buffer_id = nil,
}

local function close_menu(opts)
    opts = opts or {}
    local restore_prev = opts.restore_prev ~= false
    if menu_state.augroup then
        pcall(api.nvim_del_augroup_by_id, menu_state.augroup)
        menu_state.augroup = nil
    end
    if menu_state.win_id and api.nvim_win_is_valid(menu_state.win_id) then
        api.nvim_win_close(menu_state.win_id, true)
    end
    if menu_state.buf_id and api.nvim_buf_is_valid(menu_state.buf_id) then
        api.nvim_buf_delete(menu_state.buf_id, { force = true })
    end
    if restore_prev and menu_state.prev_win_id and api.nvim_win_is_valid(menu_state.prev_win_id) then
        api.nvim_set_current_win(menu_state.prev_win_id)
    end
    menu_state.win_id = nil
    menu_state.buf_id = nil
    menu_state.prev_win_id = nil
    menu_state.title = nil
    menu_state.items = nil
    menu_state.filtered_items = nil
    menu_state.include_hint = false
    menu_state.title_offset = 0
    menu_state.max_digits = 1
    menu_state.input_buffer = ""
    menu_state.input_mode = nil
    menu_state.current_buffer_id = nil
end

-- Setup highlight groups function
local function setup_highlights()
    -- Base theme colors for composing highlights
    local pmenusel_attrs = vim.api.nvim_get_hl(0, {name = 'PmenuSel'})
    local pmenu_attrs = vim.api.nvim_get_hl(0, {name = 'Pmenu'})
    local title_attrs = vim.api.nvim_get_hl(0, {name = 'Title'})
    local comment_attrs = vim.api.nvim_get_hl(0, {name = 'Comment'})
    local directory_attrs = vim.api.nvim_get_hl(0, {name = 'Directory'})
    local operator_attrs = vim.api.nvim_get_hl(0, {name = 'Operator'})
    local warning_attrs = vim.api.nvim_get_hl(0, {name = 'WarningMsg'})
    local special_attrs = vim.api.nvim_get_hl(0, {name = 'Special'})
    local number_attrs = vim.api.nvim_get_hl(0, {name = 'Number'})
    local cursorline_attrs = vim.api.nvim_get_hl(0, {name = 'CursorLine'})
    local statusline_attrs = vim.api.nvim_get_hl(0, {name = 'StatusLine'})
    local normal_attrs = vim.api.nvim_get_hl(0, {name = 'Normal'})
    local current_bg = pmenusel_attrs.bg or cursorline_attrs.bg

    local function normalize_hex(color)
        if type(color) ~= "string" then
            return nil
        end
        local hex = color:match("^#?%x%x%x%x%x%x$")
        if not hex then
            return nil
        end
        if hex:sub(1, 1) ~= "#" then
            hex = "#" .. hex
        end
        return hex:lower()
    end

    local function tweak_hex(color, delta)
        local hex = normalize_hex(color)
        if not hex then
            return nil
        end
        local r = tonumber(hex:sub(2, 3), 16)
        local g = tonumber(hex:sub(4, 5), 16)
        local b = tonumber(hex:sub(6, 7), 16)
        local function clamp(value)
            return math.max(0, math.min(255, value))
        end
        r = clamp(r + delta)
        g = clamp(g + delta)
        b = clamp(b + delta)
        return string.format("#%02x%02x%02x", r, g, b)
    end

    local normalized_current_bg = normalize_hex(current_bg)
    local bar_bg = nil
    local candidates = {
        pmenu_attrs.bg,
        statusline_attrs.bg,
        cursorline_attrs.bg,
        normal_attrs.bg,
    }
    for _, bg in ipairs(candidates) do
        local normalized = normalize_hex(bg)
        if normalized and normalized ~= normalized_current_bg then
            bar_bg = normalized
            break
        end
    end
    if not bar_bg then
        if normalized_current_bg then
            bar_bg = tweak_hex(normalized_current_bg, -20)
        else
            bar_bg = config_module.COLORS.DARK_GRAY
        end
    end

    -- Buffer state highlights using semantic nvim highlight groups for theme compatibility
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.CURRENT, { bg = current_bg })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.VISIBLE, { link = "PmenuSel" })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.INACTIVE, { link = "Comment" })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.MODIFIED, { link = "WarningMsg", italic = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.MODIFIED_CURRENT, {
        fg = warning_attrs.fg or config_module.COLORS.YELLOW,
        bg = current_bg,
        italic = true
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PIN, { link = "Special" })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PIN_CURRENT, {
        fg = special_attrs.fg or config_module.COLORS.CYAN,
        bg = current_bg
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.BAR, {
        bg = bar_bg
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PLACEHOLDER, {
        bg = config_module.COLORS.RED
    })
    
    -- Path highlights - should be subtle and low-key
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PATH, { link = "Comment", italic = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PATH_CURRENT, { link = "NonText", italic = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PATH_VISIBLE, { link = "Comment", italic = true })
    
    -- Prefix highlights - for minimal prefixes, should be consistent
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PREFIX, { link = "Comment", italic = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PREFIX_CURRENT, {
        fg = directory_attrs.fg or title_attrs.fg or config_module.COLORS.BLUE,
        bg = current_bg,
        bold = true
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.PREFIX_VISIBLE, { link = "String", italic = true })
    
    -- Filename highlights - should be consistent between prefixed and non-prefixed
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.FILENAME, { link = "Normal" })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.FILENAME_CURRENT, {
        fg = title_attrs.fg or config_module.COLORS.WHITE,
        bg = current_bg,
        bold = true
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.FILENAME_VISIBLE, { link = "String", bold = true })

    -- Buffer numbering highlights - keep distinct from filenames
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.BUFFER_NUMBER, { link = "Number" })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.BUFFER_NUMBER_VISIBLE, { link = "Number", bold = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.BUFFER_NUMBER_CURRENT, {
        fg = number_attrs.fg or title_attrs.fg or config_module.COLORS.WHITE,
        bg = current_bg,
        bold = true
    })
    
    -- Dual numbering highlights - different styles for easy distinction
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.NUMBER_LOCAL, { link = "Number", bold = true })      -- Local: bright, bold
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.NUMBER_GLOBAL, { link = "Comment" })                -- Global: subdued
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.NUMBER_SEPARATOR, { link = "Operator" })            -- Separator: distinct
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.NUMBER_SEPARATOR_CURRENT, {
        fg = operator_attrs.fg or comment_attrs.fg,
        bg = current_bg
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.NUMBER_HIDDEN, { link = "NonText" })                -- Hidden: very subtle
    
    -- Group header highlights - use semantic colors for theme compatibility
    -- Get background from PmenuSel/Pmenu but foreground/style from Title/Comment
    
    -- Subtle group header highlights for less eye-catching appearance
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_ACTIVE, {
        fg = config_module.COLORS.BLUE,
        bold = true,
        default = true
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_INACTIVE, {
        fg = comment_attrs.fg or pmenu_attrs.fg,
        default = true
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_NUMBER, { link = "Number", bold = true, default = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_SEPARATOR, { link = "Comment", default = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_MARKER, { link = "Special", bold = true, default = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_TAB_ACTIVE, {
        fg = pmenusel_attrs.fg or title_attrs.fg,
        bg = pmenusel_attrs.bg,
        bold = true,
        default = true
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_TAB_INACTIVE, {
        fg = pmenu_attrs.fg or comment_attrs.fg,
        bg = pmenu_attrs.bg,
        default = true
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.SECTION_LABEL_ACTIVE, {
        fg = title_attrs.fg or config_module.COLORS.BLUE,
        bold = true,
        default = true
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.SECTION_LABEL_INACTIVE, {
        fg = comment_attrs.fg or pmenu_attrs.fg,
        default = true
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.HORIZONTAL_NUMBER, { link = "Number", default = true })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.HORIZONTAL_NUMBER_CURRENT, {
        fg = pmenusel_attrs.fg or title_attrs.fg,
        bold = true,
        default = true
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.HORIZONTAL_CURRENT, {
        fg = pmenusel_attrs.fg or title_attrs.fg,
        bg = pmenusel_attrs.bg,
        bold = true,
        default = true
    })
    api.nvim_set_hl(0, config_module.HIGHLIGHTS.MENU_INPUT_PREFIX, { link = "Comment", default = true })

    -- Recent Files header highlight removed - kept subtle without special highlighting
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
    if not bufferline_integration.is_available() then
        return used_chars
    end

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

local function is_buffer_pinned(buf_id)
    if bufferline_integration.is_available() then
        local ok_groups, bufferline_groups = pcall(require, "bufferline.groups")
        if ok_groups and bufferline_groups and bufferline_groups._is_pinned then
            return bufferline_groups._is_pinned({ id = buf_id }) and true or false
        end
    end
    return state_module.is_buffer_pinned(buf_id)
end

local function get_pin_icon()
    if bufferline_integration.is_available() then
        local ok_groups, bufferline_groups = pcall(require, "bufferline.groups")
        if ok_groups and bufferline_groups and bufferline_groups.get_by_id then
            local pinned_group = bufferline_groups.get_by_id("pinned")
            if pinned_group and pinned_group.icon and pinned_group.icon ~= "" then
                return pinned_group.icon .. " "
            end
        end
    end
    return config_module.UI.PIN_MARKER
end

local function get_pinned_buffer_ids()
    local pinned = {}
    local utils_module = require('vertical-bufferline.utils')
    for _, buf_id in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_valid(buf_id)
            and not utils_module.is_special_buffer(buf_id)
            and is_buffer_pinned(buf_id) then
            table.insert(pinned, buf_id)
        end
    end
    return pinned
end

-- Extended picking mode implementation
local DEFAULT_PICK_CHARS = "asdfjklghqwertyuiopzxcvbnmASDFJKLGHQWERTYUIOPZXCVBNM"

local function get_pick_chars()
    local chars = config_module.settings.pick_chars
    if type(chars) ~= "string" or chars == "" then
        return DEFAULT_PICK_CHARS
    end
    return chars
end

local function get_pick_char_sets()
    local base_chars = get_pick_chars()
    local prefix_chars = {}
    for i = 1, #base_chars do
        local ch = base_chars:sub(i, i)
        if not ch:match("%d") then
            table.insert(prefix_chars, ch)
        end
    end
    if #prefix_chars == 0 then
        base_chars = DEFAULT_PICK_CHARS
        prefix_chars = {}
        for i = 1, #base_chars do
            local ch = base_chars:sub(i, i)
            if not ch:match("%d") then
                table.insert(prefix_chars, ch)
            end
        end
    end
    return base_chars, prefix_chars
end

local function get_pick_char_lists()
    local base_chars, prefix_chars = get_pick_char_sets()
    local base_list = {}
    local base_set = {}
    for i = 1, #base_chars do
        local ch = base_chars:sub(i, i)
        table.insert(base_list, ch)
        base_set[ch] = true
    end
    local prefix_list = {}
    for _, ch in ipairs(prefix_chars) do
        if base_set[ch] then
            table.insert(prefix_list, ch)
        end
    end
    return base_list, prefix_list
end

local function generate_variable_pick_char(index, base_list, prefix_list)
    if type(index) ~= "number" or index < 1 then
        return ""
    end
    local base = #base_list
    local prefix_base = #prefix_list
    if base == 0 or prefix_base == 0 then
        return ""
    end

    local remaining = index
    local length = 2
    while true do
        local count = prefix_base * (base ^ (length - 1))
        if remaining <= count then
            break
        end
        remaining = remaining - count
        length = length + 1
    end

    local remainder = remaining - 1
    local first_index = math.floor(remainder / (base ^ (length - 1))) + 1
    remainder = remainder % (base ^ (length - 1))

    local chars = { prefix_list[first_index] }
    for position = 2, length do
        local power = base ^ (length - position)
        local idx = math.floor(remainder / power) + 1
        remainder = remainder % power
        table.insert(chars, base_list[idx])
    end

    return table.concat(chars)
end

-- Generate multi-character pick char for overflow cases
local function generate_multi_char_pick_char(overflow_index)
    local base_list, prefix_list = get_pick_char_lists()
    return generate_variable_pick_char(overflow_index, base_list, prefix_list)
end

-- Generate buffer pick chars based on buffer_id (for direct insertion during rendering)
-- @param all_group_buffers table List of {buffer_id, group_id} tuples in render order
-- @param bufferline_components table Bufferline components with existing pick chars
-- @param active_group_id string|nil Active group ID
-- @param include_active_group boolean Whether to generate pick chars for active group buffers
-- @return table buffer_id -> pick_char mapping
local function generate_buffer_pick_chars(all_group_buffers, bufferline_components, active_group_id, include_active_group)
    local buffer_hints = {}
    local used_chars = {}

    -- Reserve fixed pick chars for pinned buffers
    local pinned_pick_chars = state_module.get_pinned_pick_chars() or {}
    for buf_id, pick_char in pairs(pinned_pick_chars) do
        if type(pick_char) == "string" and pick_char ~= "" and #pick_char == 1 then
            if not used_chars[pick_char] then
                used_chars[pick_char] = true
                buffer_hints[buf_id] = pick_char
            end
        end
    end

    -- Extract existing bufferline pick chars (these take priority)
    for _, component in ipairs(bufferline_components or {}) do
        local ok, element = pcall(function() return component:as_element() end)
        local letter = nil
        if ok and element and element.letter then
            letter = element.letter
        elseif component.letter then
            letter = component.letter
        end

        if letter and not buffer_hints[component.id] and not used_chars[letter] then
            used_chars[letter] = true
            buffer_hints[component.id] = letter
        end
    end

    -- Generate available character pool
    local _, prefix_chars = get_pick_char_sets()
    local available_chars = {}
    for _, char in ipairs(prefix_chars) do
        if not used_chars[char] then
            table.insert(available_chars, char)
        end
    end

    -- If no bufferline pick chars exist and we should include active group, reset to allow all chars
    if include_active_group and next(buffer_hints) == nil then
        used_chars = {}
        available_chars = {}
        local _, reset_prefix_chars = get_pick_char_sets()
        for _, char in ipairs(reset_prefix_chars) do
            table.insert(available_chars, char)
        end
    end

    -- Assign pick chars to buffers that don't have them yet
    local char_index = 1
    local overflow_index = 1
    local overflow_index = 1
    local overflow_index = 1
    for _, entry in ipairs(all_group_buffers) do
        local buffer_id = entry.buffer_id
        local group_id = entry.group_id

        -- Skip if buffer already has a pick char from bufferline
        if buffer_hints[buffer_id] then
            goto continue
        end

        -- Skip active group buffers unless include_active_group is true
        if not include_active_group and group_id == active_group_id then
            goto continue
        end

        -- Assign pick char
        if char_index <= #available_chars then
            local hint_char = available_chars[char_index]
            buffer_hints[buffer_id] = hint_char
            used_chars[hint_char] = true
            char_index = char_index + 1
        else
            -- Handle overflow: assign multi-character pick chars (variable length)
            while true do
                local multi_char_hint = generate_multi_char_pick_char(overflow_index)
                overflow_index = overflow_index + 1
                if multi_char_hint == "" then
                    break
                end
                if not used_chars[multi_char_hint] then
                    buffer_hints[buffer_id] = multi_char_hint
                    used_chars[multi_char_hint] = true
                    break
                end
            end
        end

        ::continue::
    end

    return buffer_hints
end

-- Legacy function for backward compatibility (used by highlight system)
local function generate_extended_pick_chars(bufferline_components, line_to_buffer, line_group_context, active_group_id, include_active_group)
    local line_hints = {}
    local hint_lines = {}
    local bufferline_hints = {}

    -- Extract existing bufferline pick chars
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
    local _, prefix_chars = get_pick_char_sets()
    local available_chars = {}
    for _, char in ipairs(prefix_chars) do
        if not used_chars[char] then
            table.insert(available_chars, char)
        end
    end

    -- No bufferline: reset used_chars so we can assign pick chars to all lines
    if include_active_group and next(bufferline_hints) == nil then
        used_chars = {}
    end

    -- Assign pick chars to non-active group lines with deterministic ordering
    local char_index = 1
    local overflow_index = 1

    -- Create sorted list of line numbers for deterministic ordering
    local sorted_lines = {}
    for line_num, buffer_id in pairs(line_to_buffer) do
        local line_group_id = line_group_context[line_num]
        if include_active_group or line_group_id ~= active_group_id then
            table.insert(sorted_lines, line_num)
        end
    end
    table.sort(sorted_lines)

    -- Assign pick chars in deterministic order
    for _, line_num in ipairs(sorted_lines) do
        if char_index <= #available_chars then
            local hint_char = available_chars[char_index]
            line_hints[line_num] = hint_char
            hint_lines[hint_char] = line_num
            used_chars[hint_char] = true
            char_index = char_index + 1
        else
            -- Handle overflow: assign multi-character pick chars (variable length)
            while true do
                local multi_char_hint = generate_multi_char_pick_char(overflow_index)
                overflow_index = overflow_index + 1
                if multi_char_hint == "" then
                    break
                end
                if not used_chars[multi_char_hint] and not hint_lines[multi_char_hint] then
                    line_hints[line_num] = multi_char_hint
                    hint_lines[multi_char_hint] = line_num
                    used_chars[multi_char_hint] = true
                    break
                end
            end
        end
    end

    return line_hints, hint_lines, bufferline_hints
end

-- Helper function to find line number by pick char
local function find_line_by_pick_char(hint_char)
    local extended_picking = state_module.get_extended_picking_state()
    return extended_picking.hint_lines[hint_char]
end

-- Helper function to check if a prefix matches any pick char
local function has_pick_char_prefix(prefix)
    local extended_picking = state_module.get_extended_picking_state()
    for hint_char, _ in pairs(extended_picking.hint_lines) do
        if hint_char:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function get_pick_char_match(prefix)
    local extended_picking = state_module.get_extended_picking_state()
    local match = nil
    local count = 0
    local matched_buffers = {}
    local line_to_buffer = state_module.get_line_to_buffer_id()
    local line_hints = extended_picking.line_hints or {}
    local hint_lines_are_lines = next(line_hints) ~= nil

    for hint_char, line_or_buf in pairs(extended_picking.hint_lines) do
        if hint_char:sub(1, #prefix) == prefix then
            local buffer_id = nil
            if hint_lines_are_lines then
                buffer_id = line_to_buffer and line_to_buffer[line_or_buf] or nil
            else
                buffer_id = line_or_buf
            end
            if buffer_id and not matched_buffers[buffer_id] then
                matched_buffers[buffer_id] = true
                count = count + 1
                if count == 1 then
                    match = hint_char
                else
                    match = nil
                    break
                end
            end
        end
    end
    return count, match
end

M._get_pick_char_match = get_pick_char_match

-- Read user input for pick mode
local function read_pick_input()
    local input = ""
    local extended_picking = state_module.get_extended_picking_state()
    local hint_lines = extended_picking.hint_lines or {}

    while true do
        local char = vim.fn.getcharstr()
        if char == "" then
            return nil
        end
        if char == "\027" then  -- ESC
            return nil
        end
        if char == "\r" or char == "\n" then
            if hint_lines[input] then
                return input
            end
            goto continue
        end
        if #char ~= 1 then
            goto continue
        end
        local pick_chars = get_pick_chars()
        if not pick_chars:find(char, 1, true) then
            goto continue
        end
        if input == "" then
            local _, prefix_chars = get_pick_char_sets()
            local is_prefix = false
            for _, prefix_char in ipairs(prefix_chars) do
                if prefix_char == char then
                    is_prefix = true
                    break
                end
            end
            if not is_prefix then
                goto continue
            end
        end
        input = input .. char
        update_pick_display(input)
        local match_count, match_hint = get_pick_char_match(input)
        if match_count == 1 and match_hint then
            return match_hint
        end
        if match_count == 0 then
            return input
        end
        ::continue::
    end
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
        -- Update history with the selected buffer
        groups.sync_group_history_with_current(target_group_id, buffer_id)
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
        -- This was the only group with this buffer, safely close it
        bufferline_integration.smart_close_buffer(buffer_id)
    end

    -- Refresh the display
    vim.schedule(function()
        M.refresh("buffer_close")
    end)
end

-- Exit extended picking mode
local function exit_extended_picking()
    extended_picking_state.active = false
    extended_picking_state.mode_type = nil
    extended_picking_state.extended_hints = {}
    extended_picking_state.bufferline_used_chars = {}
    extended_picking_state.saved_offset = 0  -- Clear saved offset

    -- Deactivate extended picking in state module
    state_module.set_extended_picking_active(false)
    state_module.set_extended_picking_input_prefix("")
    restore_pick_display()
    update_pick_display("")
    -- DON'T reset was_picking here - let detect_and_manage_picking_mode handle it
    -- This ensures proper cleanup in the next refresh cycle
end

-- Key handling for extended picking
local function handle_extended_picking_key(key)
    local extended_picking = state_module.get_extended_picking_state()
    if not extended_picking.is_active then
        return false
    end

    -- Look up buffer_id from hint_lines (letter -> buffer_id mapping)
    local buffer_id = extended_picking.hint_lines[key]
    if not buffer_id or not api.nvim_buf_is_valid(buffer_id) then
        return false
    end

    if is_buffer_pinned(buffer_id) then
        if extended_picking.pick_mode == "switch" then
            if switch_to_buffer_in_main_window and switch_to_buffer_in_main_window(buffer_id, "Error switching to pinned buffer") then
                vim.schedule(function()
                    M.refresh("pinned_pick_switch")
                end)
                return true
            end
        end
        return false
    end

    -- Find which group this buffer belongs to
    local target_group_id = nil
    for _, group in ipairs(groups.get_all_groups()) do
        if vim.tbl_contains(group.buffers or {}, buffer_id) then
            target_group_id = group.id
            break
        end
    end

    if not target_group_id then
        return false
    end

    -- Perform the action based on mode type
    if extended_picking.pick_mode == "switch" then
        switch_to_buffer_and_group(buffer_id, target_group_id)
    elseif extended_picking.pick_mode == "close" then
        close_buffer_from_group(buffer_id, target_group_id)
    end

    return true
end

-- Pick highlights matching bufferline's style
-- Copy the exact colors from BufferLine groups
local function setup_pick_highlights()
    -- Get the actual BufferLine highlight groups
    local bufferline_pick = vim.api.nvim_get_hl(0, {name = "BufferLinePick"})
    local bufferline_pick_visible = vim.api.nvim_get_hl(0, {name = "BufferLinePickVisible"})
    local bufferline_pick_selected = vim.api.nvim_get_hl(0, {name = "BufferLinePickSelected"})

    local has_bufferline_hl = bufferline_pick and bufferline_pick.fg

    -- Set our highlights to match exactly, or use fallback red color
    if has_bufferline_hl then
        api.nvim_set_hl(0, config_module.HIGHLIGHTS.PICK, bufferline_pick)
        api.nvim_set_hl(0, config_module.HIGHLIGHTS.PICK_VISIBLE, bufferline_pick_visible)
        api.nvim_set_hl(0, config_module.HIGHLIGHTS.PICK_SELECTED, bufferline_pick_selected)
    else
        -- Fallback to red highlights when bufferline is not available
        api.nvim_set_hl(0, config_module.HIGHLIGHTS.PICK, { fg = config_module.COLORS.RED, bold = true, italic = true })
        api.nvim_set_hl(0, config_module.HIGHLIGHTS.PICK_VISIBLE, { fg = config_module.COLORS.RED, bold = true, italic = true })
        api.nvim_set_hl(0, config_module.HIGHLIGHTS.PICK_SELECTED, { fg = config_module.COLORS.RED, bold = true, italic = true })
    end
end

-- Extended picking mode management (for VBL standalone mode without bufferline)
local function start_extended_picking(mode_type)
    if not state_module.is_sidebar_open() then
        vim.notify("VBL sidebar must be open to use pick mode", vim.log.levels.WARN)
        return
    end

    -- Save current scroll offset before entering pick mode
    extended_picking_state.saved_offset = state_module.get_line_offset() or 0

    extended_picking_state.active = true
    extended_picking_state.mode_type = mode_type

    -- Set extended picking state so it will be detected during refresh
    state_module.set_extended_picking_active(true)
    state_module.set_extended_picking_mode(mode_type)
    state_module.set_was_picking(false)  -- Reset to trigger hint generation
    state_module.set_extended_picking_input_prefix("")

    -- Setup pick highlights before rendering
    setup_pick_highlights()

    -- Trigger refresh to generate hints and render with pick letters
    M.refresh("vbl_pick_mode_start")
    capture_pick_display_state()

    -- Use a blocking input loop in a coroutine to prevent keys from reaching vim
    vim.schedule(function()
        local input_buffer = ""

        -- Save current mode and switch to a safe state
        local saved_mode = vim.api.nvim_get_mode().mode

        local prompt_label = mode_type == "close" and "Pick buffer (enter to confirm) [close]" or "Pick buffer (enter to confirm)"

        -- Input loop - check state_module directly each iteration
        while state_module.get_extended_picking_state().is_active do
            local extended_picking = state_module.get_extended_picking_state()
            -- Prompt for input (non-blocking)
            vim.api.nvim_echo({{string.format("%s [%s]: ", prompt_label, input_buffer), "Question"}}, false, {})
            vim.cmd("redraw")

            -- Get a single character without echo
            local ok, char_code = pcall(vim.fn.getchar)
            if not ok then
                exit_extended_picking()
                vim.schedule(function()
                    M.refresh("vbl_pick_mode_end")
                    vim.api.nvim_echo({{"", "Normal"}}, false, {})  -- Clear prompt
                    vim.defer_fn(function()
                        M.refresh_cursor_alignment()
                    end, 150)
                end)
                break
            end

            -- Convert char code to string
            local char = type(char_code) == "number" and vim.fn.nr2char(char_code) or char_code

            -- Handle ESC (char code 27)
            if char_code == 27 then
                exit_extended_picking()
                vim.schedule(function()
                    M.refresh("vbl_pick_mode_end")
                    vim.api.nvim_echo({{"", "Normal"}}, false, {})  -- Clear prompt
                    vim.defer_fn(function()
                        M.refresh_cursor_alignment()
                    end, 150)
                end)
                break
            end

            if char == "\027" then
                exit_extended_picking()
                vim.schedule(function()
                    M.refresh("vbl_pick_mode_end")
                    vim.api.nvim_echo({{"", "Normal"}}, false, {})  -- Clear prompt
                    vim.defer_fn(function()
                        M.refresh_cursor_alignment()
                    end, 150)
                end)
                break
            end

            -- Handle Ctrl-C (char code 3)
            if char_code == 3 or char == "\003" then
                exit_extended_picking()
                vim.schedule(function()
                    M.refresh("vbl_pick_mode_end")
                    vim.api.nvim_echo({{"", "Normal"}}, false, {})  -- Clear prompt
                    vim.defer_fn(function()
                        M.refresh_cursor_alignment()
                    end, 150)
                end)
                break
            end

            if char == "\r" or char == "\n" then
                if extended_picking.hint_lines[input_buffer] then
                    local success = handle_extended_picking_key(input_buffer)
                    exit_extended_picking()
                    vim.schedule(function()
                        M.refresh("vbl_pick_mode_end")
                        vim.api.nvim_echo({{"", "Normal"}}, false, {})  -- Clear prompt
                        vim.defer_fn(function()
                            M.refresh_cursor_alignment()
                        end, 150)
                    end)
                    break
                end
                exit_extended_picking()
                vim.schedule(function()
                    M.refresh("vbl_pick_mode_end")
                    vim.api.nvim_echo({{"", "Normal"}}, false, {})  -- Clear prompt
                    vim.defer_fn(function()
                        M.refresh_cursor_alignment()
                    end, 150)
                end)
                break
            end

            -- Only handle single printable characters
            if type(char) == "string" and #char == 1 then
                local pick_chars = get_pick_chars()
                if not pick_chars:find(char, 1, true) then
                    if input_buffer ~= "" then
                        exit_extended_picking()
                        vim.schedule(function()
                            M.refresh("vbl_pick_mode_end")
                            vim.api.nvim_echo({{"", "Normal"}}, false, {})  -- Clear prompt
                            vim.defer_fn(function()
                                M.refresh_cursor_alignment()
                            end, 150)
                        end)
                        break
                    end
                    goto continue
                end
                if input_buffer == "" then
                    local _, prefix_chars = get_pick_char_sets()
                    local is_prefix = false
                    for _, prefix_char in ipairs(prefix_chars) do
                        if prefix_char == char then
                            is_prefix = true
                            break
                        end
                    end
                    if not is_prefix then
                        goto continue
                    end
                end

                input_buffer = input_buffer .. char
                update_pick_display(input_buffer)
                M.apply_extended_picking_highlights()
                vim.cmd("redraw")

                local match_count, match_hint = get_pick_char_match(input_buffer)
                if match_count == 1 and match_hint then
                    local success = handle_extended_picking_key(match_hint)
                    exit_extended_picking()
                    vim.schedule(function()
                        M.refresh("vbl_pick_mode_end")
                        vim.api.nvim_echo({{"", "Normal"}}, false, {})  -- Clear prompt
                        vim.defer_fn(function()
                            M.refresh_cursor_alignment()
                        end, 150)
                    end)
                    break
                end

                if match_count == 0 then
                    exit_extended_picking()
                    vim.schedule(function()
                        M.refresh("vbl_pick_mode_end")
                        vim.api.nvim_echo({{"", "Normal"}}, false, {})  -- Clear prompt
                        vim.defer_fn(function()
                            M.refresh_cursor_alignment()
                        end, 150)
                    end)
                    break
                end
            end
            ::continue::
        end

        -- Clear the prompt
        vim.api.nvim_echo({{"", "Normal"}}, false, {})
    end)
end

local function rebuild_extended_picking_pick_chars()
    if not extended_picking_state.active then
        return
    end

    if state_module.get_layout_mode() == "horizontal" then
        local existing = state_module.get_extended_picking_state()
        state_module.set_extended_picking_pick_chars({}, existing.hint_lines or {}, existing.bufferline_hints or {})
        extended_picking_state.extended_hints = {}
        return
    end

    local components = {}
    if bufferline_integration.is_available() then
        local bufferline_state = require('bufferline.state')
        components = bufferline_state.components or {}
    end

    local active_group = groups.get_active_group()
    local active_group_id = active_group and active_group.id or nil
    local line_to_buffer = state_module.get_line_to_buffer_id()
    local line_group_context = state_module.get_line_group_context()

    local line_hints, hint_lines, bufferline_hints = generate_extended_pick_chars(
        components,
        line_to_buffer,
        line_group_context,
        active_group_id,
        not bufferline_integration.is_available()
    )

    state_module.set_extended_picking_pick_chars(line_hints, hint_lines, bufferline_hints)
    extended_picking_state.extended_hints = line_hints
end


local function run_manual_pick(mode_type)
    if not state_module.is_sidebar_open() then
        return
    end

    start_extended_picking(mode_type)
    M.refresh("manual_pick")

    rebuild_extended_picking_pick_chars()
    M.refresh("manual_pick_hints")
    capture_pick_display_state()

    local input = read_pick_input()
    if input then
        if not handle_extended_picking_key(input) then
            exit_extended_picking()
        end
    else
        exit_extended_picking()
    end

    vim.schedule(function()
        M.refresh("manual_pick_exit")
    end)
end

local function setup_extended_picking_hooks()
    if not bufferline_integration.is_available() then
        return
    end

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

-- Import shared utilities
local utils = require('vertical-bufferline.utils')

-- State is now managed by the state_module, no direct state object needed

-- Helper function to get the current buffer from main window, not sidebar
local function get_main_window_id()
    local current_win = api.nvim_get_current_win()
    local sidebar_win = state_module.get_win_id()
    
    -- If current window is not the sidebar, use it directly
    if current_win ~= sidebar_win then
        local win_config = api.nvim_win_get_config(current_win)
        if win_config.relative == "" then  -- Not a floating window
            return current_win
        end
    end
    
    -- If current window is sidebar or floating, find the most recent non-sidebar window
    local main_windows = {}
    for _, win_id in ipairs(api.nvim_list_wins()) do
        if win_id ~= sidebar_win and api.nvim_win_is_valid(win_id) then
            local win_config = api.nvim_win_get_config(win_id)
            if win_config.relative == "" then  -- Not a floating window
                table.insert(main_windows, {
                    id = win_id,
                    buf_id = api.nvim_win_get_buf(win_id),
                    buf_name = vim.api.nvim_buf_get_name(api.nvim_win_get_buf(win_id))
                })
            end
        end
    end
    
    -- Try to find a window that has a real file (not fugitive, etc.)
    for _, win_info in ipairs(main_windows) do
        if not win_info.buf_name:match("^fugitive://") and win_info.buf_name ~= "" then
            return win_info.id
        end
    end
    
    -- If no real file window found, use the first main window
    if #main_windows > 0 then
        local win_info = main_windows[1]
        return win_info.id
    end

    return current_win
end

local function get_main_window_current_buffer()
    local main_win = get_main_window_id()
    if main_win and api.nvim_win_is_valid(main_win) then
        return api.nvim_win_get_buf(main_win)
    end

    return api.nvim_get_current_buf()
end

local function build_components_from_group(group, current_buffer_id)
    if not group then
        return {}
    end

    local group_buffers = groups.get_group_buffers(group.id) or {}
    local valid_buffers = {}
    for _, buf_id in ipairs(group_buffers) do
        if api.nvim_buf_is_valid(buf_id) and not utils.is_special_buffer(buf_id) then
            table.insert(valid_buffers, buf_id)
        end
    end

    local win_id = state_module.get_win_id()
    local window_width = 40
    if win_id and api.nvim_win_is_valid(win_id) then
        window_width = api.nvim_win_get_width(win_id)
    end

    local minimal_prefixes = {}
    if #valid_buffers > 1 then
        local filename_utils = require('vertical-bufferline.filename_utils')
        minimal_prefixes = filename_utils.generate_minimal_prefixes(valid_buffers, window_width)
    end

    local components = {}
    for i, buf_id in ipairs(valid_buffers) do
        local buf_name = api.nvim_buf_get_name(buf_id)
        local filename = buf_name == "" and "[No Name]" or vim.fn.fnamemodify(buf_name, ":t")
        table.insert(components, {
            id = buf_id,
            name = filename,
            minimal_prefix = minimal_prefixes[i],
            focused = (buf_id == current_buffer_id),
            icon = ""
        })
    end

    return components
end

local function get_statusline_buffers(group_id)
    local buffers = groups.get_group_buffers(group_id) or {}
    local visible = {}
    for _, buf_id in ipairs(buffers) do
        if api.nvim_buf_is_valid(buf_id)
            and not utils.is_special_buffer(buf_id)
            and not state_module.is_buffer_pinned(buf_id) then
            table.insert(visible, buf_id)
        end
    end
    return visible
end

local function get_main_window_current_buffer_id()
    local main_win = get_main_window_id()
    if main_win and api.nvim_win_is_valid(main_win) then
        return api.nvim_win_get_buf(main_win)
    end
    return api.nvim_get_current_buf()
end

local function get_navigable_buffers(group_id)
    local buffers = groups.get_group_buffers(group_id) or {}
    local visible = {}
    for _, buf_id in ipairs(buffers) do
        if api.nvim_buf_is_valid(buf_id)
            and not utils.is_special_buffer(buf_id)
            and not state_module.is_buffer_pinned(buf_id) then
            table.insert(visible, buf_id)
        end
    end
    return visible
end

-- Validate and initialize refresh state
local function validate_and_initialize_refresh()
    if not state_module.is_sidebar_open() or not api.nvim_win_is_valid(state_module.get_win_id()) then
        return nil
    end

    -- Ensure buf_id is valid
    if not state_module.get_buf_id() or not api.nvim_buf_is_valid(state_module.get_buf_id()) then
        return nil
    end

    if groups.is_window_scope_enabled() then
        groups.activate_window_context(get_main_window_id())
    end

    local bufferline_state = nil
    local components = {}
    if bufferline_integration.is_available() then
        bufferline_state = require('bufferline.state')
        components = bufferline_state.components or {}
    end

    local active_group = groups.get_active_group()
    local current_buffer_id = get_main_window_current_buffer()
    if not bufferline_integration.is_available() then
        components = build_components_from_group(active_group, current_buffer_id)
        local extended_picking_active = state_module.get_extended_picking_state().is_active
        bufferline_state = { components = components, is_picking = extended_picking_active }
    end

    -- Filter out invalid components and special buffers
    local valid_components = {}
    for _, comp in ipairs(components) do
        if comp.id and api.nvim_buf_is_valid(comp.id) and not utils.is_special_buffer(comp.id) then
            table.insert(valid_components, comp)
        end
    end

    -- Get group information
    local group_info = bufferline_integration.get_group_buffer_info()
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
    if not bufferline_integration.is_available() then
        return nil
    end

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
    if bufferline_state and bufferline_state.is_picking then
        is_picking = true
    end

    -- Check if any component has picking-related text
    if bufferline_state then
        for _, comp in ipairs(components) do
            if comp.text and comp.text:match("^%w") and #comp.text == 1 then
                is_picking = true
                break
            end
        end
    end
    if state_module.get_extended_picking_state().is_active then
        is_picking = true
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
        
        local line_hints, hint_lines, bufferline_hints = generate_extended_pick_chars(
            components,
            line_to_buffer,
            line_group_context,
            active_group_id,
            not bufferline_integration.is_available()
        )
        
        -- Activate extended picking mode
        local pick_mode = detect_pick_mode() or state_module.get_extended_picking_state().pick_mode or "switch"
        state_module.set_extended_picking_active(true)
        state_module.set_extended_picking_mode(pick_mode)
        state_module.set_extended_picking_pick_chars(line_hints, hint_lines, bufferline_hints)

        -- Start highlight application timer during picking mode
        local timer = vim.loop.new_timer()
        timer:start(0, config_module.UI.HIGHLIGHT_UPDATE_INTERVAL, vim.schedule_wrap(function()
            if bufferline_integration.is_available() then
                local current_state = require('bufferline.state')
                if current_state.is_picking and state_module.is_sidebar_open() then
                    M.apply_extended_picking_highlights()
                else
                    state_module.stop_highlight_timer()
                end
            else
                if state_module.get_extended_picking_state().is_active and state_module.is_sidebar_open() then
                    M.apply_extended_picking_highlights()
                else
                    state_module.stop_highlight_timer()
                end
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
    if state_module.get_layout_mode() == "horizontal" then
        return false
    end

    local show_path_setting = config_module.settings.show_path
    
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
    
    -- Use smart path compression instead of crude truncation
    local filename_utils = require('vertical-bufferline.filename_utils')
    relative_dir = filename_utils.compress_path_smart(relative_dir, config_module.settings.path_max_length, 1)
    
    return relative_dir, filename
end

local renderer = require('vertical-bufferline.renderer')
local components = require('vertical-bufferline.components')

local pick_display_cache = {
    buf_id = nil,
    lines = nil,
    hints_by_line = nil,
}

capture_pick_display_state = function()
    local buf_id = state_module.get_buf_id()
    if not buf_id or not api.nvim_buf_is_valid(buf_id) then
        return
    end

    local lines = api.nvim_buf_get_lines(buf_id, 0, -1, false)
    local line_to_buffer = state_module.get_line_to_buffer_id()
    local hint_lines = state_module.get_extended_picking_state().hint_lines or {}
    local hints_by_line = {}
    local hints_by_buffer = {}

    for hint, buf_id_for_hint in pairs(hint_lines) do
        local line_nums = {}
        for ln, mapped_buf in pairs(line_to_buffer) do
            if mapped_buf == buf_id_for_hint then
                table.insert(line_nums, ln)
            end
        end
        if #line_nums > 0 then
            for _, line_num in ipairs(line_nums) do
                local line = lines[line_num]
                if line then
                    local pos = line:find(hint, 1, true)
                    if pos then
                        hints_by_line[line_num] = { hint = hint, pos = pos }
                        hints_by_buffer[buf_id_for_hint] = hints_by_buffer[buf_id_for_hint] or {}
                        table.insert(hints_by_buffer[buf_id_for_hint], { line_num = line_num, pos = pos, hint = hint })
                    end
                end
            end
        end
    end

    pick_display_cache = {
        buf_id = buf_id,
        lines = lines,
        hints_by_line = hints_by_line,
        hints_by_buffer = hints_by_buffer,
    }
end

M._capture_pick_display_state = capture_pick_display_state

update_pick_display = function(prefix)
    local normalized_prefix = prefix or ""
    state_module.set_extended_picking_input_prefix(normalized_prefix)
    if normalized_prefix == "" then
        restore_pick_display()
        M.apply_extended_picking_highlights()
        return
    end

    local cache = pick_display_cache
    if not cache.lines or not cache.buf_id or not api.nvim_buf_is_valid(cache.buf_id) then
        M.apply_extended_picking_highlights()
        return
    end

    local updated_lines = {}
    local updated = false
    local prefix_len = #normalized_prefix
    local enter_indicator = "⏎"

    for i, line in ipairs(cache.lines) do
        local hint_info = cache.hints_by_line and cache.hints_by_line[i]
        local hint = hint_info and hint_info.hint or nil
        local hint_pos = hint_info and hint_info.pos or nil

        if hint and hint_pos then
            if hint:sub(1, prefix_len) == normalized_prefix then
                local start_idx = hint_pos
                local end_idx = start_idx + prefix_len - 1
                if hint == normalized_prefix then
                    local replaced = line:sub(1, start_idx - 1)
                        .. enter_indicator
                        .. string.rep(" ", #hint - 1)
                        .. line:sub(start_idx + #hint)
                    updated_lines[i] = replaced
                else
                    local replaced = line:sub(1, start_idx - 1)
                        .. string.rep(" ", prefix_len)
                        .. line:sub(end_idx + 1)
                    updated_lines[i] = replaced
                end
                updated = true
            else
                local start_idx = hint_pos
                local end_idx = start_idx + #hint - 1
                local replaced = line:sub(1, start_idx - 1)
                    .. string.rep(" ", #hint)
                    .. line:sub(end_idx + 1)
                updated_lines[i] = replaced
                updated = true
            end
        else
            updated_lines[i] = line
        end
    end

    if updated then
        api.nvim_buf_set_option(cache.buf_id, "modifiable", true)
        api.nvim_buf_set_lines(cache.buf_id, 0, -1, false, updated_lines)
        api.nvim_buf_set_option(cache.buf_id, "modifiable", false)
    end

    M.apply_extended_picking_highlights()
end

restore_pick_display = function()
    local cache = pick_display_cache
    if not cache.lines or not cache.buf_id or not api.nvim_buf_is_valid(cache.buf_id) then
        pick_display_cache = { buf_id = nil, lines = nil, hints_by_line = nil }
        return
    end

    api.nvim_buf_set_option(cache.buf_id, 'modifiable', true)
    api.nvim_buf_set_lines(cache.buf_id, 0, -1, false, cache.lines)
    api.nvim_buf_set_option(cache.buf_id, 'modifiable', false)
    pick_display_cache = { buf_id = nil, lines = nil, hints_by_line = nil }
end

M._update_pick_display = update_pick_display

local function build_component_list_from_buffers(buffer_ids, buffer_hints, window_width)
    local valid_buffers = {}
    for _, buf_id in ipairs(buffer_ids or {}) do
        if api.nvim_buf_is_valid(buf_id) and not utils.is_special_buffer(buf_id) then
            table.insert(valid_buffers, buf_id)
        end
    end

    local minimal_prefixes = filename_utils.generate_minimal_prefixes(valid_buffers, window_width)
    local list = {}
    for i, buf_id in ipairs(valid_buffers) do
        local buf_name = api.nvim_buf_get_name(buf_id)
        local filename = buf_name == "" and "[No Name]" or vim.fn.fnamemodify(buf_name, ":t")
        table.insert(list, {
            id = buf_id,
            name = filename,
            minimal_prefix = minimal_prefixes[i],
            icon = "",
            focused = false,
            letter = buffer_hints and buffer_hints[buf_id] or nil
        })
    end

    return list
end

local function build_pick_parts(letter, is_current, is_visible, highlight_override)
    local display_letter = letter
    local extended_picking = state_module.get_extended_picking_state()
    if extended_picking and extended_picking.is_active and type(display_letter) == "string" then
        local max_len = extended_picking.max_hint_len or 1
        if #display_letter < max_len then
            display_letter = display_letter .. string.rep(" ", max_len - #display_letter)
        end
    end
    return components.create_pick_letter(display_letter, is_current, is_visible, highlight_override)
end

local function build_horizontal_item_parts(component, number_index, max_digits, is_current, is_visible, is_picking, force_pick_letter, reserve_pick_space)
    local parts = {}

    if number_index then
        local num_str = tostring(number_index)
        local padding = (max_digits or 1) - #num_str
        local padded_num = string.rep(" ", padding) .. num_str
        local num_hl = is_current and config_module.HIGHLIGHTS.HORIZONTAL_NUMBER_CURRENT
            or config_module.HIGHLIGHTS.HORIZONTAL_NUMBER
        table.insert(parts, renderer.create_part(padded_num, num_hl))
        table.insert(parts, renderer.create_part(" ", nil))
    end

    if is_picking or force_pick_letter or reserve_pick_space then
        local letter = component.letter
        if letter then
            local pick_parts = build_pick_parts(letter, is_current, is_visible, force_pick_letter and config_module.HIGHLIGHTS.PICK or nil)
            for _, part in ipairs(pick_parts) do
                table.insert(parts, part)
            end
        elseif reserve_pick_space then
            local space_parts = components.create_space(2)
            for _, part in ipairs(space_parts) do
                table.insert(parts, part)
            end
        end
    end

    local prefix_info = nil
    local final_name = component.name
    if component.minimal_prefix and component.minimal_prefix.prefix and component.minimal_prefix.prefix ~= "" then
        prefix_info = {
            prefix = component.minimal_prefix.prefix,
            filename = component.minimal_prefix.filename
        }
        final_name = prefix_info.prefix .. prefix_info.filename
    end

    local filename_parts = components.create_filename(prefix_info, final_name, is_current, is_visible)
    for _, part in ipairs(filename_parts) do
        if is_current then
            part.highlight = config_module.HIGHLIGHTS.HORIZONTAL_CURRENT
        end
        table.insert(parts, part)
    end

    local is_modified = is_buffer_actually_modified(component.id)
    local modified_parts = components.create_modified_indicator(is_modified, is_current)
    for _, part in ipairs(modified_parts) do
        if is_current then
            part.highlight = config_module.HIGHLIGHTS.HORIZONTAL_CURRENT
        end
        table.insert(parts, part)
    end

    return parts
end

local function get_group_display_name(group)
    if not group then
        return "Group"
    end
    if group.name and group.name ~= "" then
        return group.name
    end
    if group.id == "default" then
        return "Default"
    end
    return tostring(group.id or "Group")
end

local function build_horizontal_group_parts(group, number_index, max_digits, is_active)
    local num_str = tostring(number_index)
    local padding = max_digits - #num_str
    local padded_num = string.rep(" ", padding) .. num_str
    local name = group and group.name or ""
    local label = padded_num .. (name ~= "" and (" " .. name) or "")
    local tab_hl = is_active and config_module.HIGHLIGHTS.GROUP_TAB_ACTIVE or config_module.HIGHLIGHTS.GROUP_TAB_INACTIVE

    return {
        renderer.create_part("[", tab_hl),
        renderer.create_part(label, tab_hl),
        renderer.create_part("]", tab_hl)
    }
end

local function open_menu(lines, title)
    close_menu()

    local width = 0
    for _, line in ipairs(lines) do
        local w = vim.fn.strdisplaywidth(line)
        if w > width then
            width = w
        end
    end
    if title and title ~= "" then
        width = math.max(width, vim.fn.strdisplaywidth(title))
    end
    width = math.max(10, width)

    local height = #lines
    if title and title ~= "" then
        height = height + 1
    end

    local buf_id = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf_id, 'bufhidden', 'wipe')
    api.nvim_buf_set_option(buf_id, 'filetype', 'vertical-bufferline-menu')
    api.nvim_buf_set_option(buf_id, 'modifiable', true)

    local final_lines = {}
    if title and title ~= "" then
        table.insert(final_lines, title)
    end
    for _, line in ipairs(lines) do
        table.insert(final_lines, line)
    end
    api.nvim_buf_set_lines(buf_id, 0, -1, false, final_lines)
    api.nvim_buf_set_option(buf_id, 'modifiable', false)

    local win_id = api.nvim_open_win(buf_id, false, {
        relative = 'cursor',
        row = 1,
        col = 0,
        width = width + 2,
        height = height,
        style = 'minimal',
        border = 'single',
        focusable = true,
    })

    api.nvim_win_set_option(win_id, 'number', false)
    api.nvim_win_set_option(win_id, 'relativenumber', false)
    api.nvim_win_set_option(win_id, 'cursorline', true)
    api.nvim_win_set_option(win_id, 'winhl', 'Normal:Pmenu,CursorLine:PmenuSel')
    api.nvim_win_set_option(win_id, 'wrap', false)

    menu_state.prev_win_id = api.nvim_get_current_win()
    menu_state.win_id = win_id
    menu_state.buf_id = buf_id
    menu_state.augroup = api.nvim_create_augroup("VerticalBufferlineMenu", { clear = true })
    menu_state.title = title or ""

    api.nvim_create_autocmd({ "WinLeave", "BufLeave", "BufHidden" }, {
        group = menu_state.augroup,
        buffer = buf_id,
        callback = function()
            close_menu({ restore_prev = false })
        end,
        desc = "Close vertical-bufferline menu when focus leaves",
    })

    local keymap_opts = { noremap = true, silent = true, nowait = true }
    api.nvim_buf_set_keymap(buf_id, "n", "<Esc>", ":lua require('vertical-bufferline').close_menu()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "q", ":lua require('vertical-bufferline').close_menu()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "<CR>", ":lua require('vertical-bufferline').menu_confirm_input()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "j", "j", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "k", "k", keymap_opts)

    if title and title ~= "" then
        api.nvim_buf_add_highlight(buf_id, 0, "Title", 0, 0, -1)
    end

    api.nvim_set_current_win(win_id)
end

local function can_open_popup_menu()
    local current_win = api.nvim_get_current_win()
    local sidebar_win = state_module.get_win_id()
    if sidebar_win and current_win == sidebar_win then
        return false
    end

    local win_config = api.nvim_win_get_config(current_win)
    if win_config.relative ~= "" then
        return false
    end

    local buf_id = api.nvim_win_get_buf(current_win)
    if not api.nvim_buf_is_valid(buf_id) then
        return false
    end

    if utils.is_special_buffer(buf_id) then
        return false
    end

    local buftype = api.nvim_buf_get_option(buf_id, 'buftype')
    if buftype ~= "" then
        return false
    end

    return groups.find_buffer_group(buf_id) ~= nil
end

local function get_menu_max_hint_len(items)
    local max_hint_len = 1
    for _, item in ipairs(items or {}) do
        if item.hint and #item.hint > max_hint_len then
            max_hint_len = #item.hint
        end
    end
    return max_hint_len
end

local function build_menu_hint_text(item, include_hint, input_prefix, max_hint_len)
    if not include_hint or not item.hint then
        return ""
    end

    local display_hint = item.hint
    local hint_spaces = 1

    if input_prefix ~= "" and item.hint:sub(1, #input_prefix) == input_prefix then
        display_hint = item.hint:sub(#input_prefix + 1)
        local removed = #item.hint - #display_hint
        hint_spaces = removed + 1
    end

    if #display_hint < max_hint_len then
        display_hint = display_hint .. string.rep(" ", max_hint_len - #display_hint)
    end

    return display_hint .. string.rep(" ", hint_spaces)
end

local function build_menu_modified_text(item)
    if not item or not item.is_modified then
        return ""
    end

    local parts = components.create_modified_indicator(true, false)
    if #parts == 0 then
        return ""
    end

    local rendered = renderer.render_line(parts)
    return rendered and rendered.text or ""
end

local function build_menu_lines(items, include_hint, max_digits)
    local lines = {}
    local digits = max_digits or #tostring(#items)

    -- Get input prefix for hint display
    local input_prefix = state_module.get_extended_picking_state().input_prefix or ""
    local max_hint_len = get_menu_max_hint_len(items)

    for i, item in ipairs(items) do
        local menu_index = item.menu_index or i
        item.menu_index = menu_index
        local num = tostring(menu_index)
        local padding = string.rep(" ", digits - #num)

        local hint = build_menu_hint_text(item, include_hint, input_prefix, max_hint_len)
        local name = item.name or "[No Name]"
        local modified_text = build_menu_modified_text(item)
        table.insert(lines, string.format("%s%s %s%s%s", padding, num, hint, name, modified_text))
    end
    return lines
end

local function assign_menu_pick_chars(items, buffer_hints, opts)
    opts = opts or {}
    local reserved = opts.reserved or { j = true, k = true, q = true }
    local used = {}
    local used_single = {}
    local base_chars, prefix_chars = get_pick_char_sets()
    local base_list = {}
    local prefix_list = {}
    local base_set = {}
    local prefix_set = {}
    for i = 1, #base_chars do
        local ch = base_chars:sub(i, i)
        if not reserved[ch] then
            table.insert(base_list, ch)
            base_set[ch] = true
        end
    end
    for _, ch in ipairs(prefix_chars) do
        if base_set[ch] then
            table.insert(prefix_list, ch)
        end
    end
    if #prefix_list == 0 then
        base_chars = DEFAULT_PICK_CHARS
        base_list = {}
        prefix_list = {}
        base_set = {}
        for i = 1, #base_chars do
            local ch = base_chars:sub(i, i)
            if not reserved[ch] then
                table.insert(base_list, ch)
                base_set[ch] = true
                if not ch:match("%d") then
                    table.insert(prefix_list, ch)
                end
            end
        end
    end
    for _, ch in ipairs(prefix_list) do
        prefix_set[ch] = true
    end

    for _, item in ipairs(items) do
        if item.hint and item.hint ~= "" then
            used[item.hint] = true
            if #item.hint == 1 then
                used_single[item.hint] = true
            end
        end
    end

    local function is_available_pick_char(hint)
        if not hint or #hint ~= 1 then
            return false
        end
        if reserved[hint] or used_single[hint] then
            return false
        end
        return prefix_set[hint] == true
    end

    local function is_available_hint(hint)
        if type(hint) ~= "string" or hint == "" then
            return false
        end
        if used[hint] then
            return false
        end
        local first_char = hint:sub(1, 1)
        if not prefix_set[first_char] then
            return false
        end
        for i = 1, #hint do
            local ch = hint:sub(i, i)
            if not base_set[ch] then
                return false
            end
        end
        return true
    end

    -- Assign based on filename letters (left to right), try lower then upper
    for _, item in ipairs(items) do
        if not item.hint then
            local name = item.name or ""
            for i = 1, #name do
                local ch = name:sub(i, i)
                if ch:match("%a") then
                    local lower = ch:lower()
                    local upper = ch:upper()
                    local picked = nil
                    if is_available_pick_char(lower) then
                        picked = lower
                    elseif lower ~= upper and is_available_pick_char(upper) then
                        picked = upper
                    end
                    if picked then
                        item.hint = picked
                        used[picked] = true
                        used_single[picked] = true
                        break
                    end
                end
            end
        end
    end

    -- If name-based assignment failed, fall back to existing hints
    for _, item in ipairs(items) do
        if not item.hint then
            local hint = buffer_hints and buffer_hints[item.id] or nil
            if hint and is_available_hint(hint) then
                item.hint = hint
                used[hint] = true
                if #hint == 1 then
                    used_single[hint] = true
                end
            end
        end
        ::continue::
    end

    -- Fallback to remaining available characters in prefix order
    local available = {}
    for _, char in ipairs(prefix_list) do
        if is_available_pick_char(char) then
            table.insert(available, char)
        end
    end

    local next_index = 1
    local multi_index = 1
    for _, item in ipairs(items) do
        if not item.hint then
            if next_index <= #available then
                item.hint = available[next_index]
                used[item.hint] = true
                used_single[item.hint] = true
                next_index = next_index + 1
            else
                while true do
                    local multi = generate_variable_pick_char(multi_index, base_list, prefix_list)
                    multi_index = multi_index + 1
                    if multi == "" then
                        break
                    end
                    if is_available_hint(multi) then
                        item.hint = multi
                        used[multi] = true
                        break
                    end
                end
            end
        end
    end
end

local function build_name_map(buffer_ids, window_width)
    local name_map = {}
    if #buffer_ids == 0 then
        return name_map
    end

    local minimal_prefixes = filename_utils.generate_minimal_prefixes(buffer_ids, window_width)
    for i, buf_id in ipairs(buffer_ids) do
        local buf_name = api.nvim_buf_get_name(buf_id)
        local filename = buf_name == "" and "[No Name]" or vim.fn.fnamemodify(buf_name, ":t")
        local prefix_info = minimal_prefixes[i]
        if prefix_info and prefix_info.prefix and prefix_info.prefix ~= "" then
            filename = prefix_info.prefix .. prefix_info.filename
        end
        name_map[buf_id] = filename
    end

    return name_map
end

local function apply_menu_highlights(items, include_hint, title_offset, max_digits, current_buffer_id)
    local buf_id = menu_state.buf_id
    if not buf_id or not api.nvim_buf_is_valid(buf_id) then
        return
    end

    local digits = max_digits or #tostring(#items)
    local line_offset = title_offset or 0
    local input = menu_state.input_buffer or ""
    local input_mode = menu_state.input_mode
    local input_prefix = state_module.get_extended_picking_state().input_prefix or ""
    local max_hint_len = get_menu_max_hint_len(items)
    for i, item in ipairs(items) do
        local menu_index = item.menu_index or i
        local num = tostring(menu_index)
        local padding = digits - #num
        local line = line_offset + (i - 1)
        local num_start = padding
        local num_end = padding + #num
        api.nvim_buf_add_highlight(buf_id, 0, "Number", line, num_start, num_end)
        if input ~= "" and input_mode == "index" and num:sub(1, #input) == input then
            local prefix_end = num_start + #input
            api.nvim_buf_add_highlight(buf_id, 0, config_module.HIGHLIGHTS.MENU_INPUT_PREFIX, line, num_start, prefix_end)
        end

        if include_hint and item.hint then
            local hint_start = padding + #num + 1
            local hint_end = hint_start + #item.hint
            api.nvim_buf_add_highlight(buf_id, 0, "Special", line, hint_start, hint_end)
            if input ~= "" and input_mode == "hint" and item.hint:sub(1, #input) == input then
                local prefix_end = hint_start + #input
                api.nvim_buf_add_highlight(buf_id, 0, config_module.HIGHLIGHTS.MENU_INPUT_PREFIX, line, hint_start, prefix_end)
            end
        end

        if item.is_modified then
            local modified_text = build_menu_modified_text(item)
            if modified_text ~= "" then
                local hint = build_menu_hint_text(item, include_hint, input_prefix, max_hint_len)
                local name = item.name or "[No Name]"
                local modified_start = padding + #num + 1 + #hint + #name
                local modified_end = modified_start + #modified_text
                local hl_group = (current_buffer_id and item.id == current_buffer_id)
                    and config_module.HIGHLIGHTS.MODIFIED_CURRENT
                    or config_module.HIGHLIGHTS.MODIFIED
                api.nvim_buf_add_highlight(buf_id, 0, hl_group, line, modified_start, modified_end)
            end
        end
    end
end

local function collect_menu_hint_chars(items)
    local chars = {}
    for _, item in ipairs(items) do
        if item.hint and type(item.hint) == "string" then
            for i = 1, #item.hint do
                chars[item.hint:sub(i, i)] = true
            end
        end
    end
    return chars
end

local function refresh_menu_display(items)
    local buf_id = menu_state.buf_id
    if not buf_id or not api.nvim_buf_is_valid(buf_id) then
        return
    end

    local title = menu_state.title or ""
    local lines = build_menu_lines(items, menu_state.include_hint, menu_state.max_digits)
    local final_lines = {}
    if title ~= "" then
        table.insert(final_lines, title)
    end
    for _, line in ipairs(lines) do
        table.insert(final_lines, line)
    end

    api.nvim_buf_set_option(buf_id, 'modifiable', true)
    api.nvim_buf_set_lines(buf_id, 0, -1, false, final_lines)
    api.nvim_buf_set_option(buf_id, 'modifiable', false)

    api.nvim_buf_clear_namespace(buf_id, 0, 0, -1)
    if title ~= "" then
        api.nvim_buf_add_highlight(buf_id, 0, "Title", 0, 0, -1)
    end
    apply_menu_highlights(items, menu_state.include_hint, menu_state.title_offset, menu_state.max_digits, menu_state.current_buffer_id)

    local win_id = menu_state.win_id
    if win_id and api.nvim_win_is_valid(win_id) then
        local win_config = api.nvim_win_get_config(win_id)
        win_config.height = #final_lines
        api.nvim_win_set_config(win_id, win_config)
        local target_line = 1
        if #items > 0 then
            target_line = (menu_state.title_offset or 0) + 1
        end
        api.nvim_win_set_cursor(win_id, { math.min(target_line, math.max(1, #final_lines)), 0 })
    end
end

local function get_menu_matches(input, mode)
    local items = menu_state.items or {}
    local matches = {}
    if input == "" then
        return items
    end
    for _, item in ipairs(items) do
        if mode == "index" then
            local index = tostring(item.menu_index or "")
            if index:sub(1, #input) == input then
                table.insert(matches, item)
            end
        else
            local hint = item.hint
            if hint and hint:sub(1, #input) == input then
                table.insert(matches, item)
            end
        end
    end
    return matches
end

local function setup_menu_mappings(items, on_select_item, include_hint, title_offset)
    local buf_id = menu_state.buf_id
    if not buf_id or not api.nvim_buf_is_valid(buf_id) then
        return
    end

    local keymap_opts = { noremap = true, silent = true, nowait = true }

    for i, item in ipairs(items) do
        if not item.menu_index then
            item.menu_index = i
        end
    end

    local allow_direct_digits = #items <= 9
    for i, item in ipairs(items) do
        if allow_direct_digits and i <= 9 then
            api.nvim_buf_set_keymap(buf_id, "n", tostring(i),
                string.format(":lua require('vertical-bufferline').menu_select_by_index(%d)<CR>", i),
                keymap_opts)
        end
    end

    if not allow_direct_digits then
        for digit = 0, 9 do
            api.nvim_buf_set_keymap(buf_id, "n", tostring(digit),
                string.format(":lua require('vertical-bufferline').menu_handle_input('%d')<CR>", digit),
                keymap_opts)
        end
    end

    if include_hint then
        local hint_chars = collect_menu_hint_chars(items)
        for ch, _ in pairs(hint_chars) do
            api.nvim_buf_set_keymap(buf_id, "n", ch,
                string.format(":lua require('vertical-bufferline').menu_handle_input('%s')<CR>", ch),
                keymap_opts)
        end
    end

    M._menu_items = items
    M._menu_on_select_item = on_select_item
    M._menu_title_offset = title_offset or 0
    menu_state.items = items
    menu_state.filtered_items = items
    menu_state.include_hint = include_hint or false
    menu_state.title_offset = title_offset or 0
    menu_state.max_digits = #tostring(#items)
    menu_state.input_buffer = ""
    menu_state.input_mode = nil
end

-- Create individual buffer line with proper formatting and highlights
local function create_buffer_line(component, j, total_components, current_buffer_id, is_picking, line_number, group_id, max_local_digits, max_global_digits, has_any_local_info, should_hide_local_numbering, opts)
    opts = opts or {}
    local is_last = (j == total_components)
    local is_visible = component.focused or false  -- Assuming focused means visible
    local has_pick = false
    local compact_mode = state_module.get_layout_mode() == "horizontal"
    local show_tree_lines = config_module.settings.show_tree_lines and not compact_mode
    local show_icons = config_module.settings.show_icons and not compact_mode
    
    -- Check if this buffer is in the currently active group
    local groups = require('vertical-bufferline.groups')
    local active_group = groups.get_active_group()
    local is_in_active_group = active_group and (group_id == active_group.id)
    
    -- Determine if this buffer is "current" based on group context
    local is_current = false
    if is_in_active_group then
        -- For active group, use global current buffer
        is_current = (component.id == current_buffer_id)
    elseif opts.use_current_buffer then
        is_current = (component.id == current_buffer_id)
    else
        -- For inactive groups, use the group's history to determine current buffer
        local target_group = groups.find_group_by_id(group_id)
        if target_group and target_group.history and #target_group.history > 0 then
            -- The first item in history is the group's "current" buffer
            is_current = (component.id == target_group.history[1])
        end
    end
    
    -- Build line parts using component system
    local parts = {}
    
    -- 1. Tree prefix (optional, but always show for current buffer in history)
    if show_tree_lines then
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
    
    -- 2. Pick letter (picking mode) - MUST be before numbering for alignment
    if is_picking or opts.force_pick_letter or opts.reserve_pick_space then
        local letter = component.letter

        if letter then
            has_pick = true
            local pick_parts = build_pick_parts(letter, is_current, is_visible, opts.force_pick_letter and config_module.HIGHLIGHTS.PICK or nil)
            for _, part in ipairs(pick_parts) do
                table.insert(parts, part)
            end
        elseif opts.reserve_pick_space then
            local space_parts = components.create_space(2)
            for _, part in ipairs(space_parts) do
                table.insert(parts, part)
            end
        end
    end

    -- 3. Smart numbering (intelligent display logic)
    local bl_integration = require('vertical-bufferline.bufferline-integration')
    -- 2. Numbering (skip if position is 0, show for active group and history group)
    if j > 0 and (is_in_active_group or group_id == "history" or opts.force_numbering) then
        local ok, position_info = pcall(bl_integration.get_buffer_position_info, group_id)
        if ok and position_info then
            local local_pos = position_info[component.id]  -- nil if not visible in bufferline
            local global_pos = j  -- Global position is just the index in current group
            local numbering_parts = components.create_smart_numbering(local_pos, global_pos, max_local_digits or 1, max_global_digits or 1, has_any_local_info, should_hide_local_numbering, is_current, is_visible)
            for _, part in ipairs(numbering_parts) do
                table.insert(parts, part)
            end
        else
            -- Fallback to simple numbering
            local numbering_parts = components.create_simple_numbering(j, max_global_digits or 1, is_current, is_visible)
            for _, part in ipairs(numbering_parts) do
                table.insert(parts, part)
            end
        end
    end
    
    -- 4. Space after numbering (only if there was numbering)
    if j > 0 and (is_in_active_group or group_id == "history" or opts.force_numbering) then
        local space_parts = components.create_space(1)
        for _, part in ipairs(space_parts) do
            table.insert(parts, part)
        end
    end

    local history_number_padding = 0
    if group_id == "history" and j == 0 then
        local numbering_width
        if not has_any_local_info or should_hide_local_numbering then
            numbering_width = (max_global_digits or 1)
        else
            numbering_width = (max_local_digits or 1) + 1 + (max_global_digits or 1)
        end
        local marker_width = 0
        if not show_tree_lines and is_current then
            marker_width = vim.fn.strdisplaywidth(config_module.UI.CURRENT_BUFFER_MARKER)
        end
        history_number_padding = math.max(0, numbering_width + 1 - marker_width)
        if history_number_padding > 0 then
            local space_parts = components.create_space(history_number_padding)
            for _, part in ipairs(space_parts) do
                table.insert(parts, part)
            end
        end
    end
    
    -- 5. Icon (moved before filename) - only if enabled
    if show_icons then
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
    
    -- 6. Pin indicator (only show when bufferline is available)
    if not opts.hide_pin_icon and is_buffer_pinned(component.id) then
        local pin_parts = components.create_pin_indicator(get_pin_icon(), is_current)
        for _, part in ipairs(pin_parts) do
            table.insert(parts, part)
        end
    end

    -- 7. Filename with optional prefix
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
    
    -- 8. Modified indicator (moved to end)
    local is_modified = is_buffer_actually_modified(component.id)
    local modified_parts = components.create_modified_indicator(is_modified, is_current)
    for _, part in ipairs(modified_parts) do
        table.insert(parts, part)
    end
    
    -- Render the complete line
    local rendered_line = renderer.render_line(parts)

    -- Create path line if needed
    local path_line = nil
    local should_show_path = should_show_path_for_buffer(component.id)
    if path_dir and should_show_path then
        local show_path_setting = config_module.settings.show_path
        if show_path_setting == "yes" or path_dir ~= "." then
            -- Calculate dynamic indentation to align with filename
            -- Use the same component calculation as filename lines for perfect alignment
            local base_indent = 0
            
            -- Tree prefix: only if show_tree_lines is enabled
            if show_tree_lines then
                base_indent = base_indent + 4  -- " " + tree_chars (4 chars total)
            elseif group_id == "history" and is_current then
                base_indent = base_indent + 2  -- current marker for history
            end
            
            -- Add pick letter space if in picking mode
            if is_picking then
                base_indent = base_indent + 2  -- "a "
            end
            
            -- Add numbering width - only if j > 0 and in active group or history group
            if j > 0 and (is_in_active_group or group_id == "history") then
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

            if history_number_padding > 0 then
                base_indent = base_indent + history_number_padding
            end
            
            -- Add icon width if icons are enabled (emoji + space)
            if show_icons then
                base_indent = base_indent + 2  -- "🌙 " (emoji + space)
            end
            
            -- Apply contextual compression based on available space
            local raw_path = path_dir == "." and "./" or path_dir .. "/"

            -- Get window width for contextual compression
            local win_id = state_module.get_win_id()
            local window_width = 40  -- fallback
            if win_id and api.nvim_win_is_valid(win_id) then
                window_width = api.nvim_win_get_width(win_id)
            end

            -- Calculate UI context for better compression
            local ui_context = {
                base_indent = base_indent,
                tree_chars = config_module.settings.show_tree_lines and 2 or 0,
                numbering_width = max_global_digits + 2,  -- [N] format
                preserve_segments = 1
            }

            local filename_utils = require('vertical-bufferline.filename_utils')
            local display_path = filename_utils.compress_path_contextual(raw_path, window_width, ui_context)
            
            -- Only add tree continuation if tree lines are enabled
            if show_tree_lines then
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
        has_pick = has_pick,
        is_current = is_current,
        prefix_info = prefix_info,
        -- Legacy fields for compatibility
        tree_prefix = parts[1] and parts[1].text or "",
        pick_highlight_group = nil,  -- Now handled by renderer
        pick_highlight_end = 0,
        number_highlights = nil  -- Now handled by renderer
    }
end

-- Apply all highlighting for a single buffer line (unified highlighting function)
local function apply_buffer_highlighting(line_info, component, actual_line_number, current_buffer_id, is_picking, is_in_active_group, position)
    if not line_info or not component then return end

    -- Use component-based renderer system - this is the modern approach
    if line_info.rendered_line then
        -- Log pick highlight application
        if is_picking and line_info.has_pick then
            local pick_highlights = {}
            for _, hl in ipairs(line_info.rendered_line.highlights or {}) do
                if hl.group and hl.group:match("Pick") then
                    table.insert(pick_highlights, {
                        group = hl.group,
                        start_col = hl.start_col,
                        end_col = hl.end_col
                    })
                end
            end
        end

        if line_info.is_current then
            api.nvim_buf_add_highlight(
                state_module.get_buf_id(),
                ns_id,
                config_module.HIGHLIGHTS.CURRENT,
                actual_line_number - 1,
                0,
                -1
            )
        end

        renderer.apply_highlights(state_module.get_buf_id(), ns_id, actual_line_number - 1, line_info.rendered_line)
        return
    end

    -- Fallback: This should rarely happen with the new component system
    -- If we reach here, it means create_buffer_line didn't return rendered_line properly
    vim.notify("Warning: Falling back to legacy highlighting for line " .. actual_line_number, vim.log.levels.WARN)
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
local function render_group_buffers(group_components, current_buffer_id, is_picking, lines_text, new_line_map, line_types, line_components, line_group_context, line_infos, target_buffer_id)
    
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
    
    local target_line = nil
    for j, component in ipairs(group_components) do
        if component.id and component.name and api.nvim_buf_is_valid(component.id) then
            -- Calculate the line number this buffer will be on
            local main_line_number = #lines_text + 1
            local line_info = create_buffer_line(component, j, #group_components, current_buffer_id, is_picking, main_line_number, line_group_context.current_group_id, max_local_digits, max_global_digits, has_any_local_info, should_hide_local_numbering, nil)

            -- Add main buffer line
            table.insert(lines_text, line_info.text)
            new_line_map[main_line_number] = component.id
            line_types[main_line_number] = "buffer"  -- Record this as a buffer line
            line_components[main_line_number] = component  -- Store specific component for this line
            line_infos[main_line_number] = line_info  -- Store complete line_info for highlighting
            line_group_context[main_line_number] = line_group_context.current_group_id  -- Store which group this line belongs to

            if target_buffer_id and component.id == target_buffer_id and not target_line then
                target_line = main_line_number
            end

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

    return target_line
end

-- Render header for a single group
local function render_group_header(group, i, is_active, buffer_count, lines_text, group_header_lines)
    local group_marker = is_active and config_module.UI.ACTIVE_GROUP_MARKER or config_module.UI.INACTIVE_GROUP_MARKER
    local name_segment = group.name ~= "" and (" " .. group.name) or ""

    -- Add spacing between groups (except for first group)
    if i > config_module.SYSTEM.FIRST_INDEX then
        table.insert(lines_text, "")  -- Empty line separator
        local separator_line_num = #lines_text - config_module.SYSTEM.ZERO_BASED_OFFSET  -- 0-based line number
        group_header_lines[separator_line_num] = {line = separator_line_num, type = "separator"}
    end

    -- Clean group header format without borders
    local group_line = string.format("[%d] %s%s (%d)",
        group.display_number, group_marker, name_segment, buffer_count)
    table.insert(lines_text, group_line)

    -- Record group header line info (use hash table indexed by line number for consistency)
    local header_line_num = #lines_text - config_module.SYSTEM.ZERO_BASED_OFFSET  -- 0-based line number
    group_header_lines[header_line_num] = {
        line = header_line_num,
        type = "header",
        is_active = is_active,
        group_id = group.id,
        group_number = group.display_number
    }
end

-- Render horizontal layout with multiple buffers per line
local function render_horizontal_layout(active_group, bufferline_components, current_buffer_id, is_picking, lines_text, line_types, line_infos, line_buffer_ranges, buffer_hints, pinned_buffers, pinned_set)
    if not active_group then
        return
    end

    local win_id = state_module.get_win_id()
    local window_width = 80
    if win_id and api.nvim_win_is_valid(win_id) then
        window_width = api.nvim_win_get_width(win_id)
    end

    local current_parts = {}
    local current_ranges = {}
    local current_line_width = 0
    local current_line_len = 0
    local line_has_items = false
    local line_has_pick = false
    local continuation_prefix = nil
    local function is_pinned_buffer_id(buf_id)
        return pinned_set and pinned_set[buf_id] == true
    end

    local function reset_line(prefix_parts)
        current_parts = {}
        current_ranges = {}
        current_line_width = 0
        current_line_len = 0
        line_has_items = false
        line_has_pick = false

        if prefix_parts then
            for _, part in ipairs(prefix_parts) do
                table.insert(current_parts, part)
                current_line_width = current_line_width + vim.fn.strdisplaywidth(part.text)
                current_line_len = current_line_len + #part.text
            end
        end
    end

    local function flush_line()
        if #current_parts == 0 then
            return
        end
        local rendered = renderer.render_line(current_parts)
        table.insert(lines_text, rendered.text)
        local line_num = #lines_text
        line_infos[line_num] = {
            rendered_line = rendered,
            has_pick = line_has_pick
        }
        line_types[line_num] = "horizontal"
        if #current_ranges > 0 then
            line_buffer_ranges[line_num] = current_ranges
        end
        reset_line(nil)
    end

    local function add_item(parts, buffer_id, group_id, is_history, is_group_entry)
        local sep_text = "  "
        local sep_width = vim.fn.strdisplaywidth(sep_text)
        local sep_len = #sep_text

        local item_width = 0
        local item_len = 0
        for _, part in ipairs(parts) do
            item_width = item_width + vim.fn.strdisplaywidth(part.text)
            item_len = item_len + #part.text
            if part.highlight and part.highlight:match("Pick") then
                line_has_pick = true
            end
        end

        local needed_width = item_width + (line_has_items and sep_width or 0)
        if current_line_width + needed_width > window_width and current_line_width > 0 then
            flush_line()
            reset_line(continuation_prefix)
        end

        if line_has_items then
            table.insert(current_parts, renderer.create_part(sep_text, nil))
            current_line_width = current_line_width + sep_width
            current_line_len = current_line_len + sep_len
        end

        local start_col = current_line_len
        for _, part in ipairs(parts) do
            table.insert(current_parts, part)
        end
        current_line_width = current_line_width + item_width
        current_line_len = current_line_len + item_len

        table.insert(current_ranges, {
            start_col = start_col,
            end_col = start_col + item_len,
            buffer_id = buffer_id,
            group_id = group_id,
            is_history = is_history or false,
            is_group_entry = is_group_entry or false
        })
        line_has_items = true
    end

local function render_section(label_text, label_highlight, item_entries, group_id, is_history, current_id, max_digits, is_group_entry, force_pick_letter)
        if #current_parts > 0 then
            flush_line()
        end

        local label_parts = {
            renderer.create_part(label_text, label_highlight),
            renderer.create_part(" ", nil)
        }
        local label_len = #label_text + 1
        continuation_prefix = {
            renderer.create_part(string.rep(" ", label_len), nil)
        }
        reset_line(label_parts)

        if item_entries and #item_entries > 0 then
            for _, entry in ipairs(item_entries) do
                local component = entry.component
                local number_index = entry.index
                local is_current = (component.id == current_id)
                local parts = build_horizontal_item_parts(component, number_index, max_digits, is_current, component.focused or false, is_picking, force_pick_letter, force_pick_letter and not component.letter)
                add_item(parts, component.id, group_id, is_history)
            end
        end

        flush_line()
    end

    -- Pinned section
    if pinned_buffers and #pinned_buffers > 0 then
        local pinned_entries = {}
        local pinned_items = build_component_list_from_buffers(pinned_buffers, buffer_hints, window_width)
        for i, component in ipairs(pinned_items) do
            local pin_char = state_module.get_buffer_pin_char(component.id)
            if pin_char and pin_char ~= "" then
                component.letter = pin_char
            end
            table.insert(pinned_entries, { component = component, index = i })
        end
        if #pinned_entries > 0 then
            local max_digits = #tostring(#pinned_entries)
            render_section(config_module.UI.HORIZONTAL_LABEL_PINNED, config_module.HIGHLIGHTS.SECTION_LABEL_INACTIVE, pinned_entries, "pinned", false, current_buffer_id, max_digits, false, true)
        end
    end

    -- History section (active group only)
    if groups.should_show_history(active_group.id) then
        local history = groups.get_group_history(active_group.id)
        local history_entries = {}
        local buffer_ids = {}
        for i, buf_id in ipairs(history or {}) do
            if i > config_module.settings.history_display_count then
                break
            end
            if is_pinned_buffer_id(buf_id) then
                goto continue
            end
            table.insert(buffer_ids, buf_id)
            ::continue::
        end
        if #buffer_ids > 0 then
            local history_items = build_component_list_from_buffers(buffer_ids, buffer_hints, window_width)
            for i, component in ipairs(history_items) do
                table.insert(history_entries, { component = component, index = i })
            end
            local max_digits = #tostring(#history_entries)
            render_section(config_module.UI.HORIZONTAL_LABEL_HISTORY, config_module.HIGHLIGHTS.SECTION_LABEL_INACTIVE, history_entries, active_group.id, true, current_buffer_id, max_digits)
        end
    end

    -- Active group section
    local active_group_entries = {}
    local active_group_max_digits = 1
    if active_group then
        local active_components = {}
        if bufferline_components then
            for _, comp in ipairs(bufferline_components or {}) do
                if comp.id
                    and comp.name
                    and api.nvim_buf_is_valid(comp.id)
                    and not utils.is_special_buffer(comp.id)
                    and not is_pinned_buffer_id(comp.id) then
                    table.insert(active_components, comp)
                end
            end
        end

        if #active_components > 1 then
            local buffer_ids = {}
            for _, comp in ipairs(active_components) do
                table.insert(buffer_ids, comp.id)
            end
            local minimal_prefixes = filename_utils.generate_minimal_prefixes(buffer_ids, window_width)
            for j, comp in ipairs(active_components) do
                comp.minimal_prefix = minimal_prefixes[j]
                comp.letter = buffer_hints and buffer_hints[comp.id] or comp.letter
            end
        end

        for i, component in ipairs(active_components) do
            table.insert(active_group_entries, { component = component, index = i })
        end
        if #active_group_entries > 0 then
            active_group_max_digits = #tostring(#active_group_entries)
        end

        local group_label = config_module.UI.HORIZONTAL_LABEL_FILES
        local group_current_id = nil
        if current_buffer_id
            and vim.tbl_contains(active_group.buffers or {}, current_buffer_id)
            and not is_pinned_buffer_id(current_buffer_id) then
            group_current_id = current_buffer_id
        elseif active_group.current_buffer
            and vim.tbl_contains(active_group.buffers or {}, active_group.current_buffer)
            and not is_pinned_buffer_id(active_group.current_buffer) then
            group_current_id = active_group.current_buffer
        end
        render_section(group_label, config_module.HIGHLIGHTS.SECTION_LABEL_INACTIVE, active_group_entries, active_group.id, false, group_current_id, active_group_max_digits)
    end

    -- Group list section
    local group_entries = {}
    local all_groups = groups.get_all_groups()
    local max_display_number = 1
    for i, group in ipairs(all_groups) do
        local display_number = group.display_number or i
        if display_number > max_display_number then
            max_display_number = display_number
        end
        table.insert(group_entries, {
            group = group,
            index = display_number
        })
    end

    local group_max_digits = #tostring(max_display_number)
    if #group_entries > 0 then
        if #current_parts > 0 then
            flush_line()
        end

        local label_text = config_module.UI.HORIZONTAL_LABEL_GROUPS
        local label_parts = {
            renderer.create_part(label_text, config_module.HIGHLIGHTS.SECTION_LABEL_INACTIVE),
            renderer.create_part(" ", nil)
        }
        local label_len = #label_text + 1
        continuation_prefix = {
            renderer.create_part(string.rep(" ", label_len), nil)
        }
        reset_line(label_parts)

        for _, entry in ipairs(group_entries) do
            local group = entry.group
            local is_active = active_group and group.id == active_group.id
            local parts = build_horizontal_group_parts(group, entry.index, group_max_digits, is_active)
            add_item(parts, nil, group.id, false, true)
        end

        flush_line()
    end
end

local function render_pinned_section(pinned_buffers, current_buffer_id, is_picking, lines_text, new_line_map, group_header_lines, line_types, all_components, line_components, line_group_context, line_infos, buffer_hints)
    if not pinned_buffers or #pinned_buffers == 0 then
        return nil
    end

    local header_text = string.format(" %s %s (%d)", config_module.UI.VERTICAL_LABEL_PINNED, config_module.UI.VERTICAL_PINNED_TEXT, #pinned_buffers)
    table.insert(lines_text, header_text)
    local header_line_num = #lines_text
    group_header_lines[header_line_num] = {
        type = "header",
        line = header_line_num - 1
    }

    local win_id = state_module.get_win_id()
    local window_width = 40
    if win_id and api.nvim_win_is_valid(win_id) then
        window_width = api.nvim_win_get_width(win_id)
    end

    local minimal_prefixes = filename_utils.generate_minimal_prefixes(pinned_buffers, window_width)
    local target_line = nil

    for i, buf_id in ipairs(pinned_buffers) do
        local buf_name = api.nvim_buf_get_name(buf_id)
        local filename = buf_name == "" and "[No Name]" or vim.fn.fnamemodify(buf_name, ":t")
        local is_current = buf_id == current_buffer_id

        local pin_char = state_module.get_buffer_pin_char(buf_id)
        local pinned_component = {
            id = buf_id,
            name = filename,
            minimal_prefix = minimal_prefixes[i],
            focused = is_current,
            letter = pin_char or (buffer_hints and buffer_hints[buf_id] or nil)
        }

        local line_info = create_buffer_line(
            pinned_component,
            i,
            #pinned_buffers,
            current_buffer_id,
            is_picking,
            #lines_text + 1,
            "pinned",
            1,
            1,
            false,
            false,
            {
                hide_pin_icon = true,
                force_pick_letter = true,
                reserve_pick_space = pin_char == nil,
                pick_highlight_group = config_module.HIGHLIGHTS.PICK,
                use_current_buffer = true,
                force_numbering = true
            }
        )
        table.insert(lines_text, line_info.text)
        local line_num = #lines_text

        new_line_map[line_num] = buf_id
        line_types[line_num] = "buffer"
        line_components[line_num] = pinned_component
        line_group_context[line_num] = "pinned"
        line_infos[line_num] = line_info
        all_components[buf_id] = pinned_component

        if is_current then
            target_line = line_num
        end

        if line_info.has_path and line_info.path_line then
            table.insert(lines_text, line_info.path_line)
            local path_line_num = #lines_text
            new_line_map[path_line_num] = buf_id
            line_types[path_line_num] = "path"
            line_components[path_line_num] = pinned_component
            line_group_context[path_line_num] = "pinned"
        end
    end

    table.insert(lines_text, "")
    local empty_line_num = #lines_text
    line_types[empty_line_num] = "empty"

    return target_line
end

-- Render current group's history as a unified group
-- @param current_components: Current bufferline components (for filtering history to match display)
local function render_current_group_history(active_group, current_buffer_id, is_picking, lines_text, new_line_map, group_header_lines, line_types, all_components, line_components, line_group_context, line_infos, current_components, buffer_hints, pinned_set)
    if state_module.get_layout_mode() == "horizontal" then
        return
    end

    if not active_group or not groups.should_show_history(active_group.id) then
        return
    end
    
    -- Get history from current active group only
    local history = groups.get_group_history(active_group.id)
    if not history or #history == 0 then
        return
    end

    -- Use the same data source as the interface display (current_components from bufferline)
    local current_buffer_ids = {}
    for _, comp in ipairs(current_components or {}) do
        if comp and comp.id then
            table.insert(current_buffer_ids, comp.id)
        end
    end

    -- Filter valid history items and ensure they're still in the current display
    local valid_history = {}
    for _, buffer_id in ipairs(history) do
        if api.nvim_buf_is_valid(buffer_id)
            and vim.tbl_contains(current_buffer_ids, buffer_id)
            and not (pinned_set and pinned_set[buffer_id]) then
            table.insert(valid_history, buffer_id)
        end
    end
    
    -- Only render if we have valid history items
    if #valid_history > 0 then
        -- Render history group header with enhanced styling
        local header_text = string.format(" %s %s (%d)", config_module.UI.VERTICAL_LABEL_RECENT, config_module.UI.VERTICAL_RECENT_TEXT, math.min(#valid_history, config_module.settings.history_display_count))
        table.insert(lines_text, header_text)
        local header_line_num = #lines_text
        group_header_lines[header_line_num] = {
            group_id = "history",
            group_number = "H",
            type = "header",
            is_recent_files = true,  -- Special flag for Recent Files
            line = header_line_num - 1  -- 0-based line number
        }
        
        -- Generate minimal prefixes for history items (same logic as regular groups)
        local history_buffer_ids = {}
        for i, buffer_id in ipairs(valid_history) do
            if i <= config_module.settings.history_display_count then
                table.insert(history_buffer_ids, buffer_id)
            end
        end

        local win_id = state_module.get_win_id()
        local window_width = 40  -- fallback
        if win_id and api.nvim_win_is_valid(win_id) then
            window_width = api.nvim_win_get_width(win_id)
        end

        local minimal_prefixes = filename_utils.generate_minimal_prefixes(history_buffer_ids, window_width)

        -- Render history items
        for i, buffer_id in ipairs(valid_history) do
            if i > config_module.settings.history_display_count then break end

            local buf_name = api.nvim_buf_get_name(buffer_id)
            local filename = buf_name == "" and "[No Name]" or vim.fn.fnamemodify(buf_name, ":t")
            local is_current = buffer_id == current_buffer_id
            local is_last = (i == math.min(#valid_history, config_module.settings.history_display_count))

            -- Create component object for history buffer
            local history_component = {
                id = buffer_id,
                name = filename,
                minimal_prefix = minimal_prefixes[i],  -- Add minimal prefix for path disambiguation
                focused = is_current,  -- Current buffer should be focused for proper highlighting
                letter = buffer_hints and buffer_hints[buffer_id] or nil  -- Pick mode hint
            }
            
            -- Create buffer line - first item (current) has no number, rest have numbers
            local display_pos = (i == 1) and 0 or (i - 1)  -- First item has no number, rest are numbered 1, 2, 3...
            local line_info = create_buffer_line(history_component, display_pos, #valid_history, current_buffer_id, is_picking, #lines_text + 1, "history", 1, 1, false, false, nil)
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
local function render_all_groups(active_group, components, current_buffer_id, is_picking, lines_text, new_line_map, group_header_lines, line_types, all_components, line_components, line_group_context, line_infos, buffer_hints, pinned_set)
    if not active_group then
        return components, nil
    end

    local compact_mode = state_module.get_layout_mode() == "horizontal"
    local all_groups = groups.get_all_groups()
    local remaining_components = components
    local active_buffer_line = nil
    local function is_pinned_buffer_id(buf_id)
        return pinned_set and pinned_set[buf_id] == true
    end

    for i, group in ipairs(all_groups) do
        local is_active = group.id == active_group.id
        local group_buffers = groups.get_group_buffers(group.id) or {}

        if compact_mode and not is_active then
            goto continue
        end

        -- Calculate valid buffer count (filter out special and pinned buffers)
        local valid_buffer_count = 0
        for _, buf_id in ipairs(group_buffers) do
            if vim.api.nvim_buf_is_valid(buf_id)
                and not utils.is_special_buffer(buf_id)
                and not is_pinned_buffer_id(buf_id) then
                valid_buffer_count = valid_buffer_count + 1
            end
        end
        local buffer_count = valid_buffer_count

        -- Render group header
        if not compact_mode then
            render_group_header(group, i, is_active, buffer_count, lines_text, group_header_lines)
        end

        -- Decide whether to expand group based on active status and setting
        local should_expand = is_active or (not compact_mode and config_module.settings.show_inactive_group_buffers)
        if should_expand then
            -- Get current group buffers and display them
            local group_components = {}
            if is_active then
                -- For active group, use bufferline components directly (including [No Name] buffers)
                for _, comp in ipairs(components) do
                    if comp.id
                        and comp.name
                        and not utils.is_special_buffer(comp.id)
                        and not is_pinned_buffer_id(comp.id) then
                        table.insert(group_components, comp)
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
                    -- Get window width for dynamic space calculation
                    local win_id = state_module.get_win_id()
                    local window_width = 40  -- fallback
                    if win_id and api.nvim_win_is_valid(win_id) then
                        window_width = api.nvim_win_get_width(win_id)
                    end

                    local minimal_prefixes = filename_utils.generate_minimal_prefixes(buffer_ids, window_width)
                    -- Update component names with minimal prefixes
                    for j, comp in ipairs(group_components) do
                        if comp.id and minimal_prefixes[j] then
                            comp.minimal_prefix = minimal_prefixes[j]
                        end
                    end
                end
            end

            -- For inactive groups that should show buffers, manually construct components
            if config_module.settings.show_inactive_group_buffers and not is_active then
                group_components = {}

                -- First collect all valid buffer information
                local valid_buffers = {}
                for _, buf_id in ipairs(group_buffers) do
                    if api.nvim_buf_is_valid(buf_id)
                        and not utils.is_special_buffer(buf_id)
                        and not is_pinned_buffer_id(buf_id) then
                        table.insert(valid_buffers, buf_id)
                    end
                end

                -- Generate minimal prefixes for conflict resolution
                -- Get window width for dynamic space calculation
                local win_id = state_module.get_win_id()
                local window_width = 40  -- fallback
                if win_id and api.nvim_win_is_valid(win_id) then
                    window_width = api.nvim_win_get_width(win_id)
                end

                local minimal_prefixes = filename_utils.generate_minimal_prefixes(valid_buffers, window_width)

                -- Construct components
                for j, buf_id in ipairs(valid_buffers) do
                    local buf_name = api.nvim_buf_get_name(buf_id)
                    local filename = buf_name == "" and "[No Name]" or vim.fn.fnamemodify(buf_name, ":t")
                    table.insert(group_components, {
                        id = buf_id,
                        name = filename,
                        minimal_prefix = minimal_prefixes[j],
                        icon = "",
                        focused = false,
                        letter = buffer_hints and buffer_hints[buf_id] or nil  -- Pick mode hint
                    })
                end
            end

            -- If group is empty, show clean empty group hint
            if #group_components == 0 then
                local show_tree_lines = config_module.settings.show_tree_lines and not compact_mode
                local empty_line = show_tree_lines and 
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
                if global_current
                    and vim.tbl_contains(group.buffers, global_current)
                    and not is_pinned_buffer_id(global_current) then
                    group_current_buffer_id = global_current
                elseif group.current_buffer
                    and vim.tbl_contains(group.buffers, group.current_buffer)
                    and not is_pinned_buffer_id(group.current_buffer) then
                    group_current_buffer_id = group.current_buffer
                end
            else
                -- For non-active groups, always use the group's remembered current_buffer
                if group.current_buffer
                    and vim.tbl_contains(group.buffers, group.current_buffer)
                    and not is_pinned_buffer_id(group.current_buffer) then
                    group_current_buffer_id = group.current_buffer
                end
            end
            
            local target_buffer_id = nil
            if is_active then
                target_buffer_id = group_current_buffer_id
                if not target_buffer_id and current_buffer_id then
                    target_buffer_id = current_buffer_id
                end
            end
            local group_target_line = render_group_buffers(group_components, group_current_buffer_id, is_picking, lines_text, new_line_map, line_types, line_components, line_group_context, line_infos, target_buffer_id)
            if is_active and group_target_line then
                active_buffer_line = group_target_line
            end
            
            -- Collect all components for highlighting
            for _, comp in ipairs(group_components) do
                all_components[comp.id] = comp
            end

            -- If current active group and inactive groups not shown, clear remaining components
            if is_active and not config_module.settings.show_inactive_group_buffers then
                remaining_components = {}
            end
        end

        ::continue::
    end

    return remaining_components, active_buffer_line
end

-- Apply group header highlights
local function apply_group_highlights(group_header_lines, lines_text)
    for _, header_info in pairs(group_header_lines) do
        if header_info.type == "separator" then
            -- Empty separator line - no highlight needed
            -- Just a space line for visual separation
        elseif header_info.type == "header" then
            -- Skip highlighting for Recent Files header (keep it subtle)
            if not header_info.is_recent_files then
                -- Only highlight regular group headers
                local group_highlight = header_info.is_active and config_module.HIGHLIGHTS.GROUP_ACTIVE or config_module.HIGHLIGHTS.GROUP_INACTIVE
                api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, group_highlight, header_info.line, 0, -1)
            end

            -- Note: We no longer highlight individual parts (number, marker) to preserve the background color
            -- The overall group highlight already provides the visual distinction
        elseif header_info.type == "separator_visual" then
            -- This type is no longer used since we removed visual separators
        end
    end
end

-- Calculate vertical offset to align VBL content with main window cursor
local function calculate_cursor_based_offset(content_length, target_line)
    -- Check if cursor alignment is enabled
    if not config_module.settings.align_with_cursor then
        return 0
    end

    if state_module.get_layout_mode() == "horizontal" then
        return 0
    end

    -- During pick mode, maintain the saved scroll position
    if extended_picking_state.active then
        return extended_picking_state.saved_offset
    end

    -- Find the most recently used normal window (avoid floating windows)
    local sidebar_win = state_module.get_win_id()
    local main_win = nil

    -- Look for the most suitable main window
    for _, win_id in ipairs(api.nvim_list_wins()) do
        if win_id ~= sidebar_win and api.nvim_win_is_valid(win_id) then
            local win_config = api.nvim_win_get_config(win_id)
            if win_config.relative == "" then  -- Only normal windows
                local buf_id = api.nvim_win_get_buf(win_id)
                local buftype = api.nvim_buf_get_option(buf_id, 'buftype')
                local filetype = api.nvim_buf_get_option(buf_id, 'filetype')

                -- Only use normal file buffers
                if buftype == '' and
                   filetype ~= 'TelescopePrompt' and
                   filetype ~= 'TelescopeResults' then
                    main_win = win_id
                    break
                end
            end
        end
    end

    if not main_win or not api.nvim_win_is_valid(main_win) or not api.nvim_win_is_valid(sidebar_win) then
        return 0
    end

    -- Safely get cursor position and window info
    local success, cursor_row, main_height, sidebar_height = pcall(function()
        local row = vim.api.nvim_win_call(main_win, function()
            return vim.fn.winline()
        end)
        local main_h = api.nvim_win_get_height(main_win)
        local sidebar_h = api.nvim_win_get_height(sidebar_win)
        return row, main_h, sidebar_h
    end)

    if not success then
        return 0
    end

    -- Calculate cursor position relative to visible area
    local cursor_relative_to_window = cursor_row

    -- Calculate desired offset with conservative bounds
    local desired_offset = nil
    if target_line and target_line > 0 then
        desired_offset = cursor_relative_to_window - target_line
    else
        desired_offset = cursor_relative_to_window - 5  -- Fallback: more space above
    end
    desired_offset = math.max(0, desired_offset)

    -- Ensure we don't push the target line below the visible window
    local max_offset = nil
    if target_line and target_line > 0 then
        max_offset = math.max(0, sidebar_height - target_line)
    else
        local content_len = content_length or 0
        max_offset = math.max(0, sidebar_height - content_len - 2)  -- Reserve 2 lines buffer
    end

    return math.min(desired_offset, max_offset)
end

-- Calculate the maximum display width of all lines in the content
local function calculate_content_width(lines_text)
    local max_width = 0
    for _, line in ipairs(lines_text) do
        -- Use vim.fn.strdisplaywidth to properly handle multi-byte characters
        local display_width = vim.fn.strdisplaywidth(line)
        if display_width > max_width then
            max_width = display_width
        end
    end
    return max_width
end

-- Calculate and apply adaptive width to the sidebar window
local function apply_adaptive_width(content_width)
    if not config_module.settings.adaptive_width then
        return
    end

    local win_id = state_module.get_win_id()
    if not win_id or not api.nvim_win_is_valid(win_id) then
        return
    end

    -- Get min and max width from configuration
    local min_width = config_module.settings.min_width
    local max_width = config_module.settings.max_width

    -- Calculate desired width: content width + 2 for padding
    local desired_width = content_width + 2

    -- Clamp to min/max bounds
    local new_width = math.max(min_width, math.min(desired_width, max_width))

    -- Get current width to avoid unnecessary updates
    local current_width = api.nvim_win_get_width(win_id)

    -- Only update if width actually changed
    if new_width ~= current_width then
        api.nvim_win_set_option(win_id, 'winfixwidth', false)
        api.nvim_win_set_width(win_id, new_width)

        -- Update saved width for next open
        state_module.set_last_width(new_width)

        -- For floating windows, also update position to keep it aligned
        if config_module.settings.floating then
            local win_config = api.nvim_win_get_config(win_id)
            if win_config and win_config.relative ~= "" then
                local screen_width = vim.o.columns
                local new_col = screen_width - new_width
                api.nvim_win_set_config(win_id, {
                    relative = 'editor',
                    width = new_width,
                    height = win_config.height,
                    col = new_col,
                    row = win_config.row,
                    style = 'minimal',
                    border = 'none',
                    focusable = false,
                })
            end
        end
    end
end

-- Calculate and apply adaptive height to the sidebar window (top/bottom only)
local function count_normal_windows()
    local count = 0
    for _, win_id in ipairs(api.nvim_list_wins()) do
        if api.nvim_win_is_valid(win_id) then
            local win_config = api.nvim_win_get_config(win_id)
            if win_config.relative == "" then
                count = count + 1
            end
        end
    end
    return count
end

local function configure_sidebar_window(win_id, is_horizontal, opts)
    opts = opts or {}
    api.nvim_win_set_option(win_id, 'winfixwidth', not config_module.settings.adaptive_width)
    api.nvim_win_set_option(win_id, 'winfixheight', false)
    api.nvim_win_set_option(win_id, 'number', false)
    api.nvim_win_set_option(win_id, 'relativenumber', false)
    api.nvim_win_set_option(win_id, 'cursorline', false)
    api.nvim_win_set_option(win_id, 'cursorcolumn', false)
    api.nvim_win_set_option(win_id, 'statuscolumn', '')
    api.nvim_win_set_option(win_id, 'statusline', ' ')
    if opts.placeholder then
        api.nvim_win_set_option(win_id, 'winhl', 'Normal:' .. config_module.HIGHLIGHTS.PLACEHOLDER)
    elseif is_horizontal then
        api.nvim_win_set_option(win_id, 'winhl', 'Normal:' .. config_module.HIGHLIGHTS.BAR)
    end
end

local function create_horizontal_overlay(placeholder_win_id, buf_id, placeholder_height, statusline_height)
    local row, col = unpack(api.nvim_win_get_position(placeholder_win_id))
    local width = api.nvim_win_get_width(placeholder_win_id)
    local float_height = placeholder_height + statusline_height
    local new_win_id = api.nvim_open_win(buf_id, false, {
        relative = 'editor',
        width = width,
        height = float_height,
        col = col,
        row = row,
        style = 'minimal',
        border = 'none',
        focusable = false,
        mouse = true,
    })
    configure_sidebar_window(new_win_id, true)
    return new_win_id
end

local function apply_horizontal_height(content_height)
    local win_id = state_module.get_win_id()
    local placeholder_win_id = state_module.get_placeholder_win_id()
    local buf_id = state_module.get_buf_id()
    if not placeholder_win_id or not api.nvim_win_is_valid(placeholder_win_id) then
        return
    end
    local statusline_height = layout.statusline_height(vim.o.laststatus, count_normal_windows())
    local placeholder_height = layout.placeholder_height(content_height, statusline_height)

    pcall(api.nvim_win_set_option, placeholder_win_id, 'winfixheight', false)
    pcall(api.nvim_win_set_height, placeholder_win_id, placeholder_height)
    pcall(api.nvim_win_set_option, placeholder_win_id, 'winhl', 'Normal:' .. config_module.HIGHLIGHTS.PLACEHOLDER)
    pcall(api.nvim_win_set_option, placeholder_win_id, 'statusline', ' ')

    local valid_float = win_id and api.nvim_win_is_valid(win_id)
    if valid_float then
        local win_config = api.nvim_win_get_config(win_id)
        if win_config and win_config.relative ~= "" then
            local row, col = unpack(api.nvim_win_get_position(placeholder_win_id))
            local width = api.nvim_win_get_width(placeholder_win_id)
            local float_height = placeholder_height + statusline_height
            api.nvim_win_set_config(win_id, {
                relative = 'editor',
                width = width,
                height = float_height,
                col = col,
                row = row,
                style = 'minimal',
                border = 'none',
                focusable = false,
            })
            configure_sidebar_window(win_id, true)
            return
        end
    end

    if buf_id and api.nvim_buf_is_valid(buf_id) then
        local new_win_id = create_horizontal_overlay(placeholder_win_id, buf_id, placeholder_height, statusline_height)
        state_module.set_win_id(new_win_id)
    end
end

-- Finalize buffer display with lines and mapping
local function finalize_buffer_display(lines_text, new_line_map, line_group_context, group_header_lines, line_infos, line_types, line_components, line_buffer_ranges, position, target_line, current_buffer_id, active_group_id)
    api.nvim_buf_set_option(state_module.get_buf_id(), "modifiable", true)

    if (not target_line or target_line == 0) and current_buffer_id and active_group_id then
        for line_num, buffer_id in pairs(new_line_map or {}) do
            if buffer_id == current_buffer_id
                and line_group_context[line_num] == active_group_id
                and line_types[line_num] == "buffer" then
                target_line = line_num
                break
            end
        end
    end

    local offset = 0
    if extended_picking_state.active then
        offset = extended_picking_state.saved_offset or 0
    elseif config_module.settings.align_with_cursor
        and state_module.get_layout_mode() ~= "horizontal"
        and target_line then
        local main_win = get_main_window_id()
        if main_win and api.nvim_win_is_valid(main_win) then
            local ok, cursor_row = pcall(function()
                return vim.api.nvim_win_call(main_win, function()
                    return vim.fn.winline()
                end)
            end)
            if ok then
                local cursor_relative = cursor_row
                offset = math.max(0, cursor_relative - target_line)
                local win_id = state_module.get_win_id()
                if win_id and api.nvim_win_is_valid(win_id) then
                    local sidebar_height = api.nvim_win_get_height(win_id)
                    local content_length = #lines_text
                    local max_offset = math.max(0, sidebar_height - content_length)
                    if offset > max_offset then
                        offset = max_offset
                    end
                end
            end
        end
    end

    local final_lines = {}
    local adjusted_line_map = {}
    local adjusted_group_context = {}
    local adjusted_header_lines = {}
    local adjusted_line_infos = {}
    local adjusted_line_types = {}
    local adjusted_line_components = {}
    local adjusted_line_buffer_ranges = {}

    if (not line_buffer_ranges or vim.tbl_isempty(line_buffer_ranges)) and new_line_map then
        line_buffer_ranges = {}
        for line_num, buffer_id in pairs(new_line_map) do
            local line_text = lines_text[line_num] or ""
            local line_len = #line_text
            line_buffer_ranges[line_num] = {
                {
                    start_col = 0,
                    end_col = line_len,
                    buffer_id = buffer_id,
                    group_id = line_group_context[line_num],
                    is_history = line_types[line_num] == "history"
                }
            }
        end
    end

    -- Add empty lines for offset
    for i = 1, offset do
        table.insert(final_lines, "")
    end

    -- Add original content
    for i, line in ipairs(lines_text) do
        table.insert(final_lines, line)
    end


    -- Adjust line mappings to account for offset
    for line_num, buffer_id in pairs(new_line_map or {}) do
        adjusted_line_map[line_num + offset] = buffer_id
    end

    -- Adjust group context mappings
    for line_num, group_id in pairs(line_group_context or {}) do
        if type(line_num) == "number" then
            adjusted_group_context[line_num + offset] = group_id
        else
            adjusted_group_context[line_num] = group_id
        end
    end

    -- Adjust group header line mappings
    for line_num, header_info in pairs(group_header_lines or {}) do
        -- Create a copy of header_info with adjusted line number
        local adjusted_header_info = {}
        for k, v in pairs(header_info) do
            adjusted_header_info[k] = v
        end
        adjusted_header_info.line = line_num + offset
        adjusted_header_lines[line_num + offset] = adjusted_header_info
    end

    -- Adjust line_infos mappings to account for offset
    for line_num, line_info in pairs(line_infos or {}) do
        adjusted_line_infos[line_num + offset] = line_info
    end

    -- Adjust line_types mappings to account for offset
    for line_num, line_type in pairs(line_types or {}) do
        adjusted_line_types[line_num + offset] = line_type
    end

    -- Adjust line_components mappings to account for offset
    for line_num, line_component in pairs(line_components or {}) do
        adjusted_line_components[line_num + offset] = line_component
    end

    -- Adjust line buffer ranges to account for offset
    for line_num, ranges in pairs(line_buffer_ranges or {}) do
        if type(line_num) == "number" then
            adjusted_line_buffer_ranges[line_num + offset] = ranges
        else
            adjusted_line_buffer_ranges[line_num] = ranges
        end
    end

    api.nvim_buf_set_lines(state_module.get_buf_id(), 0, -1, false, final_lines)

    -- Calculate and apply adaptive size based on layout
    if is_horizontal_position(position) then
        apply_horizontal_height(#final_lines)
    elseif config_module.settings.adaptive_width then
        local content_width = calculate_content_width(lines_text)
        apply_adaptive_width(content_width)
    end

    -- Reset horizontal scroll and keep topline anchored to avoid truncation.
    local win_id = state_module.get_win_id()
    if win_id and api.nvim_win_is_valid(win_id) then
        vim.api.nvim_win_call(win_id, function()
            local view = vim.fn.winsaveview()
            view.topline = 1
            view.leftcol = 0
            vim.fn.winrestview(view)
        end)
    end

    state_module.set_line_offset(offset)
    state_module.set_line_to_buffer_id(adjusted_line_map)
    state_module.set_line_group_context(adjusted_group_context)
    state_module.set_group_header_lines(adjusted_header_lines)
    state_module.set_line_buffer_ranges(adjusted_line_buffer_ranges)

    -- Return adjusted data so the caller can use it for highlighting
    return adjusted_line_infos, adjusted_line_map, adjusted_line_types, adjusted_line_components, adjusted_header_lines, adjusted_line_buffer_ranges
end

local function apply_cursor_alignment_view(current_buffer_id, active_group_id)
    if not config_module.settings.align_with_cursor then
        return
    end

    if state_module.get_layout_mode() == "horizontal" then
        return
    end

    if not current_buffer_id or not active_group_id then
        return
    end

    local win_id = state_module.get_win_id()
    if not win_id or not api.nvim_win_is_valid(win_id) then
        return
    end

    local main_win = get_main_window_id()
    if not main_win or not api.nvim_win_is_valid(main_win) then
        return
    end

    local line_to_buffer = state_module.get_line_to_buffer_id()
    local line_group_context = state_module.get_line_group_context()
    local target_line = nil
    for line, buf_id in pairs(line_to_buffer) do
        if buf_id == current_buffer_id and line_group_context[line] == active_group_id then
            target_line = line
            break
        end
    end

    if not target_line then
        return
    end

    local ok, cursor_line, topline = pcall(function()
        local cursor_pos = api.nvim_win_get_cursor(main_win)
        local view = vim.api.nvim_win_call(main_win, vim.fn.winsaveview)
        return cursor_pos[1], (view.topline or 1)
    end)

    if not ok then
        return
    end

    local cursor_relative = cursor_line - topline + 1
    local sidebar_height = api.nvim_win_get_height(win_id)
    local buf_id = state_module.get_buf_id()
    local line_count = api.nvim_buf_line_count(buf_id)
    local desired_topline = target_line - cursor_relative + 1
    if desired_topline < 1 then
        desired_topline = 1
    end
    local max_topline = math.max(1, line_count - sidebar_height + 1)

    local needed_line_count = sidebar_height + desired_topline - 1
    if needed_line_count > line_count then
        local tail_padding = needed_line_count - line_count
        local padding = {}
        for _ = 1, tail_padding do
            table.insert(padding, "")
        end
        api.nvim_buf_set_lines(buf_id, -1, -1, false, padding)
        line_count = api.nvim_buf_line_count(buf_id)
        max_topline = math.max(1, line_count - sidebar_height + 1)
    end

    desired_topline = math.max(1, math.min(desired_topline, max_topline))

    vim.api.nvim_win_call(win_id, function()
        local view = vim.fn.winsaveview()
        view.topline = desired_topline
        view.leftcol = 0
        vim.fn.winrestview(view)
    end)

end

-- Complete buffer setup and make it read-only
local function complete_buffer_setup()
    api.nvim_buf_set_option(state_module.get_buf_id(), "modifiable", false)
end

--- Refresh the sidebar display
--- Updates all buffer states, group information, and highlights
--- @param reason? string Optional reason for the refresh (for debugging)
--- @return nil
function M.refresh(reason, position_override)
    -- Auto-enable logging for refresh debugging (disabled for normal use)
    -- if not logger.is_enabled() and not _G._vbl_auto_logging_enabled then
    --     logger.enable(vim.fn.expand("~/vbl-refresh-debug.log"), "INFO")
    --     logger.info("refresh", "auto-enabled debug logging for refresh debugging")
    --     _G._vbl_auto_logging_enabled = true
    -- end
    
    logger.info("refresh", "refresh called", {
        reason = reason or "unknown",
        sidebar_open = state_module.is_sidebar_open(),
        win_valid = state_module.get_win_id() and api.nvim_win_is_valid(state_module.get_win_id()),
        buf_valid = state_module.get_buf_id() and api.nvim_buf_is_valid(state_module.get_buf_id())
    })
    
    local refresh_data = validate_and_initialize_refresh()
    if not refresh_data then 
        logger.warn("refresh", "refresh validation failed - skipping refresh", {
            reason = reason,
            sidebar_open = state_module.is_sidebar_open(),
            win_id = state_module.get_win_id(),
            buf_id = state_module.get_buf_id()
        })
        return 
    end

    local position = position_override or config_module.settings.position
    state_module.set_layout_mode(is_horizontal_position(position) and "horizontal" or "vertical")

    local components = refresh_data.components
    local current_buffer_id = refresh_data.current_buffer_id
    local active_group = refresh_data.active_group
    local pinned_buffers = get_pinned_buffer_ids()
    local pinned_set = {}
    for _, buf_id in ipairs(pinned_buffers) do
        pinned_set[buf_id] = true
    end

    -- Handle picking mode detection and timer management
    local is_picking = detect_and_manage_picking_mode(refresh_data.bufferline_state, components)

    -- Generate buffer hints BEFORE rendering (so they're available during line creation)
    local buffer_hints = nil
    if is_picking then
        local all_group_buffers = {}
        local active_group_id = active_group and active_group.id or nil
        local seen_buffers = {}
        local function add_unique_buffer(buf_id, group_id)
            if not buf_id or seen_buffers[buf_id] then
                return
            end
            seen_buffers[buf_id] = true
            table.insert(all_group_buffers, {buffer_id = buf_id, group_id = group_id})
        end

        for _, buf_id in ipairs(pinned_buffers) do
            if api.nvim_buf_is_valid(buf_id) then
                add_unique_buffer(buf_id, "pinned")
            end
        end

        -- Collect all buffers from history
        if active_group and active_group.history then
            for _, buf_id in ipairs(active_group.history) do
                if api.nvim_buf_is_valid(buf_id) then
                    add_unique_buffer(buf_id, active_group_id)
                end
            end
        end

        -- Collect all buffers from all groups
        for _, group in ipairs(groups.get_all_groups()) do
            for _, buf_id in ipairs(group.buffers or {}) do
                if api.nvim_buf_is_valid(buf_id) then
                    add_unique_buffer(buf_id, group.id)
                end
            end
        end

        buffer_hints = generate_buffer_pick_chars(
            all_group_buffers,
            components,
            active_group_id,
            not bufferline_integration.is_available()
        )

        if not bufferline_integration.is_available() then
            local unique_buffer_ids = {}
            local seen_buffers = {}
            for _, entry in ipairs(all_group_buffers) do
                local buf_id = entry.buffer_id
                if buf_id and not seen_buffers[buf_id] then
                    table.insert(unique_buffer_ids, buf_id)
                    seen_buffers[buf_id] = true
                end
            end

            local win_id = state_module.get_win_id()
            local window_width = 40
            if win_id and api.nvim_win_is_valid(win_id) then
                window_width = api.nvim_win_get_width(win_id)
            end

            local name_map = build_name_map(unique_buffer_ids, window_width)
            local hint_items = {}
            for _, buf_id in ipairs(unique_buffer_ids) do
                local pin_char = state_module.get_buffer_pin_char(buf_id)
                table.insert(hint_items, {
                    id = buf_id,
                    name = name_map[buf_id] or "",
                    hint = pin_char
                })
            end

            assign_menu_pick_chars(hint_items, buffer_hints)
            local remapped_hints = {}
            for _, item in ipairs(hint_items) do
                if item.hint then
                    remapped_hints[item.id] = item.hint
                end
            end
            buffer_hints = remapped_hints
        end

        -- Generate reverse mapping: letter -> buffer_id
        local hint_to_buffer = {}
        for buf_id, letter in pairs(buffer_hints) do
            hint_to_buffer[letter] = buf_id
        end

        -- Store in state for input handling
        state_module.set_extended_picking_pick_chars({}, hint_to_buffer, buffer_hints)

        -- CRITICAL: Write hints to component.letter so existing code can read them!
        -- Create a component lookup map first
        local component_by_bufid = {}
        for _, comp in ipairs(components or {}) do
            if comp.id then
                component_by_bufid[comp.id] = comp
            end
        end

        -- Write hints to components
        for buf_id, letter in pairs(buffer_hints) do
            local comp = component_by_bufid[buf_id]
            if comp then
                comp.letter = letter
            end
        end
    else
        -- CRITICAL: Clear component.letter when NOT in pick mode to remove stale hints
        for _, comp in ipairs(components or {}) do
            if comp.letter then
                comp.letter = nil
            end
        end

        -- Also clear state
        state_module.set_extended_picking_pick_chars({}, {}, {})
    end

    local lines_text = {}
    local new_line_map = {}
    local group_header_lines = {}  -- Record group header line positions and info
    local line_types = {}  -- Record what type each line is: "buffer", "path", "group_header", "group_separator"
    local all_components = {}  -- Collect all components from all groups for highlighting
    local line_components = {}  -- Store specific component for each line (handles multi-group buffers)
    local line_infos = {}  -- Store complete line_info for each line (includes number_highlights)
    local line_group_context = {}  -- Store which group each line belongs to
    local line_buffer_ranges = {}  -- Store buffer column ranges per line (horizontal layout)

    local active_buffer_line = nil
    if state_module.get_layout_mode() == "horizontal" then
        render_horizontal_layout(active_group, components, current_buffer_id, is_picking, lines_text, line_types, line_infos, line_buffer_ranges, buffer_hints, pinned_buffers, pinned_set)
    else
        local pinned_target_line = render_pinned_section(pinned_buffers, current_buffer_id, is_picking, lines_text, new_line_map, group_header_lines, line_types, all_components, line_components, line_group_context, line_infos, buffer_hints)
        if pinned_target_line then
            active_buffer_line = pinned_target_line
        end

        -- Render current group's history first (at the top)
        render_current_group_history(active_group, current_buffer_id, is_picking, lines_text, new_line_map, group_header_lines, line_types, all_components, line_components, line_group_context, line_infos, components, buffer_hints, pinned_set)

        -- Render all groups with their buffers (without applying highlights yet)
        local remaining_components = nil
        local group_active_line = nil
        remaining_components, group_active_line = render_all_groups(active_group, components, current_buffer_id, is_picking, lines_text, new_line_map, group_header_lines, line_types, all_components, line_components, line_group_context, line_infos, buffer_hints, pinned_set)
        if group_active_line then
            active_buffer_line = group_active_line
        end
        if remaining_components then
            components = remaining_components
        end
    end

    if not active_buffer_line and active_group and current_buffer_id then
        for line_num, buffer_id in pairs(new_line_map) do
            if buffer_id == current_buffer_id
                and line_group_context[line_num] == active_group.id
                and line_types[line_num] == "buffer" then
                active_buffer_line = line_num
                break
            end
        end
    end

    -- Finalize buffer display (set lines but keep modifiable) - this clears highlights
    line_infos, new_line_map, line_types, line_components, group_header_lines, line_buffer_ranges = finalize_buffer_display(lines_text, new_line_map, line_group_context, group_header_lines, line_infos, line_types, line_components, line_buffer_ranges, position, active_buffer_line, current_buffer_id, active_group and active_group.id or nil)

    
    -- Clear old highlights and apply all highlights AFTER buffer content is set
    api.nvim_buf_clear_namespace(state_module.get_buf_id(), ns_id, 0, -1)
    
    -- Re-setup highlights after clearing to ensure they're available
    setup_highlights()
    if pinned_buffers and #pinned_buffers > 0 then
        setup_pick_highlights()
    end
    
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

    if state_module.get_layout_mode() == "horizontal" then
        for line_num, line_info in pairs(line_infos or {}) do
            if line_info and line_info.rendered_line then
                renderer.apply_highlights(state_module.get_buf_id(), ns_id, line_num - 1, line_info.rendered_line)
            end
        end
        return
    end
    
    -- Log highlight application start
    logger.info("highlight", "applying buffer highlights", {
        current_buffer_id = current_buffer_id,
        active_group_id = active_group and active_group.id or "none",
        line_count = #lines_text,
        mapped_lines = vim.tbl_count(new_line_map)
    })
    
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
                
                -- Log current buffer detection for this line
                local is_current_buffer = (buffer_id == group_current_buffer_id)
                if is_current_buffer or buffer_id == current_buffer_id then
                    logger.log_buffer_state("highlight", buffer_id, group_current_buffer_id, 
                        string.format("line %d: %s buffer in %s group", 
                            line_num, is_current_buffer and "CURRENT" or "non-current",
                            is_in_active_group and "active" or "inactive"))
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
                apply_buffer_highlighting(line_info, component, line_num, group_current_buffer_id, is_picking, is_in_active_group, position)
            elseif line_type == "history" then
                -- This is a history line - apply proper highlighting using the component system
                local component = line_components[line_num]
                local line_info = line_infos[line_num]
                if component and line_info then
                    local buffer_id = new_line_map[line_num]
                    local is_current_buffer = (buffer_id == current_buffer_id)
                    -- Apply highlighting with proper group context (history group is considered active)
                    apply_buffer_highlighting(line_info, component, line_num, current_buffer_id, is_picking, true, position)
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
    if state_module.get_layout_mode() == "horizontal" then return end

    if bufferline_integration.is_available() then
        local bufferline_state = require('bufferline.state')
        if not bufferline_state.is_picking then return end
    end

    -- Re-setup highlights to ensure they're current
    setup_pick_highlights()
    local input_prefix = state_module.get_extended_picking_state().input_prefix or ""

    api.nvim_buf_clear_namespace(state_module.get_buf_id(), pick_input_ns_id, 0, -1)

    local extended_picking = state_module.get_extended_picking_state()
    if not extended_picking.is_active then
        -- Fall back to original picking highlights
        M.apply_picking_highlights()
        return
    end

    local current_buffer_id = get_main_window_current_buffer()
    local input_prefix = extended_picking.input_prefix or ""

    local line_to_buffer = state_module.get_line_to_buffer_id()
    local line_group_context = state_module.get_line_group_context()
    local active_group = groups.get_active_group()
    local active_group_id = active_group and active_group.id or nil

    -- Apply highlights to all lines with hints (including duplicate buffer lines)
    local line_hints = extended_picking.line_hints or {}
    if (not next(line_hints)) and extended_picking.hint_lines then
        line_hints = {}
        for hint_char, buf_id in pairs(extended_picking.hint_lines) do
            for line_num, mapped_buf in pairs(line_to_buffer) do
                if mapped_buf == buf_id then
                    line_hints[line_num] = hint_char
                end
            end
        end
    end

    local cached_hints = pick_display_cache.hints_by_line or {}
    local highlight_lines = {}
    for line_num, hint_info in pairs(cached_hints) do
        highlight_lines[line_num] = { hint = hint_info.hint, pos = hint_info.pos }
    end
    for line_num, hint_char in pairs(line_hints) do
        if not highlight_lines[line_num] then
            highlight_lines[line_num] = { hint = hint_char, pos = nil }
        end
    end

    for line_num, hint_info in pairs(highlight_lines) do
        local hint_char = hint_info.hint
        local buffer_id = line_to_buffer[line_num]
        if buffer_id and hint_char then
            -- Choose appropriate pick highlight based on buffer state
            local pick_highlight_group
            if buffer_id == current_buffer_id then
                pick_highlight_group = config_module.HIGHLIGHTS.PICK_SELECTED
            else
                pick_highlight_group = config_module.HIGHLIGHTS.PICK
            end
            local is_prefix_match = input_prefix ~= "" and hint_char:sub(1, #input_prefix) == input_prefix

            if hint_info.pos then
                local highlight_start = hint_info.pos - 1
                local highlight_end = highlight_start + #hint_char

                if input_prefix ~= "" then
                    if not is_prefix_match then
                        goto continue_highlight
                    end
                    if hint_char == input_prefix then
                        highlight_end = highlight_start + 1
                    else
                        local prefix_len = #input_prefix
                        highlight_start = highlight_start + prefix_len
                        if highlight_start >= highlight_end then
                            goto continue_highlight
                        end
                    end
                end

                api.nvim_buf_add_highlight(state_module.get_buf_id(), 0, pick_highlight_group, line_num - 1, highlight_start, highlight_end)
                api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, pick_highlight_group, line_num - 1, highlight_start, highlight_end)
            else
                -- Fallback: try to find the hint in the line text
                local line_text = api.nvim_buf_get_lines(state_module.get_buf_id(), line_num - 1, line_num, false)[1] or ""
                local hint_pos = line_text:find(vim.pesc(hint_char))
                if hint_pos then
                    local highlight_start = hint_pos - 1
                    local highlight_end = highlight_start + #hint_char

                    if input_prefix ~= "" then
                        if not is_prefix_match then
                            goto continue_highlight
                        end
                        if hint_char == input_prefix then
                            highlight_end = highlight_start + 1
                        else
                            local prefix_len = #input_prefix
                            highlight_start = highlight_start + prefix_len
                            if highlight_start >= highlight_end then
                                goto continue_highlight
                            end
                        end
                    end

                    api.nvim_buf_add_highlight(state_module.get_buf_id(), 0, pick_highlight_group, line_num - 1, highlight_start, highlight_end)
                    api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, pick_highlight_group, line_num - 1, highlight_start, highlight_end)
                end
            end
        end
        ::continue_highlight::
    end

    vim.cmd("redraw!")
end

--- Apply picking highlights continuously during picking mode
function M.apply_picking_highlights()
    if not state_module.is_sidebar_open() then return end
    if state_module.get_layout_mode() == "horizontal" then return end

    if not bufferline_integration.is_available() then
        return
    end

    local bufferline_state = require('bufferline.state')
    if not bufferline_state.is_picking then return end

    -- Re-setup highlights to ensure they're current
    setup_pick_highlights()
    api.nvim_buf_clear_namespace(state_module.get_buf_id(), pick_input_ns_id, 0, -1)

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
                        local is_prefix_match = input_prefix ~= "" and letter:sub(1, #input_prefix) == input_prefix

                        -- Get the actual line text to find the letter position
                        local line_text = api.nvim_buf_get_lines(state_module.get_buf_id(), actual_line_number - 1, actual_line_number, false)[1] or ""
                        local letter_pos = line_text:find(vim.pesc(letter))
                        
                        if letter_pos then
                            local highlight_start = letter_pos - 1
                            local highlight_end = highlight_start + #letter

                            if input_prefix ~= "" then
                                if not is_prefix_match then
                                    goto continue_picking
                                end
                                if letter == input_prefix then
                                    highlight_end = highlight_start + 1
                                else
                                    local prefix_len = #input_prefix
                                    highlight_start = highlight_start + prefix_len
                                    if highlight_start >= highlight_end then
                                        goto continue_picking
                                    end
                                end
                            end
                            
                            api.nvim_buf_add_highlight(state_module.get_buf_id(), 0, pick_highlight_group, actual_line_number - 1, highlight_start, highlight_end)
                            api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, pick_highlight_group, actual_line_number - 1, highlight_start, highlight_end)
                        end
                    end
                end
            end
        end
        ::continue_picking::
    end
    
    -- Apply extended hints for non-active group buffers
    if extended_picking_state.active then
        apply_extended_picking_highlights()
    end

    vim.cmd("redraw!")
end

function M.close_menu()
    close_menu()
end

function M.menu_select_by_index(index)
    local items = M._menu_items or {}
    local item = items[index]
    if not item then
        close_menu()
        return
    end
    if M._menu_on_select_item then
        M._menu_on_select_item(item)
    end
    close_menu()
end

function M.menu_select_by_pick_char(pick_char)
    local items = M._menu_items or {}
    for _, item in ipairs(items) do
        if item.hint == pick_char then
            if M._menu_on_select_item then
                M._menu_on_select_item(item)
            end
            close_menu()
            return
        end
    end
    close_menu()
end

function M.menu_select_current_line()
    local win_id = menu_state.win_id
    local buf_id = menu_state.buf_id
    if not win_id or not buf_id then
        close_menu()
        return
    end
    local count = vim.v.count
    if count and count > 0 then
        M.menu_select_by_index(count)
        return
    end
    local cursor = api.nvim_win_get_cursor(win_id)
    local line_index = cursor[1] - (M._menu_title_offset or 0)
    M.menu_select_by_index(line_index)
end

function M.menu_handle_input(char)
    if not menu_state.win_id or not menu_state.buf_id then
        return
    end

    local is_digit = char:match("%d") ~= nil
    local pick_chars = get_pick_chars()
    local is_pick_char = pick_chars:find(char, 1, true) ~= nil

    if not menu_state.input_mode then
        if is_digit then
            menu_state.input_mode = "index"
        elseif is_pick_char then
            menu_state.input_mode = "hint"
        else
            return
        end
    end

    if menu_state.input_mode == "index" and not is_digit then
        return
    end
    if menu_state.input_mode == "hint" and not is_pick_char then
        return
    end

    local current = menu_state.input_buffer or ""
    local next_input = current .. char
    local matches = get_menu_matches(next_input, menu_state.input_mode)
    if #matches == 0 then
        return
    end

    menu_state.input_buffer = next_input
    menu_state.filtered_items = matches
    refresh_menu_display(matches)

    if #matches == 1 then
        local match = matches[1]
        M.menu_select_by_index(match.menu_index or 1)
    end
end

function M.menu_confirm_input()
    local input = menu_state.input_buffer or ""
    if input == "" then
        M.menu_select_current_line()
        return
    end

    local mode = menu_state.input_mode
    if mode == "index" then
        local target = tonumber(input)
        if target then
            M.menu_select_by_index(target)
            return
        end
    elseif mode == "hint" then
        local items = menu_state.items or {}
        for _, item in ipairs(items) do
            if item.hint == input then
                M.menu_select_by_index(item.menu_index or 1)
                return
            end
        end
    end

    local matches = menu_state.filtered_items or {}
    if #matches == 1 then
        M.menu_select_by_index(matches[1].menu_index or 1)
    end
end

function M.open_buffer_menu()
    if not can_open_popup_menu() then
        return
    end

    local active_group = groups.get_active_group()
    if not active_group then
        return
    end

    local buffer_ids = {}
    for _, buf_id in ipairs(active_group.buffers or {}) do
        if api.nvim_buf_is_valid(buf_id) and not utils.is_special_buffer(buf_id) then
            table.insert(buffer_ids, buf_id)
        end
    end

    if #buffer_ids == 0 then
        vim.notify("No buffers in current group", vim.log.levels.INFO)
        return
    end

    local win_id = state_module.get_win_id()
    local window_width = 40
    if win_id and api.nvim_win_is_valid(win_id) then
        window_width = api.nvim_win_get_width(win_id)
    end

    local minimal_prefixes = filename_utils.generate_minimal_prefixes(buffer_ids, window_width)

    local items = {}
    for i, buf_id in ipairs(buffer_ids) do
        local buf_name = api.nvim_buf_get_name(buf_id)
        local filename = buf_name == "" and "[No Name]" or vim.fn.fnamemodify(buf_name, ":t")
        local prefix_info = minimal_prefixes[i]
        if prefix_info and prefix_info.prefix and prefix_info.prefix ~= "" then
            filename = prefix_info.prefix .. prefix_info.filename
        end
        table.insert(items, {
            id = buf_id,
            name = filename,
            is_modified = is_buffer_actually_modified(buf_id),
        })
    end

    local all_group_buffers = {}
    for _, buf_id in ipairs(buffer_ids) do
        table.insert(all_group_buffers, { buffer_id = buf_id, group_id = active_group.id })
    end
    local buffer_hints = generate_buffer_pick_chars(all_group_buffers, {}, active_group.id, true)
    assign_menu_pick_chars(items, buffer_hints)

    local lines = build_menu_lines(items, true)
    open_menu(lines, "Buffers")
    local current_buffer_id = get_main_window_current_buffer()
    setup_menu_mappings(items, function(item)
        switch_to_buffer_in_main_window(item.id, "Error switching buffer")
    end, true, 1)
    menu_state.current_buffer_id = current_buffer_id
    apply_menu_highlights(items, true, 1, nil, current_buffer_id)

    for i, item in ipairs(items) do
        if item.id == current_buffer_id then
            local win_id = menu_state.win_id
            if win_id and api.nvim_win_is_valid(win_id) then
                api.nvim_win_set_cursor(win_id, { i + 1, 0 })
            end
            break
        end
    end
end

function M.open_group_menu()
    if not can_open_popup_menu() then
        return
    end

    local all_groups = groups.get_all_groups()
    if #all_groups == 0 then
        return
    end

    local items = {}
    for _, group in ipairs(all_groups) do
        local name = group.name ~= "" and group.name or ""
        table.insert(items, { id = group.id, name = name })
    end

    local lines = build_menu_lines(items, false)
    open_menu(lines, "Groups")
    setup_menu_mappings(items, function(item)
        groups.set_active_group(item.id)
    end, false, 1)
    apply_menu_highlights(items, false, 1, nil)

    local active_group = groups.get_active_group()
    if active_group then
        for i, item in ipairs(items) do
            if item.id == active_group.id then
                local win_id = menu_state.win_id
                if win_id and api.nvim_win_is_valid(win_id) then
                    api.nvim_win_set_cursor(win_id, { i + 1, 0 })
                end
                break
            end
        end
    end
end

function M.open_history_menu()
    if not can_open_popup_menu() then
        return
    end

    local active_group = groups.get_active_group()
    if not active_group then
        return
    end

    local ordered_buffer_ids = {}
    local seen = {}

    local history = groups.get_group_history(active_group.id)
    for _, buf_id in ipairs(history or {}) do
        if api.nvim_buf_is_valid(buf_id) and not utils.is_special_buffer(buf_id) then
            table.insert(ordered_buffer_ids, buf_id)
            seen[buf_id] = true
        end
    end

    local stable_buffer_ids = {}
    for _, buf_id in ipairs(active_group.buffers or {}) do
        if api.nvim_buf_is_valid(buf_id) and not utils.is_special_buffer(buf_id) and not seen[buf_id] then
            table.insert(ordered_buffer_ids, buf_id)
            seen[buf_id] = true
        end
    end

    if #ordered_buffer_ids == 0 then
        vim.notify("No buffers in current group history", vim.log.levels.INFO)
        return
    end

    local win_id = state_module.get_win_id()
    local window_width = 40
    if win_id and api.nvim_win_is_valid(win_id) then
        window_width = api.nvim_win_get_width(win_id)
    end

    for _, buf_id in ipairs(active_group.buffers or {}) do
        if api.nvim_buf_is_valid(buf_id) and not utils.is_special_buffer(buf_id) then
            table.insert(stable_buffer_ids, buf_id)
        end
    end

    local name_map = build_name_map(stable_buffer_ids, window_width)

    local items = {}
    for i, buf_id in ipairs(ordered_buffer_ids) do
        local filename = name_map[buf_id]
        if not filename then
            local buf_name = api.nvim_buf_get_name(buf_id)
            filename = buf_name == "" and "[No Name]" or vim.fn.fnamemodify(buf_name, ":t")
        end
        table.insert(items, {
            id = buf_id,
            name = filename,
            is_modified = is_buffer_actually_modified(buf_id),
        })
    end

    local all_group_buffers = {}
    for _, buf_id in ipairs(stable_buffer_ids) do
        table.insert(all_group_buffers, { buffer_id = buf_id, group_id = active_group.id })
    end
    local buffer_hints = generate_buffer_pick_chars(all_group_buffers, {}, active_group.id, true)
    local stable_items = {}
    for _, buf_id in ipairs(stable_buffer_ids) do
        table.insert(stable_items, {
            id = buf_id,
            name = name_map[buf_id] or "",
        })
    end
    assign_menu_pick_chars(stable_items, buffer_hints)

    local hint_map = {}
    for _, item in ipairs(stable_items) do
        if item.hint then
            hint_map[item.id] = item.hint
        end
    end
    for _, item in ipairs(items) do
        item.hint = hint_map[item.id]
    end

    local lines = build_menu_lines(items, true)
    open_menu(lines, "History")
    local current_buffer_id = get_main_window_current_buffer()
    setup_menu_mappings(items, function(item)
        switch_to_buffer_in_main_window(item.id, "Error switching buffer")
    end, true, 1)
    menu_state.current_buffer_id = current_buffer_id
    apply_menu_highlights(items, true, 1, nil, current_buffer_id)

    for i, item in ipairs(items) do
        if item.id == current_buffer_id then
            local menu_win_id = menu_state.win_id
            if menu_win_id and api.nvim_win_is_valid(menu_win_id) then
                api.nvim_win_set_cursor(menu_win_id, { i + 1, 0 })
            end
            break
        end
    end
end



--- Closes the sidebar window.
function M.close_sidebar(position_override)
    if not state_module.is_sidebar_open() or not api.nvim_win_is_valid(state_module.get_win_id()) then return end

    local current_win = api.nvim_get_current_win()
    local all_windows = api.nvim_list_wins()
    local sidebar_win_id = state_module.get_win_id()
    local position = position_override or config_module.settings.position
    local is_horizontal = is_horizontal_position(position)
    local use_floating = config_module.settings.floating and not is_horizontal

    -- Save the current size before closing
    local placeholder_win_id = state_module.get_placeholder_win_id()
    local size_win_id = placeholder_win_id or sidebar_win_id
    if api.nvim_win_is_valid(size_win_id) then
        layout.save_size(size_win_id, position, state_module)
    end

    -- Check if only one window remains (sidebar is the last window)
    if #all_windows == 1 then
        -- If only sidebar window remains, exit nvim completely
        vim.cmd("qall")
    else
        -- Normal case: close sidebar (floating or split)
        if use_floating then
            -- Close floating window
            api.nvim_win_close(sidebar_win_id, false)
        else
            -- Close floating overlay if present
            if api.nvim_win_is_valid(sidebar_win_id) then
                pcall(api.nvim_win_close, sidebar_win_id, false)
            end

            -- Close split window
            local target_win = placeholder_win_id or sidebar_win_id
            if target_win and api.nvim_win_is_valid(target_win) then
                api.nvim_set_current_win(target_win)
                vim.cmd("close")
            end
            
            -- Return to previous window
            if api.nvim_win_is_valid(current_win) and current_win ~= sidebar_win_id and current_win ~= placeholder_win_id then
                api.nvim_set_current_win(current_win)
            else
                -- If previous window is invalid, find first valid non-sidebar window
                for _, win_id in ipairs(api.nvim_list_wins()) do
                    if win_id ~= sidebar_win_id and win_id ~= placeholder_win_id and api.nvim_win_is_valid(win_id) then
                        api.nvim_set_current_win(win_id)
                        break
                    end
                end
            end
        end
    end

    -- Clean up autocmd group for sidebar protection
    pcall(api.nvim_del_augroup_by_name, "VerticalBufferlineSidebarProtection")
    
    state_module.close_sidebar()
    state_module.set_current_position(nil)
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
    
    -- Mouse support - simple approach
    api.nvim_buf_set_keymap(buf_id, "n", "<LeftRelease>", ":lua require('vertical-bufferline').handle_mouse_click()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "<LeftMouse>", "<LeftMouse>", keymap_opts)
    
    -- Disable problematic keymaps
    api.nvim_buf_set_keymap(buf_id, "n", "<C-W>o", "<Nop>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "<C-W><C-O>", "<Nop>", keymap_opts)
end

--- Opens the sidebar window.
local function open_sidebar(position_override)
    if state_module.is_sidebar_open() then return end
    local buf_id = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf_id, 'bufhidden', 'wipe')
    api.nvim_buf_set_option(buf_id, 'buftype', 'nofile')
    api.nvim_buf_set_option(buf_id, 'buflisted', false)
    api.nvim_buf_set_option(buf_id, 'swapfile', false)
    api.nvim_buf_set_option(buf_id, 'filetype', 'vertical-bufferline')
    local current_win = api.nvim_get_current_win()

    local position = position_override or config_module.settings.position
    local is_horizontal = is_horizontal_position(position)
    local use_floating = config_module.settings.floating and not is_horizontal

    -- Use saved size if available, otherwise use defaults
    local width, height = layout.initial_size(position, state_module, config_module.settings)

    local new_win_id
    local placeholder_win_id = nil
    local placeholder_buf_id = nil

    if use_floating then
        -- Create floating sidebar (right side, focusable=false)
        local screen_width = vim.o.columns
        local screen_height = vim.o.lines
        local height = screen_height - 2  -- Leave space for command line
        local col = screen_width - width  -- Always on right side for floating
        
        new_win_id = api.nvim_open_win(buf_id, false, {  -- false = don't enter the new window
            relative = 'editor',
            width = width,
            height = height,
            col = col,
            row = 0,
            style = 'minimal',
            border = 'none',
            focusable = false,  -- This works for floating windows
            mouse = true, -- Enable mouse interaction for floating window
        })
    else
        -- Create traditional split sidebar
        if is_horizontal then
            placeholder_buf_id = api.nvim_create_buf(false, true)
            api.nvim_buf_set_option(placeholder_buf_id, 'bufhidden', 'wipe')
            api.nvim_buf_set_option(placeholder_buf_id, 'buftype', 'nofile')
            api.nvim_buf_set_option(placeholder_buf_id, 'buflisted', false)
            api.nvim_buf_set_option(placeholder_buf_id, 'swapfile', false)
            api.nvim_buf_set_option(placeholder_buf_id, 'filetype', 'vertical-bufferline-placeholder')
            if position == "top" then
                vim.cmd("topleft split")
            else
                vim.cmd("botright split")
            end
            placeholder_win_id = api.nvim_get_current_win()
            api.nvim_win_set_buf(placeholder_win_id, placeholder_buf_id)
            api.nvim_win_set_height(placeholder_win_id, height)
            configure_sidebar_window(placeholder_win_id, true, { placeholder = true })

            local row, col = unpack(api.nvim_win_get_position(placeholder_win_id))
            local width = api.nvim_win_get_width(placeholder_win_id)
            local normal_count = count_normal_windows()
            local statusline_height = layout.statusline_height(vim.o.laststatus, normal_count)
            local float_height = height + statusline_height

            new_win_id = api.nvim_open_win(buf_id, false, {
                relative = 'editor',
                width = width,
                height = float_height,
                col = col,
                row = row,
                style = 'minimal',
                border = 'none',
                focusable = false,
                mouse = true,
            })
            configure_sidebar_window(new_win_id, true)
        else
            if position == "left" then
                vim.cmd("topleft vsplit")
            else
                vim.cmd("botright vsplit")
            end
            new_win_id = api.nvim_get_current_win()
            api.nvim_win_set_buf(new_win_id, buf_id)
            api.nvim_win_set_width(new_win_id, width)
        end
    end
    
    -- Configure window options after creation
    configure_sidebar_window(new_win_id, is_horizontal)
    
    -- Ensure mouse support is enabled for this window
    if vim.o.mouse == '' then
        vim.notify("Mouse support disabled. Enable with :set mouse=a for sidebar mouse interaction", vim.log.levels.INFO)
    end
    
    -- Note: We don't use winfixbuf as it completely blocks file opening
    -- Instead, we rely on autocmd protection below for smart handling
    
    -- Buffer protection and floating window management
    local group_name = "VerticalBufferlineSidebarProtection"
    api.nvim_create_augroup(group_name, { clear = true })
    
    -- Handle window resize for floating sidebar (only needed in floating mode)
    if use_floating then
        api.nvim_create_autocmd("VimResized", {
            group = group_name,
            callback = function()
                if api.nvim_win_is_valid(new_win_id) then
                    local new_screen_width = vim.o.columns
                    local new_screen_height = vim.o.lines
                    local new_height = new_screen_height - 2
                    -- Use current window width to preserve user adjustments
                    local current_width = api.nvim_win_get_width(new_win_id)

                    -- Always position on right side for floating sidebar
                    local new_col = new_screen_width - current_width

                    api.nvim_win_set_config(new_win_id, {
                        relative = 'editor',
                        width = current_width,
                        height = new_height,
                        col = new_col,
                        row = 0
                    })
                end
            end,
            desc = "Resize floating sidebar when terminal is resized"
        })
    elseif is_horizontal then
        api.nvim_create_autocmd({"VimResized", "WinResized"}, {
            group = group_name,
            callback = function()
                if not api.nvim_win_is_valid(new_win_id) then
                    return
                end
                local line_count = api.nvim_buf_line_count(buf_id)
                apply_horizontal_height(line_count)
            end,
            desc = "Resize horizontal floating overlay when window is resized"
        })
    else
        -- For split windows, add WinEnter redirect with delay for mouse clicks
        api.nvim_create_autocmd("WinEnter", {
            group = group_name,
            callback = function()
                local current_win = api.nvim_get_current_win()
                if current_win == new_win_id or current_win == placeholder_win_id then
                    -- Wait a short delay to allow mouse click processing
                    vim.defer_fn(function()
                        -- Check if we're still in the sidebar window
                        local check_win = api.nvim_get_current_win()
                        if check_win == new_win_id or check_win == placeholder_win_id then
                            -- Find best non-sidebar window
                            local all_wins = api.nvim_list_wins()
                            local best_win = nil
                            local best_priority = -1
                            
                            for _, win_id in ipairs(all_wins) do
                                if win_id ~= new_win_id and api.nvim_win_is_valid(win_id) then
                                    local win_buf = api.nvim_win_get_buf(win_id)
                                    local buf_type = api.nvim_buf_get_option(win_buf, 'buftype')
                                    local buf_name = api.nvim_buf_get_name(win_buf)
                                    local priority = 0
                                    
                                    -- Prefer normal editing buffers
                                    if buf_type == '' and buf_name ~= '' then
                                        priority = priority + 100
                                    end
                                    
                                    -- Prefer readable files
                                    if buf_name ~= '' and vim.fn.filereadable(buf_name) == 1 then
                                        priority = priority + 50
                                    end
                                    
                                    -- Avoid special buffers
                                    if buf_name:match('^fugitive://') or buf_type ~= '' then
                                        priority = priority - 50
                                    end
                                    
                                    if priority > best_priority then
                                        best_priority = priority
                                        best_win = win_id
                                    end
                                end
                            end
                            
                            -- Redirect to the best window found
                            if best_win then
                                api.nvim_set_current_win(best_win)
                            end
                        end
                    end, 500)  -- 500ms delay
                end
            end,
            desc = "Redirect keyboard navigation away from sidebar with delay for mouse clicks"
        })
    end
    
    -- Monitor buffer changes in sidebar window
    api.nvim_create_autocmd("BufWinEnter", {
        group = group_name,
        callback = function(ev)
            -- Only respond if the event is happening in the sidebar window specifically
            local current_win = ev.buf and vim.fn.win_findbuf(ev.buf)[1]
            if not current_win or (current_win ~= new_win_id and current_win ~= placeholder_win_id) then
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
                    api.nvim_buf_set_option(new_sidebar_buf, 'buftype', 'nofile')
                    api.nvim_buf_set_option(new_sidebar_buf, 'buflisted', false)
                    api.nvim_buf_set_option(new_sidebar_buf, 'swapfile', false)
                    api.nvim_buf_set_option(new_sidebar_buf, 'filetype', 'vertical-bufferline')
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
                    api.nvim_buf_set_option(new_sidebar_buf, 'buftype', 'nofile')
                    api.nvim_buf_set_option(new_sidebar_buf, 'buflisted', false)
                    api.nvim_buf_set_option(new_sidebar_buf, 'swapfile', false)
                    api.nvim_buf_set_option(new_sidebar_buf, 'filetype', 'vertical-bufferline')
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
    state_module.set_placeholder_win_id(placeholder_win_id)
    state_module.set_placeholder_buf_id(placeholder_buf_id)
    state_module.set_sidebar_open(true)
    state_module.set_current_position(position)

    setup_sidebar_keymaps(buf_id)

    -- Switch back to original window (only needed for split mode)
    if not config_module.settings.floating then
        api.nvim_set_current_win(current_win)
    end
    
    M.refresh("sidebar_open")
end

--- Handle mouse click in sidebar
function M.handle_mouse_click()
    if not state_module.is_sidebar_open() then 
        return 
    end
    
    -- Get mouse position
    local mouse_pos = vim.fn.getmousepos()
    
    local sidebar_win_id = state_module.get_win_id()
    if not mouse_pos or mouse_pos.winid ~= sidebar_win_id then
        return
    end
    
    -- Handle selection directly using mouse position
    local col = (mouse_pos.column or 1) - 1
    M.handle_selection(nil, mouse_pos.line, col)
end

--- Cycle through show_path settings (yes -> no -> auto -> yes)
function M.cycle_show_path_setting()
    if not state_module.is_sidebar_open() then 
        return 
    end
    
    local current_setting = config_module.settings.show_path
    local next_setting
    
    if current_setting == "yes" then
        next_setting = "no"
    elseif current_setting == "no" then
        next_setting = "auto"
    else -- "auto" or any other value
        next_setting = "yes"
    end
    
    -- Update the configuration
    config_module.settings.show_path = next_setting
    
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
local function format_group_switch_label(group, fallback_number)
    local name = ""
    local display_number = fallback_number

    if group then
        name = group.name or ""
        if display_number == nil then
            display_number = group.display_number or group.id
        end
    end

    if display_number ~= nil then
        local label = "[" .. tostring(display_number) .. "]"
        if name ~= "" then
            label = label .. " " .. name
        end
        return label
    end

    if name ~= "" then
        return name
    end

    return "Group"
end

function M.handle_selection(captured_buffer_id, captured_line_number, captured_col)
    if not state_module.is_sidebar_open() then 
        return 
    end
    
    -- Use passed parameters if available, otherwise fallback to cursor position
    local cursor = api.nvim_win_get_cursor(state_module.get_win_id())
    local line_number = captured_line_number or cursor[1]
    local col = captured_col
    if col == nil then
        col = cursor[2]
    end
    local bufnr = captured_buffer_id
    
    -- If no captured buffer ID provided, get it from current mapping (fallback for backwards compatibility)
    if not bufnr then
        if state_module.get_layout_mode() == "horizontal" then
            local ranges = state_module.get_line_buffer_ranges()[line_number] or {}
            for _, range in ipairs(ranges) do
                if col >= range.start_col and col < range.end_col then
                    bufnr = range.buffer_id
                    if not bufnr and range.is_group_entry and range.group_id then
                        local target_group = groups.find_group_by_id(range.group_id)
                        if target_group then
                            groups.set_active_group(range.group_id)
                            local label = format_group_switch_label(target_group, range.group_id)
                            vim.notify("Switched to group: " .. label, vim.log.levels.INFO)
                        end
                        return
                    end
                    break
                end
            end
        else
            local line_to_buffer = state_module.get_line_to_buffer_id()
            bufnr = line_to_buffer[line_number]
        end
    end
    
    
    -- Check if this is a group header line or separator
    local group_header_lines = state_module.get_group_header_lines()
    
    for i, header_info in ipairs(group_header_lines) do
        if header_info and header_info.line == line_number - 1 then  -- Convert to 0-based
            if header_info.group_id then
                local target_group = groups.find_group_by_id(header_info.group_id)
                local group_name = format_group_switch_label(target_group, header_info.group_number or header_info.group_id)
                
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

    if state_module.get_layout_mode() == "horizontal" then
        local ranges = state_module.get_line_buffer_ranges()[line_number] or {}
        for _, range in ipairs(ranges) do
            if range.buffer_id == bufnr then
                clicked_group_id = range.group_id or clicked_group_id
                is_history_click = range.is_history or false
                break
            end
        end
    end
    
    if clicked_group_id and current_active_group and clicked_group_id == current_active_group.id then
        -- Check if this buffer is in the history
        if not is_history_click then
            local history = groups.get_group_history(current_active_group.id)
            for _, hist_buf_id in ipairs(history) do
                if hist_buf_id == bufnr then
                    is_history_click = true
                    break
                end
            end
        end
    end
    
    -- Save current buffer state before switching (for within-group buffer state preservation)
    groups.save_current_buffer_state()
    
    -- STEP 1: Determine buffer group management
    local buffer_group = groups.find_buffer_group(bufnr)
    local is_pinned_click = (clicked_group_id == "pinned")
    
    if is_pinned_click then
        -- Pinned buffers never change the active group or history
    elseif clicked_group_id and current_active_group and clicked_group_id == current_active_group.id then
        -- Clicking within current active group - ensure buffer is in the group
        if not buffer_group or buffer_group.id ~= current_active_group.id then
            -- Add the buffer to current active group (useful for history items)
            groups.add_buffer_to_group(bufnr, current_active_group.id)
        end
    elseif buffer_group then
        -- Switch to the group containing this buffer
        if not current_active_group or current_active_group.id ~= buffer_group.id then
            groups.set_active_group(buffer_group.id, bufnr)
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
    if not is_pinned_click then
        local updated_active_group = groups.get_active_group()
        if updated_active_group then
            updated_active_group.current_buffer = bufnr
        end
    end
    
    -- Provide visual feedback for history clicks
    if is_history_click then
        local buf_name = api.nvim_buf_get_name(bufnr)
        local filename = buf_name == "" and "[No Name]" or vim.fn.fnamemodify(buf_name, ":t")
        vim.notify("Switched to recent file: " .. filename, vim.log.levels.INFO)
    end
    
    -- Restore buffer state for the newly selected buffer (for within-group state preservation)
    if not is_pinned_click then
        vim.schedule(function()
            groups.restore_buffer_state_for_current_group(bufnr)
        end)
    end
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
                if active_group and active_group.id == buffer_group.id and bufferline_integration.is_available() then
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

--- Pick a buffer across groups using extended hints
--- Pick a buffer to switch to (works with or without bufferline)
function M.pick_buffer()
    start_extended_picking("switch")
end

--- Pick a buffer to close (works with or without bufferline)
function M.pick_close_buffer()
    start_extended_picking("close")
end

--- Close all buffers in the current group except the current buffer
--- @return nil
function M.close_other_buffers_in_group()
    local active_group = groups.get_active_group()
    if not active_group then
        vim.notify("No active group found", vim.log.levels.ERROR)
        return
    end

    local current_buf = api.nvim_get_current_buf()
    local buffers_to_close = {}
    local has_current_in_group = false

    for _, buf_id in ipairs(active_group.buffers) do
        if buf_id == current_buf then
            has_current_in_group = true
        elseif api.nvim_buf_is_valid(buf_id) then
            table.insert(buffers_to_close, buf_id)
        end
    end

    if not has_current_in_group then
        vim.notify("Current buffer is not in the active group", vim.log.levels.WARN)
        return
    end

    if #buffers_to_close == 0 then
        vim.notify("No other buffers to close in the current group", vim.log.levels.INFO)
        return
    end

    -- Close buffers (use :bdelete to handle modified buffers gracefully)
    for _, buf_id in ipairs(buffers_to_close) do
        pcall(api.nvim_buf_delete, buf_id, { force = false })
    end

    vim.notify(string.format("Closed %d buffer(s) in group '%s'",
        #buffers_to_close, active_group.name), vim.log.levels.INFO)

    -- Cleanup and refresh
    vim.schedule(function()
        groups.cleanup_invalid_buffers()
        M.refresh("close_other_buffers")
    end)
end

--- Toggle between showing all groups expanded vs only active group
--- When enabled, all groups show their buffer lists
--- When disabled, only the active group shows its buffer list
--- @return nil
function M.toggle_expand_all()
    config_module.settings.show_inactive_group_buffers = not config_module.settings.show_inactive_group_buffers
    local status = config_module.settings.show_inactive_group_buffers and "enabled" or "disabled"
    vim.notify("Show inactive group buffers " .. status, vim.log.levels.INFO)

    -- Refresh display
    if state_module.is_sidebar_open() then
        vim.schedule(function()
            M.refresh("expand_toggle")
        end)
    end
end

--- Toggle show inactive group buffers mode (alias for toggle_expand_all)
--- @return nil
function M.toggle_show_inactive_group_buffers()
    if not state_module.is_sidebar_open() then 
        return 
    end
    
    local current_setting = config_module.settings.show_inactive_group_buffers
    local new_setting = not current_setting
    
    -- Update the configuration
    config_module.settings.show_inactive_group_buffers = new_setting
    
    -- Provide visual feedback
    local status = new_setting and "enabled" or "disabled"
    vim.notify("Show inactive group buffers mode " .. status, vim.log.levels.INFO)
    
    -- Refresh display
    if state_module.is_sidebar_open() then
        vim.schedule(function()
            M.refresh("toggle_inactive_group_buffers")
        end)
    end
end

--- Hook into bufferline's UI refresh to mirror its state
local function setup_bufferline_hook()
    if not bufferline_integration.is_available() then
        return
    end

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

local populate_startup_buffers

-- Plugin initialization function (called on load)
local function initialize_plugin()
    -- Set global flag so bufferline knows VBL is enabled
    vim.g.enable_vertical_bufferline = 1

    -- Setup commands
    commands.setup()

    -- Initialize group functionality
    groups.setup({
        auto_create_groups = config_module.settings.auto_create_groups,
        auto_add_new_buffers = config_module.settings.auto_add_new_buffers,
        group_scope = config_module.settings.group_scope,
        inherit_on_new_window = config_module.settings.inherit_on_new_window,
    })

    -- Enable bufferline integration
    bufferline_integration.enable()

    -- Setup global variable session integration (for mini.sessions and native mksession)
    session.setup_session_integration()

    -- Setup global autocmds (not dependent on sidebar state)
    api.nvim_command("augroup VerticalBufferlineGlobal")
    api.nvim_command("autocmd!")
    -- TEMP DISABLED: api.nvim_command("autocmd BufEnter,BufDelete,BufWipeout * lua require('vertical-bufferline').refresh_if_open()")
    api.nvim_command("autocmd BufWritePost * lua require('vertical-bufferline').refresh_if_open()")
    api.nvim_command("autocmd WinClosed * lua require('vertical-bufferline').check_quit_condition()")
    api.nvim_command("autocmd WinEnter * lua require('vertical-bufferline').handle_win_enter()")

    -- Add cursor alignment triggers (only for VBL-managed file buffers)
    -- WinScrolled is needed to catch viewport changes from zz, zt, zb, etc.
    api.nvim_command("autocmd CursorMoved,CursorMovedI,WinScrolled * lua require('vertical-bufferline').refresh_cursor_alignment()")
    api.nvim_command("autocmd User " .. config_module.EVENTS.GROUP_CHANGED .. " lua require('vertical-bufferline').refresh_if_open()")

    api.nvim_command("augroup END")

    -- Setup extended picking mode hooks
    setup_extended_picking_hooks()
    
    -- Setup bufferline hooks
    setup_bufferline_hook()

    -- Setup highlights
    setup_highlights()
    setup_pick_highlights()

    if not bufferline_integration.is_available() then
        vim.schedule(function()
            if vim.v.this_session and vim.v.this_session ~= "" then
                return
            end
            open_sidebar(config_module.settings.position)
            populate_startup_buffers()
            M.refresh("no_bufferline_auto_open")
        end)
    end
end

--- Wrapper function to refresh only when sidebar is open
function M.refresh_if_open()
    if state_module.is_sidebar_open() then
        M.refresh("autocmd_trigger")
    end
end

function M.handle_win_enter()
    if not groups.is_window_scope_enabled() then
        return
    end

    if state_module.is_sidebar_open() then
        M.refresh("window_context_switch")
    end
end

-- Throttled refresh for cursor alignment (only for VBL-managed buffers)
local cursor_alignment_timer = nil

function M.refresh_cursor_alignment()
    -- Disable cursor alignment during pick mode to avoid interference
    if state_module.get_extended_picking_state().is_active then
        return
    end

    -- Only refresh if cursor alignment is enabled and sidebar is open
    if not config_module.settings.align_with_cursor or not state_module.is_sidebar_open() then
        return
    end

    local current_buf = api.nvim_get_current_buf()

    -- Check if current buffer is managed by VBL
    local groups = require('vertical-bufferline.groups')
    local all_groups = groups.get_all_groups()

    local is_vbl_buffer = false
    for _, group in ipairs(all_groups) do
        if vim.tbl_contains(group.buffers, current_buf) then
            is_vbl_buffer = true
            break
        end
    end

    if not is_vbl_buffer then
        return  -- Not a VBL-managed buffer, ignore
    end

    -- Cancel existing timer
    if cursor_alignment_timer then
        cursor_alignment_timer:stop()
        cursor_alignment_timer:close()
    end

    -- Create debounced refresh (100ms delay)
    cursor_alignment_timer = vim.loop.new_timer()
    cursor_alignment_timer:start(100, 0, vim.schedule_wrap(function()
        if state_module.is_sidebar_open() and config_module.settings.align_with_cursor then
            M.refresh("cursor_alignment")
        end
        if cursor_alignment_timer then
            cursor_alignment_timer:close()
            cursor_alignment_timer = nil
        end
    end))
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

populate_startup_buffers = function()
    -- Manually add existing buffers to default group
    -- Use multiple delayed attempts to ensure buffers are correctly identified
    for _, delay in ipairs(config_module.UI.STARTUP_DELAYS) do
        vim.defer_fn(function()
            -- If loading session, skip auto-add to avoid conflicts
            if state_module.is_session_loading() then
                return
            end

            local added_count = 0

            if groups.is_window_scope_enabled() then
                for _, win_id in ipairs(vim.api.nvim_list_wins()) do
                    if vim.api.nvim_win_is_valid(win_id) and win_id ~= state_module.get_win_id() then
                        local win_config = vim.api.nvim_win_get_config(win_id)
                        if win_config.relative == "" then
                            groups.activate_window_context(win_id)
                            local active_group = groups.get_active_group()
                            if active_group then
                                local buf = vim.api.nvim_win_get_buf(win_id)
                                if vim.api.nvim_buf_is_valid(buf) then
                                    local buf_type = vim.api.nvim_buf_get_option(buf, 'buftype')
                                    if not utils.is_special_buffer(buf) and
                                       buf_type == config_module.SYSTEM.EMPTY_BUFTYPE and
                                       not vim.tbl_contains(active_group.buffers, buf) and
                                       not groups.find_buffer_group(buf) then
                                        groups.add_buffer_to_group(buf, active_group.id)
                                        added_count = added_count + 1
                                    end
                                end
                            end
                        end
                    end
                end
            else
                local visible_buffers = {}
                for _, win_id in ipairs(vim.api.nvim_list_wins()) do
                    if vim.api.nvim_win_is_valid(win_id) then
                        local win_buf = vim.api.nvim_win_get_buf(win_id)
                        visible_buffers[win_buf] = true
                    end
                end
                local active_group = groups.get_active_group()
                if active_group then
                    for buf, _ in pairs(visible_buffers) do
                        if vim.api.nvim_buf_is_valid(buf) then
                            local buf_type = vim.api.nvim_buf_get_option(buf, 'buftype')
                            -- Only add visible buffers not already in groups
                            if not utils.is_special_buffer(buf) and
                               buf_type == config_module.SYSTEM.EMPTY_BUFTYPE and
                               not vim.tbl_contains(active_group.buffers, buf) and
                               not groups.find_buffer_group(buf) then
                                groups.add_buffer_to_group(buf, active_group.id)
                                added_count = added_count + 1
                            end
                        end
                    end
                end
            end

            if added_count > 0 then
                -- Refresh interface
                M.refresh("auto_add_buffers")
            end
        end, delay)
    end
end

--- Toggle the vertical bufferline sidebar on/off
--- Opens the sidebar if closed, closes it if open
--- @return nil
function M.toggle()
    if state_module.is_sidebar_open() then
        M.close_sidebar()
    else
        open_sidebar(config_module.settings.position)
        populate_startup_buffers()

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

--- Create a new buffer group
--- @param name? string Optional name for the group (defaults to unnamed)
--- @return table|nil group The created group object, or nil on failure
M.create_group = function(name)
    return commands.create_group({args = name or ""})
end

--- Delete the currently active group
--- @return nil
M.delete_current_group = function() commands.delete_current_group() end

--- Switch to the next group in the list
--- @return nil
M.switch_to_next_group = function() commands.next_group() end

--- Switch to the previous group in the list
--- @return nil
M.switch_to_prev_group = function() commands.prev_group() end

--- Add current buffer to a specific group
--- @param group_name string Name or ID of the target group
--- @return nil
M.add_current_buffer_to_group = function(group_name)
    commands.add_buffer_to_group({args = group_name})
end

--- Move current group up in the group list
--- @return nil
M.move_group_up = function() commands.move_group_up() end

--- Move current group down in the group list
--- @return nil
M.move_group_down = function() commands.move_group_down() end

--- Clear history for a specific group or all groups
--- @param group_id? number|string Group ID to clear history for (nil clears all groups)
--- @return boolean success True if history was cleared successfully
M.clear_history = function(group_id)
    local groups = require('vertical-bufferline.groups')
    local success = groups.clear_group_history(group_id)
    if success then
        M.refresh("clear_history")
    end
    return success
end

--- Copy current window's groups to a register (edit-mode format)
--- @param register? string Target register (defaults to ")
function M.copy_groups_to_register(register)
    require('vertical-bufferline.edit_mode').copy_to_register(register)
end

--- Cycle through path display modes (yes/no/auto)
--- @return nil
M.cycle_show_path = M.cycle_show_path_setting

--- Cycle through history display modes (yes/no/auto)
--- @return nil
M.cycle_show_history = M.cycle_show_history_setting

--- Setup function for user configuration (e.g., from lazy.nvim)
--- @param user_config? table Configuration options
--- @field user_config.min_width? number Minimum sidebar width (default: 25)
--- @field user_config.max_width? number Maximum sidebar width (default: 60)
--- @field user_config.adaptive_width? boolean Enable adaptive width sizing (default: true)
--- @field user_config.min_height? number Legacy top/bottom height setting (default: 3)
--- @field user_config.max_height? number Legacy top/bottom height setting (default: 10)
--- @field user_config.show_inactive_group_buffers? boolean Show buffer list for inactive groups (default: false)
--- @field user_config.show_icons? boolean Show file type emoji icons (default: false)
--- @field user_config.position? "left"|"right"|"top"|"bottom" Sidebar position (default: "left")
--- @field user_config.show_tree_lines? boolean Show tree-style connection lines (default: false)
--- @field user_config.floating? boolean Use floating window instead of split (default: false)
--- @field user_config.auto_create_groups? boolean Enable automatic group creation (default: true)
--- @field user_config.auto_add_new_buffers? boolean Auto-add new buffers to active group (default: true)
--- @field user_config.group_scope? "global"|"window" Group scope for VBL groups (default: "global")
--- @field user_config.inherit_on_new_window? boolean Inherit groups when a new window is created (default: false)
--- @field user_config.show_path? "yes"|"no"|"auto" Path display mode (default: "auto")
--- @field user_config.path_style? "relative"|"absolute"|"smart" Path display style (default: "relative")
--- @field user_config.path_max_length? number Maximum path display length (default: 50)
--- @field user_config.align_with_cursor? boolean Align content with cursor position (default: true)
--- @field user_config.show_history? "yes"|"no"|"auto" History display mode (default: "auto")
--- @field user_config.history_size? number Maximum files to track per group (default: 10)
--- @field user_config.history_auto_threshold? number Min files for auto mode to show history (default: 6)
--- @field user_config.history_auto_threshold_horizontal? number Min files for auto mode (top/bottom) (default: 10)
--- @field user_config.history_display_count? number Max history items to display (default: 7)
--- @field user_config.session? table Session integration settings
--- @field user_config.edit_mode? table Edit-mode settings
--- @return nil
function M.setup(user_config)
    local function merge_known_table(dst, src)
        for nested_key, nested_value in pairs(src or {}) do
            if dst[nested_key] ~= nil then
                dst[nested_key] = nested_value
            end
        end
    end

    if user_config then
        -- Merge user configuration with defaults
        for key, value in pairs(user_config) do
            if key == "session" and type(value) == "table" then
                merge_known_table(config_module.settings.session, value)
            elseif key == "edit_mode" and type(value) == "table" then
                merge_known_table(config_module.settings.edit_mode, value)
            elseif config_module.settings[key] ~= nil then
                config_module.settings[key] = value
            end
        end
    end

    -- Set up pick mode highlights
    setup_pick_highlights()
end

switch_to_buffer_in_main_window = function(buffer_id, error_prefix)
    local main_win_id = nil
    local placeholder_win_id = state_module.get_placeholder_win_id()
    for _, win_id in ipairs(api.nvim_list_wins()) do
        if win_id ~= state_module.get_win_id()
            and win_id ~= placeholder_win_id
            and api.nvim_win_is_valid(win_id) then
            local win_config = api.nvim_win_get_config(win_id)
            if win_config.relative == "" then
                local win_buf = api.nvim_win_get_buf(win_id)
                local buf_type = api.nvim_buf_get_option(win_buf, 'buftype')
                local filetype = api.nvim_buf_get_option(win_buf, 'filetype')
                if buf_type == '' and filetype ~= 'vertical-bufferline-placeholder' then
                    main_win_id = win_id
                    break
                end
            end
        end
    end

    if not main_win_id then
        vim.notify("No main window found", vim.log.levels.ERROR)
        return false
    end

    local ok, err = pcall(function()
        api.nvim_set_current_win(main_win_id)
        api.nvim_set_current_buf(buffer_id)
    end)
    if not ok then
        local prefix = error_prefix or "Error switching to buffer"
        vim.notify(prefix .. ": " .. err, vim.log.levels.ERROR)
        return false
    end

    return true
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
    
    if not switch_to_buffer_in_main_window(buffer_id, "Error switching to history buffer") then
        return false
    end
    
    -- Update group's current_buffer tracking
    active_group.current_buffer = buffer_id
    
    -- Restore buffer state
    vim.schedule(function()
        groups.restore_buffer_state_for_current_group(buffer_id)
    end)

    if state_module.is_sidebar_open() then
        vim.schedule(function()
            M.refresh("history_switch")
        end)
    end
    
    return true
end

--- Switch to group buffer by position (1-9)
--- @param position number Group buffer position (1-9)
--- @return boolean success
function M.switch_to_group_buffer(position)
    local active_group = groups.get_active_group()
    if not active_group then
        vim.notify("No active group", vim.log.levels.WARN)
        return false
    end

    local buffers = groups.get_group_buffers(active_group.id)
    if not buffers or #buffers == 0 then
        vim.notify("No buffers in current group", vim.log.levels.WARN)
        return false
    end

    local visible_buffers = {}
    for _, buf_id in ipairs(buffers) do
        if buf_id and api.nvim_buf_is_valid(buf_id) and not is_buffer_pinned(buf_id) then
            table.insert(visible_buffers, buf_id)
        end
    end

    if #visible_buffers == 0 then
        vim.notify("No buffers in current group", vim.log.levels.WARN)
        return false
    end

    if position < 1 or position > #visible_buffers then
        vim.notify(string.format("Group position %d not available (1-%d)", position, #visible_buffers), vim.log.levels.WARN)
        return false
    end

    local buffer_id = visible_buffers[position]
    if not buffer_id or not api.nvim_buf_is_valid(buffer_id) then
        vim.notify("Group buffer is no longer valid", vim.log.levels.WARN)
        return false
    end

    if not api.nvim_buf_is_loaded(buffer_id) then
        pcall(vim.fn.bufload, buffer_id)
    end

    groups.save_current_buffer_state()
    if not switch_to_buffer_in_main_window(buffer_id, "Error switching to group buffer") then
        return false
    end

    groups.sync_group_history_with_current(active_group.id, buffer_id)

    if state_module.is_sidebar_open() then
        vim.schedule(function()
            M.refresh("group_switch")
        end)
    end
    return true
end

--- Switch to next buffer in current group
--- @return boolean success
function M.switch_to_next_buffer()
    local active_group = groups.get_active_group()
    if not active_group then
        return false
    end

    local buffers = get_navigable_buffers(active_group.id)
    if not buffers or #buffers <= 1 then
        return false
    end

    local current_buf = get_main_window_current_buffer_id()
    local current_idx = nil
    for i, buf_id in ipairs(buffers) do
        if buf_id == current_buf then
            current_idx = i
            break
        end
    end

    if not current_idx then
        current_idx = 0
    end

    local next_idx = current_idx % #buffers + 1
    return M.switch_to_group_buffer(next_idx)
end

--- Switch to previous buffer in current group
--- @return boolean success
function M.switch_to_prev_buffer()
    local active_group = groups.get_active_group()
    if not active_group then
        return false
    end

    local buffers = get_navigable_buffers(active_group.id)
    if not buffers or #buffers <= 1 then
        return false
    end

    local current_buf = get_main_window_current_buffer_id()
    local current_idx = nil
    for i, buf_id in ipairs(buffers) do
        if buf_id == current_buf then
            current_idx = i
            break
        end
    end

    if not current_idx then
        current_idx = 1
    end

    local prev_idx = current_idx == 1 and #buffers or current_idx - 1
    return M.switch_to_group_buffer(prev_idx)
end

--- Switch to last buffer in current group
--- @return boolean success
function M.switch_to_last_buffer()
    local active_group = groups.get_active_group()
    if not active_group then
        return false
    end

    local buffers = get_navigable_buffers(active_group.id)
    if not buffers or #buffers == 0 then
        return false
    end

    -- Last buffer is at position #buffers
    return M.switch_to_group_buffer(#buffers)
end

--- Build a keymap preset table (opt-in)
--- @param opts? table
--- @return table
function M.keymap_preset(opts)
    opts = opts or {}

    local leader = opts.leader or "<leader>"
    local group_prefix = opts.group_prefix or (leader .. "g")
    local history_prefix = opts.history_prefix or (leader .. "h")
    local buffer_prefix = opts.buffer_prefix or leader
    local pick_key = opts.pick_key or (leader .. "p")
    local pick_close_key = opts.pick_close_key or (leader .. "P")
    local buffer_menu_key = opts.buffer_menu_key or (leader .. "bb")
    local group_menu_key = opts.group_menu_key or (leader .. "gg")
    local history_menu_key = opts.history_menu_key or (leader .. "hh")
    local include = opts.include or {}

    local function include_section(name)
        return include[name] ~= false
    end

    local preset = {}
    local function add(lhs, rhs, desc, mode)
        preset[lhs] = { mode = mode or "n", rhs = rhs, desc = desc }
    end

    if include_section("basic") then
        add(leader .. "vb", function() M.toggle() end, "Toggle vertical bufferline")
        add(leader .. "ve", function() M.toggle_expand_all() end, "Toggle expand all groups")
        add(leader .. "vi", function() require('vertical-bufferline.edit_mode').open() end, "Edit buffer groups")
        add(leader .. "gn", function() M.switch_to_next_group() end, "Switch to next group")
        add(leader .. "gp", function() M.switch_to_prev_group() end, "Switch to previous group")
        add(leader .. "G", function() require('vertical-bufferline.groups').switch_to_previous_group() end, "Switch to last-used group")
        add(leader .. "gc", function() M.create_group() end, "Create new group")
    end

    if include_section("group_numbers") then
        for i = 1, 9 do
            add(group_prefix .. i, function() M.groups.switch_to_group_by_display_number(i) end,
                "Switch to group " .. i)
        end
    end

    if include_section("history_numbers") then
        for i = 1, 9 do
            add(history_prefix .. i, function() M.switch_to_history_file(i) end,
                "Switch to history file " .. i)
        end
    end

    if include_section("buffer_numbers") then
        for i = 1, 9 do
            add(buffer_prefix .. i, function() M.switch_to_group_buffer(i) end,
                "Switch to group buffer " .. i)
        end
        -- Add <leader>0 for the 10th buffer
        add(buffer_prefix .. "0", function() M.switch_to_group_buffer(10) end,
            "Switch to group buffer 10")
    end

    if include_section("buffer_navigation") then
        add(leader .. "bn", function() M.switch_to_next_buffer() end, "Switch to next buffer")
        add(leader .. "bp", function() M.switch_to_prev_buffer() end, "Switch to previous buffer")
        add(leader .. "b$", function() M.switch_to_last_buffer() end, "Switch to last buffer")
    end

    if include_section("buffer_management") then
        add(leader .. "Bo", function() M.close_other_buffers_in_group() end, "Close other buffers in group")
        add(leader .. "BO", function() M.close_other_buffers_in_group() end, "Close other buffers in group")
    end

    if include_section("pick") then
        add(pick_key, function() M.pick_buffer() end, "Pick buffer (VBL)")
        add(pick_close_key, function() M.pick_close_buffer() end, "Pick and close buffer (VBL)")
    end

    if include_section("menus") then
        add(buffer_menu_key, function() M.open_buffer_menu() end, "Open buffer menu (VBL)")
        add(group_menu_key, function() M.open_group_menu() end, "Open group menu (VBL)")
        add(history_menu_key, function() M.open_history_menu() end, "Open history menu (VBL)")
    end

    return preset
end

--- Apply a keymap preset table (opt-in)
--- @param preset? table
--- @param opts? table
function M.apply_keymaps(preset, opts)
    opts = opts or {}
    preset = preset or M.keymap_preset(opts.preset or {})

    local force = opts.force or false
    local base_opts = vim.tbl_deep_extend("force", { noremap = true, silent = true }, opts.map_opts or {})

    for lhs, item in pairs(preset) do
        local mode = item.mode or "n"
        if force or vim.fn.maparg(lhs, mode) == "" then
            local map_opts = vim.tbl_deep_extend("force", base_opts, { desc = item.desc })
            vim.keymap.set(mode, lhs, item.rhs, map_opts)
        end
    end
end

function M.statusline_label()
    local group = groups.get_active_group()
    if not group then
        return ""
    end

    local label = nil
    if group.name and group.name ~= "" then
        label = group.name
    else
        label = tostring(group.display_number or 0)
    end

    local visible = get_statusline_buffers(group.id)
    local total = #visible
    if total == 0 then
        return string.format("[%s]", label)
    end

    local buf = get_main_window_current_buffer_id()
    local local_pos = nil
    for i, id in ipairs(visible) do
        if id == buf then
            local_pos = i
            break
        end
    end

    if not local_pos then
        return string.format("[%s]", label)
    end

    return string.format("[%s] %d/%d", label, local_pos, total)
end

-- Initialize immediately on plugin load
initialize_plugin()

-- Save global instance and set loaded flag
_G._vertical_bufferline_init_loaded = true
_G._vertical_bufferline_init_instance = M

return M
