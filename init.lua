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
end

-- Call setup function immediately
setup_highlights()
api.nvim_set_hl(0, config_module.HIGHLIGHTS.ERROR, { fg = config_module.COLORS.RED, default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.WARNING, { fg = config_module.COLORS.YELLOW, default = true })

-- Group header highlights - linked to semantic highlight groups for color scheme compatibility
api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_ACTIVE, { link = "Function", bold = true, default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_INACTIVE, { link = "Comment", bold = true, default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_NUMBER, { link = "Number", bold = true, default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_SEPARATOR, { link = "Comment", default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_MARKER, { link = "Special", bold = true, default = true })


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

local config = {
    width = config_module.DEFAULTS.width,
}

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

        -- Start highlight application timer during picking mode
        local timer = vim.loop.new_timer()
        timer:start(0, config_module.UI.HIGHLIGHT_UPDATE_INTERVAL, vim.schedule_wrap(function()
            local current_state = require('bufferline.state')
            if current_state.is_picking and state_module.is_sidebar_open() then
                M.apply_picking_highlights()
            else
                state_module.stop_highlight_timer()
            end
        end))
        state_module.set_highlight_timer(timer)
    elseif not is_picking and state_module.was_picking() then
        state_module.set_was_picking(false)
        -- Clean up timer when exiting picking mode
        state_module.stop_highlight_timer()
    end

    return is_picking
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

-- Create individual buffer line with proper formatting and highlights
local function create_buffer_line(component, j, total_components, current_buffer_id, is_picking)
    local is_last = (j == total_components)
    local tree_prefix = is_last and (" " .. config_module.UI.TREE_LAST) or (" " .. config_module.UI.TREE_BRANCH)
    local modified_indicator = ""

    -- Check if buffer is modified
    if api.nvim_buf_is_valid(component.id) and api.nvim_buf_get_option(component.id, "modified") then
        modified_indicator = "● "
    end

    local icon = component.icon or ""
    if icon == "" then
        -- Fallback to basic file type detection
        local extension = component.name:match("%.([^%.]+)$")
        if extension then
            icon = config_module.ICONS[extension] or config_module.ICONS.default
        end
    end

    -- Get letter for picking mode
    local ok, element = pcall(function() return component:as_element() end)
    local letter = nil
    if ok and element and element.letter then
        letter = element.letter
    elseif component.letter then
        letter = component.letter
    end

    -- Add number display (1-9 correspond to <leader>1-9, 10 uses 0)
    local number_display = j <= 9 and tostring(j) or "0"
    if j > config_module.UI.MAX_DISPLAY_NUMBER then
        number_display = config_module.UI.NUMBER_OVERFLOW_CHAR
    end

    -- Add arrow marker for current buffer
    local current_marker = ""
    if component.id == current_buffer_id then
        current_marker = config_module.UI.CURRENT_BUFFER_MARKER
    end

    local line_text
    local pick_highlight_group = nil
    local pick_highlight_end = 0

    if letter and is_picking then
        -- In picking mode: show hint character + buffer name with tree structure
        line_text = tree_prefix .. letter .. " " .. current_marker .. number_display .. " " .. modified_indicator .. icon .. " " .. component.name
        pick_highlight_end = #tree_prefix + 1  -- Only highlight the letter character

        -- Choose appropriate pick highlight based on buffer state
        if component.id == current_buffer_id then
            pick_highlight_group = config_module.HIGHLIGHTS.PICK_SELECTED
        elseif component.focused then
            pick_highlight_group = config_module.HIGHLIGHTS.PICK_VISIBLE
        else
            pick_highlight_group = config_module.HIGHLIGHTS.PICK
        end
    else
        -- Normal mode: regular display with tree structure, current marker and number
        line_text = tree_prefix .. current_marker .. number_display .. " " .. modified_indicator .. icon .. " " .. component.name
    end

    -- Extract path information for multi-line display
    local path_dir, display_name = get_buffer_path_info(component)
    
    -- Use extracted filename or fallback to original name
    local final_name = display_name or component.name
    
    -- Build display name with minimal prefix if available
    local display_with_prefix = final_name
    local prefix_info = nil
    if component.minimal_prefix and component.minimal_prefix.prefix and component.minimal_prefix.prefix ~= "" then
        display_with_prefix = component.minimal_prefix.prefix .. component.minimal_prefix.filename
        prefix_info = {
            prefix = component.minimal_prefix.prefix,
            filename = component.minimal_prefix.filename
        }
    end
    
    -- Replace component.name with prefixed filename in the line text
    local name_in_line = display_with_prefix
    if letter and is_picking then
        line_text = tree_prefix .. letter .. " " .. current_marker .. number_display .. " " .. modified_indicator .. icon .. " " .. name_in_line
    else
        line_text = tree_prefix .. current_marker .. number_display .. " " .. modified_indicator .. icon .. " " .. name_in_line
    end
    
    -- Create path line if path exists and path display is enabled
    local path_line = nil
    if path_dir and config_module.DEFAULTS.show_path and path_dir ~= "." then
        -- Tree continuation should match the tree structure: use spaces for last item, vertical line for others
        local tree_continuation = is_last and "       " or " │     "  -- Match tree structure indentation
        path_line = tree_continuation .. path_dir .. "/"
    end
    
    return {
        text = line_text,
        path_line = path_line,
        tree_prefix = tree_prefix,
        pick_highlight_group = pick_highlight_group,
        pick_highlight_end = pick_highlight_end,
        has_path = path_line ~= nil,
        prefix_info = prefix_info
    }
end

-- Apply all highlighting for a single buffer line (unified highlighting function)
local function apply_buffer_highlighting(line_info, component, actual_line_number, current_buffer_id, is_picking, is_in_active_group)
    if not line_info or not component then return end
    
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
local function render_group_buffers(group_components, current_buffer_id, is_picking, lines_text, new_line_map, line_types, line_components, line_group_context)
    for j, component in ipairs(group_components) do
        if component.id and component.name and api.nvim_buf_is_valid(component.id) then
            local line_info = create_buffer_line(component, j, #group_components, current_buffer_id, is_picking)

            -- Add main buffer line
            table.insert(lines_text, line_info.text)
            local main_line_number = #lines_text
            new_line_map[main_line_number] = component.id
            line_types[main_line_number] = "buffer"  -- Record this as a buffer line
            line_components[main_line_number] = component  -- Store specific component for this line
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

    -- Add visual separator (except for first group)
    if i > config_module.SYSTEM.FIRST_INDEX then
        table.insert(lines_text, "")  -- Empty line separator
        local separator_line_num = #lines_text
        table.insert(lines_text, config_module.UI.GROUP_SEPARATOR)  -- Separator line
        table.insert(group_header_lines, {line = separator_line_num, type = "separator"})
    end

    local group_line = string.format("[%d] %s %s (%d buffers)",
        i, group_marker, group_name_display, buffer_count)
    table.insert(lines_text, group_line)

    -- Record group header line info
    table.insert(group_header_lines, {
        line = #lines_text - config_module.SYSTEM.ZERO_BASED_OFFSET,  -- 0-based line number
        type = "header",
        is_active = is_active,
        group_number = i
    })
end

-- Render all groups with their buffers
local function render_all_groups(active_group, components, current_buffer_id, is_picking, lines_text, new_line_map, group_header_lines, line_types, all_components, line_components, line_group_context)
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
                table.insert(lines_text, "  " .. config_module.UI.TREE_LAST .. config_module.UI.TREE_EMPTY)
            end

            -- Render group buffers
            line_group_context.current_group_id = group.id  -- Set current group context
            render_group_buffers(group_components, current_buffer_id, is_picking, lines_text, new_line_map, line_types, line_components, line_group_context)
            
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
            -- Separator line highlight
            api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, config_module.HIGHLIGHTS.GROUP_SEPARATOR, header_info.line, 0, -1)
        elseif header_info.type == "header" then
            -- Group title line overall highlight
            local group_highlight = header_info.is_active and config_module.HIGHLIGHTS.GROUP_ACTIVE or config_module.HIGHLIGHTS.GROUP_INACTIVE
            api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, group_highlight, header_info.line, 0, -1)

            -- Highlight group number [1] - include the brackets for consistency
            api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, config_module.HIGHLIGHTS.GROUP_NUMBER, header_info.line, 0, config_module.SYSTEM.GROUP_NUMBER_END)

            -- Highlight group marker (● or ○)
            local line_text = lines_text[header_info.line + 1] or ""
            local marker_start = string.find(line_text, "[●○]")
            if marker_start then
                api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, config_module.HIGHLIGHTS.GROUP_MARKER, header_info.line, marker_start - 1, marker_start)
            end
        end
    end
end

-- Finalize buffer display with lines and mapping
local function finalize_buffer_display(lines_text, new_line_map)
    api.nvim_buf_set_option(state_module.get_buf_id(), "modifiable", true)
    api.nvim_buf_set_lines(state_module.get_buf_id(), 0, -1, false, lines_text)
    state_module.set_line_to_buffer_id(new_line_map)
end

-- Complete buffer setup and make it read-only
local function complete_buffer_setup()
    api.nvim_buf_set_option(state_module.get_buf_id(), "modifiable", false)
end

--- Refreshes the sidebar content with the current list of buffers.
function M.refresh()
    local refresh_data = validate_and_initialize_refresh()
    if not refresh_data then return end

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
    local line_group_context = {}  -- Store which group each line belongs to

    -- Render all groups with their buffers (without applying highlights yet)
    local remaining_components = render_all_groups(active_group, components, current_buffer_id, is_picking, lines_text, new_line_map, group_header_lines, line_types, all_components, line_components, line_group_context)

    -- Finalize buffer display (set lines but keep modifiable) - this clears highlights
    finalize_buffer_display(lines_text, new_line_map)
    
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
            -- Determine if this line belongs to the active group
            local line_group_id = line_group_context[line_num]
            local is_in_active_group = false
            if active_group and line_group_id then
                is_in_active_group = (line_group_id == active_group.id)
            end
            
            if line_type == "path" then
                -- This is a path line - apply path-specific highlighting
                apply_path_highlighting(component, line_num, current_buffer_id, is_in_active_group)
            elseif line_type == "buffer" then
                -- This is a main buffer line - apply buffer highlighting
                local line_text = api.nvim_buf_get_lines(state_module.get_buf_id(), line_num - 1, line_num, false)[1] or ""
                
                -- Create a minimal line_info for highlighting (consistent with path line approach)
                local line_info = {
                    text = line_text,  -- Use original line text
                    tree_prefix = " ├─ ",  -- Use consistent tree prefix
                    prefix_info = component.minimal_prefix  -- This contains prefix information if available
                }
                
                -- Apply highlighting with group context
                apply_buffer_highlighting(line_info, component, line_num, current_buffer_id, is_picking, is_in_active_group)
            end
            -- Note: group headers and separators are handled by apply_group_highlights above
        end
    end
    
    
    -- Complete buffer setup (make read-only)
    complete_buffer_setup()
end


-- Make setup_pick_highlights available globally
M.setup_pick_highlights = setup_pick_highlights

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
                -- Find the actual line number of this buffer in sidebar
                local actual_line_number = nil
                for line_num, buffer_id in pairs(state_module.get_line_to_buffer_id()) do
                    if buffer_id == component.id then
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

                    -- Calculate correct highlight position, skip tree prefix
                    -- Determine if this is the last buffer or middle buffer
                    local is_last = (i == #components)
                    local tree_prefix = is_last and (" " .. config_module.UI.TREE_LAST) or (" " .. config_module.UI.TREE_BRANCH)
                    local highlight_start = #tree_prefix
                    local highlight_end = highlight_start + 1

                    -- Apply highlight with both namespace and without
                    api.nvim_buf_add_highlight(state_module.get_buf_id(), 0, pick_highlight_group, actual_line_number - 1, highlight_start, highlight_end)
                    api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, pick_highlight_group, actual_line_number - 1, highlight_start, highlight_end)
                end
            end
        end
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

    state_module.close_sidebar()
end

--- Opens the sidebar window.
local function open_sidebar()
    if state_module.is_sidebar_open() then return end
    local buf_id = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf_id, 'bufhidden', 'wipe')
    local current_win = api.nvim_get_current_win()
    vim.cmd("botright vsplit")
    local new_win_id = api.nvim_get_current_win()
    api.nvim_win_set_buf(new_win_id, buf_id)
    api.nvim_win_set_width(new_win_id, config.width)
    api.nvim_win_set_option(new_win_id, 'winfixwidth', true)  -- Prevent window from auto-resizing width
    api.nvim_win_set_option(new_win_id, 'number', false)
    api.nvim_win_set_option(new_win_id, 'relativenumber', false)
    api.nvim_win_set_option(new_win_id, 'cursorline', false)
    api.nvim_win_set_option(new_win_id, 'cursorcolumn', false)
    state_module.set_win_id(new_win_id)
    state_module.set_buf_id(buf_id)
    state_module.set_sidebar_open(true)

    local keymap_opts = { noremap = true, silent = true }
    api.nvim_buf_set_keymap(buf_id, "n", "j", "j", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "k", "k", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "<CR>", ":lua require('vertical-bufferline').handle_selection()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "d", ":lua require('vertical-bufferline').smart_close_buffer()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "x", ":lua require('vertical-bufferline').remove_from_group()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "D", ":lua require('vertical-bufferline').close_buffer()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "q", ":lua require('vertical-bufferline').close_sidebar()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "<Esc>", ":lua require('vertical-bufferline').close_sidebar()<CR>", keymap_opts)

    api.nvim_set_current_win(current_win)
    M.refresh()
end

--- Handle buffer selection from sidebar
function M.handle_selection()
    if not state_module.is_sidebar_open() then return end
    local line_number = api.nvim_win_get_cursor(state_module.get_win_id())[1]
    local bufnr = state_module.get_buffer_for_line(line_number)
    if bufnr and api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr) then
        -- Find the main window (not the sidebar)
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

        -- After successfully switching buffer, check if we need to switch active group
        local buffer_group = groups.find_buffer_group(bufnr)
        if buffer_group then
            local current_active_group = groups.get_active_group()
            if not current_active_group or current_active_group.id ~= buffer_group.id then
                -- Switch to the group containing this buffer
                groups.set_active_group(buffer_group.id)
            end
        end
    end
end

--- Close the selected buffer from sidebar
function M.close_buffer()
    if not state_module.is_sidebar_open() then return end
    local line_number = api.nvim_win_get_cursor(state_module.get_win_id())[1]
    local bufnr = state_module.get_buffer_for_line(line_number)
    if bufnr and api.nvim_buf_is_valid(bufnr) then
        -- Check if buffer is modified
        if api.nvim_buf_get_option(bufnr, "modified") then
            vim.notify("Buffer is modified, use :bd! to force close", vim.log.levels.WARN)
            return
        end

        local success, err = pcall(vim.cmd, "bd " .. bufnr)
        if success then
            vim.schedule(function()
                M.refresh()
            end)
        else
            vim.notify("Error closing buffer: " .. err, vim.log.levels.ERROR)
        end
    end
end

--- Remove buffer from current group via sidebar
function M.remove_from_group()
    if not state_module.is_sidebar_open() then return end
    local line_number = api.nvim_win_get_cursor(state_module.get_win_id())[1]
    local bufnr = state_module.get_buffer_for_line(line_number)
    if bufnr and api.nvim_buf_is_valid(bufnr) then
        -- Call bufferline's close command directly, let bufferline handle buffer removal
        -- This will automatically trigger our sync logic
        local success, err = pcall(vim.cmd, "bd " .. bufnr)
        if success then
            vim.notify("Buffer closed", vim.log.levels.INFO)
        else
            vim.notify("Error closing buffer: " .. (err or "unknown"), vim.log.levels.ERROR)
        end
    end
end

--- Smart close buffer with group-aware logic
function M.smart_close_buffer()
    if not state_module.is_sidebar_open() then return end
    local line_number = api.nvim_win_get_cursor(state_module.get_win_id())[1]
    local bufnr = state_module.get_buffer_for_line(line_number)
    if bufnr and api.nvim_buf_is_valid(bufnr) then
        bufferline_integration.smart_close_buffer(bufnr)
        -- Add delayed cleanup and refresh
        vim.schedule(function()
            groups.cleanup_invalid_buffers()
            M.refresh()
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
            M.refresh()
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
                M.refresh()
                -- Apply highlights multiple times to fight bufferline's overwrites
                vim.schedule(function()
                    M.apply_picking_highlights()
                end)
                vim.cmd("redraw!")  -- Force immediate redraw
            else
                -- Use schedule for normal updates
                vim.schedule(function()
                    M.refresh()
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
        max_buffers_per_group = config_module.DEFAULTS.max_buffers_per_group,
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
    api.nvim_command("autocmd BufEnter,BufDelete,BufWipeout * lua require('vertical-bufferline').refresh_if_open()")
    api.nvim_command("autocmd WinClosed * lua require('vertical-bufferline').check_quit_condition()")
    api.nvim_command("augroup END")

    -- Setup bufferline hooks
    setup_bufferline_hook()

    -- Setup highlights
    setup_highlights()
    setup_pick_highlights()
end

--- Wrapper function to refresh only when sidebar is open
function M.refresh_if_open()
    if state_module.is_sidebar_open() then
        M.refresh()
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
                        M.refresh()
                    end
                end
            end, delay)
        end

        -- Ensure initial state displays correctly
        vim.schedule(function()
            M.refresh()
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

-- Debug function to test highlights
function M.debug_highlights()
    print("Testing highlights...")
    
    -- Test if highlight groups exist
    local test_groups = {
        config_module.HIGHLIGHTS.FILENAME,
        config_module.HIGHLIGHTS.FILENAME_CURRENT,
        config_module.HIGHLIGHTS.FILENAME_VISIBLE,
        config_module.HIGHLIGHTS.PATH,
        config_module.HIGHLIGHTS.PATH_CURRENT,
        config_module.HIGHLIGHTS.PATH_VISIBLE,
    }
    
    for _, group in ipairs(test_groups) do
        local hl = api.nvim_get_hl(0, {name = group})
        print(string.format("Highlight group %s: %s", group, vim.inspect(hl)))
    end
end

-- Initialize immediately on plugin load
initialize_plugin()

-- Save global instance and set loaded flag
_G._vertical_bufferline_init_loaded = true
_G._vertical_bufferline_init_instance = M

return M
