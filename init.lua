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

-- Default highlights
api.nvim_set_hl(0, config_module.HIGHLIGHTS.CURRENT, { link = "Visual", default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.VISIBLE, { link = "TabLineSel", default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.MODIFIED, { fg = config_module.COLORS.YELLOW, italic = true, default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.INACTIVE, { link = "TabLine", default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.ERROR, { fg = config_module.COLORS.RED, default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.WARNING, { fg = config_module.COLORS.YELLOW, default = true })

-- Group header highlights - linked to semantic highlight groups for color scheme compatibility
api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_ACTIVE, { link = "Function", bold = true, default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_INACTIVE, { link = "Comment", bold = true, default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_NUMBER, { link = "Number", bold = true, default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_SEPARATOR, { link = "Comment", default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.GROUP_MARKER, { link = "Special", bold = true, default = true })

-- Path highlights - linked to semantic highlight groups for color scheme compatibility
api.nvim_set_hl(0, config_module.HIGHLIGHTS.PATH, { link = "Comment", italic = true, default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.PATH_CURRENT, { link = "Comment", italic = true, default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.PATH_VISIBLE, { link = "Comment", italic = true, default = true })

-- Filename highlights - linked to semantic highlight groups for color scheme compatibility
api.nvim_set_hl(0, config_module.HIGHLIGHTS.FILENAME, { link = "Normal", default = true })  -- No special highlighting for normal files
api.nvim_set_hl(0, config_module.HIGHLIGHTS.FILENAME_CURRENT, { link = "Title", bold = true, underline = true, default = true })
api.nvim_set_hl(0, config_module.HIGHLIGHTS.FILENAME_VISIBLE, { link = "String", bold = true, default = true })

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

-- Apply buffer highlighting for a single buffer line (basic highlighting only)
local function apply_buffer_highlighting(line_info, component, actual_line_number, current_buffer_id, is_picking)
    -- Apply basic buffer state highlighting
    local normal_highlight_group = config_module.HIGHLIGHTS.INACTIVE
    if component.id == current_buffer_id then
        normal_highlight_group = config_module.HIGHLIGHTS.CURRENT
    elseif component.focused then
        normal_highlight_group = config_module.HIGHLIGHTS.VISIBLE
    elseif api.nvim_buf_is_valid(component.id) and api.nvim_buf_get_option(component.id, "modified") then
        normal_highlight_group = config_module.HIGHLIGHTS.MODIFIED
    end
    
    -- Apply base highlight to entire line first
    api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, normal_highlight_group, actual_line_number - 1, 0, -1)
    
    -- Apply separate highlighting for prefix and filename if prefix exists (before picking mode to avoid conflicts)
    if line_info.prefix_info then
        local line_text = line_info.text
        
        -- Find the position of the filename part in the line
        local search_pattern = line_info.prefix_info.prefix .. line_info.prefix_info.filename
        local filename_start = line_text:find(search_pattern, 1, true)  -- Use plain text search to avoid regex issues
        if filename_start then
            local prefix_start = filename_start - 1  -- Convert to 0-based
            local prefix_end = prefix_start + #line_info.prefix_info.prefix
            local filename_end = prefix_end + #line_info.prefix_info.filename
            
            -- Determine appropriate highlight groups based on buffer state
            local path_highlight, filename_highlight
            if component.id == current_buffer_id then
                path_highlight = config_module.HIGHLIGHTS.PATH_CURRENT
                filename_highlight = config_module.HIGHLIGHTS.FILENAME_CURRENT
            elseif component.focused then
                path_highlight = config_module.HIGHLIGHTS.PATH_VISIBLE
                filename_highlight = config_module.HIGHLIGHTS.FILENAME_VISIBLE
            else
                path_highlight = config_module.HIGHLIGHTS.PATH
                filename_highlight = config_module.HIGHLIGHTS.FILENAME
            end
            
            -- Apply prefix highlight (path-style)
            api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, path_highlight, actual_line_number - 1, prefix_start, prefix_end)
            
            -- Apply filename highlight
            api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, filename_highlight, actual_line_number - 1, prefix_end, filename_end)
        end
    end
    
    -- Handle picking mode highlight (override the letter part if in picking mode) - apply last
    if is_picking and line_info.pick_highlight_group then
        local letter_start = #line_info.tree_prefix
        local letter_end = letter_start + 1
        api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, line_info.pick_highlight_group, actual_line_number - 1, letter_start, letter_end)
    end
end

-- Apply path-specific highlighting for path lines
local function apply_path_highlighting(component, path_line_number, current_buffer_id)
    local path_highlight_group = config_module.HIGHLIGHTS.PATH
    if component.id == current_buffer_id then
        path_highlight_group = config_module.HIGHLIGHTS.PATH_CURRENT
    elseif component.focused then
        path_highlight_group = config_module.HIGHLIGHTS.PATH_VISIBLE
    end
    
    -- Only highlight the path part, not the tree prefix
    local line_text = api.nvim_buf_get_lines(state_module.get_buf_id(), path_line_number - 1, path_line_number, false)[1] or ""
    local path_start = nil
    -- Find the tree marker │ and then the first non-space character after it
    local tree_marker_pos = line_text:find("│")
    if tree_marker_pos then
        path_start = line_text:find("%S", tree_marker_pos + 1)
    else
        -- For last buffer (no │), skip the initial spaces and find first non-space character
        path_start = line_text:find("%S")
    end
    
    if path_start then
        api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, path_highlight_group, path_line_number - 1, path_start - 1, -1)
    end
end

-- Render buffers within a single group
local function render_group_buffers(group_components, current_buffer_id, is_picking, lines_text, new_line_map)
    for j, component in ipairs(group_components) do
        if component.id and component.name and api.nvim_buf_is_valid(component.id) then
            local line_info = create_buffer_line(component, j, #group_components, current_buffer_id, is_picking)

            -- Add main buffer line
            table.insert(lines_text, line_info.text)
            local main_line_number = #lines_text
            new_line_map[main_line_number] = component.id

            -- Apply highlights for main line
            apply_buffer_highlighting(line_info, component, main_line_number, current_buffer_id, is_picking)
            
            -- Add path line if it exists
            if line_info.has_path and line_info.path_line then
                table.insert(lines_text, line_info.path_line)
                local path_line_number = #lines_text
                
                -- Path line also maps to the same buffer for click handling
                new_line_map[path_line_number] = component.id
                
                -- Apply path-specific highlighting
                apply_path_highlighting(component, path_line_number, current_buffer_id)
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
local function render_all_groups(active_group, components, current_buffer_id, is_picking, lines_text, new_line_map, group_header_lines)
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
            render_group_buffers(group_components, current_buffer_id, is_picking, lines_text, new_line_map)

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

    -- Clear old highlights
    api.nvim_buf_clear_namespace(state_module.get_buf_id(), ns_id, 0, -1)

    -- Render all groups with their buffers
    local remaining_components = render_all_groups(active_group, components, current_buffer_id, is_picking, lines_text, new_line_map, group_header_lines)

    -- Finalize buffer display (set lines but keep modifiable)
    finalize_buffer_display(lines_text, new_line_map)
    
    -- Apply group header highlights AFTER setting buffer content
    apply_group_highlights(group_header_lines, lines_text)
    
    -- Force reapply our custom highlights as the final step
    vim.schedule(function()
        if state_module.is_sidebar_open() and api.nvim_buf_is_valid(state_module.get_buf_id()) then
            -- Reapply buffer and path highlights with precise positioning
            for line_num, buffer_id in pairs(new_line_map) do
                local line_text = api.nvim_buf_get_lines(state_module.get_buf_id(), line_num - 1, line_num, false)[1] or ""
                if line_text:match("%.") then  -- Filename line
                    -- Find the filename part in the line (after icon and spaces)
                    local filename_start = nil
                    -- Look for pattern like "🌙 filename.ext" - find the filename after the icon
                    local icon_pos = line_text:find("[🌙📄🐍🟢🦀📝📋]")
                    if icon_pos then
                        filename_start = line_text:find("%S", icon_pos + 4) -- Skip icon and spaces
                    else
                        -- Fallback: find after common prefix patterns
                        filename_start = line_text:find("[%w_%-%.]+%.[%w]+")
                    end
                    
                    if filename_start then
                        local highlight_group = config_module.HIGHLIGHTS.FILENAME
                        if buffer_id == current_buffer_id then
                            highlight_group = config_module.HIGHLIGHTS.FILENAME_CURRENT
                        end
                        -- Only highlight the filename part, not the entire line
                        api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, highlight_group, line_num - 1, filename_start - 1, -1)
                    end
                elseif line_text:match("/") then  -- Path line
                    -- Only highlight the path part, not the tree structure
                    local path_start = nil
                    -- Find the tree marker │ and then the first non-space character after it
                    local tree_marker_pos = line_text:find("│")
                    if tree_marker_pos then
                        path_start = line_text:find("%S", tree_marker_pos + 1)
                    else
                        -- For last buffer (no │), skip the initial spaces and find first non-space character
                        path_start = line_text:find("%S")
                    end
                    
                    if path_start then
                        local highlight_group = config_module.HIGHLIGHTS.PATH
                        if buffer_id == current_buffer_id then
                            highlight_group = config_module.HIGHLIGHTS.PATH_CURRENT
                        end
                        -- Only highlight from the path start to end, leaving tree prefix normal
                        api.nvim_buf_add_highlight(state_module.get_buf_id(), ns_id, highlight_group, line_num - 1, path_start - 1, -1)
                    end
                end
            end
        end
    end)
    
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

-- Force refresh highlights - manual testing function
function M.force_refresh_highlights()
    if not state_module.is_sidebar_open() then
        print("Sidebar not open")
        return
    end
    
    local buf_id = state_module.get_buf_id()
    if not buf_id or not api.nvim_buf_is_valid(buf_id) then
        print("Invalid buffer")
        return
    end
    
    -- Clear all highlights first
    api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)
    
    -- Apply test highlights manually to see if they work
    local total_lines = api.nvim_buf_line_count(buf_id)
    for line = 1, math.min(total_lines, 10) do
        local line_text = api.nvim_buf_get_lines(buf_id, line - 1, line, false)[1] or ""
        if line_text:match("%.") then  -- Looks like a filename line
            api.nvim_buf_add_highlight(buf_id, ns_id, config_module.HIGHLIGHTS.FILENAME_CURRENT, line - 1, 0, -1)
            print(string.format("Applied FILENAME_CURRENT to line %d: %s", line, line_text))
        elseif line_text:match("/") then  -- Looks like a path line
            api.nvim_buf_add_highlight(buf_id, ns_id, config_module.HIGHLIGHTS.PATH_CURRENT, line - 1, 0, -1)
            print(string.format("Applied PATH_CURRENT to line %d: %s", line, line_text))
        end
    end
    
    vim.cmd("redraw!")
end

-- Initialize immediately on plugin load
initialize_plugin()

-- Save global instance and set loaded flag
_G._vertical_bufferline_init_loaded = true
_G._vertical_bufferline_init_instance = M

return M
