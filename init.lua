-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/init.lua

local M = {}

local api = vim.api

-- Namespace for our highlights
local ns_id = api.nvim_create_namespace("VerticalBufferline")

-- Default highlights
api.nvim_set_hl(0, "VBufferLineCurrent", { link = "Visual", default = true })
api.nvim_set_hl(0, "VBufferLineVisible", { link = "TabLineSel", default = true })
api.nvim_set_hl(0, "VBufferLineModified", { fg = "#e5c07b", italic = true, default = true })
api.nvim_set_hl(0, "VBufferLineInactive", { link = "TabLine", default = true })
api.nvim_set_hl(0, "VBufferLineError", { fg = "#e06c75", default = true })
api.nvim_set_hl(0, "VBufferLineWarning", { fg = "#e5c07b", default = true })

-- Pick highlights matching bufferline's style
-- Copy the exact colors from BufferLine groups
local function setup_pick_highlights()
    -- Get the actual BufferLine highlight groups
    local bufferline_pick = vim.api.nvim_get_hl(0, {name = "BufferLinePick"})
    local bufferline_pick_visible = vim.api.nvim_get_hl(0, {name = "BufferLinePickVisible"})
    local bufferline_pick_selected = vim.api.nvim_get_hl(0, {name = "BufferLinePickSelected"})
    
    -- Set our highlights to match exactly
    if next(bufferline_pick) then
        api.nvim_set_hl(0, "VBufferLinePick", bufferline_pick)
    else
        api.nvim_set_hl(0, "VBufferLinePick", { fg = "#e06c75", bold = true, italic = true })
    end
    
    if next(bufferline_pick_visible) then
        api.nvim_set_hl(0, "VBufferLinePickVisible", bufferline_pick_visible)
    else
        api.nvim_set_hl(0, "VBufferLinePickVisible", { fg = "#e06c75", bold = true, italic = true })
    end
    
    if next(bufferline_pick_selected) then
        api.nvim_set_hl(0, "VBufferLinePickSelected", bufferline_pick_selected)
    else
        api.nvim_set_hl(0, "VBufferLinePickSelected", { fg = "#e06c75", bold = true, italic = true })
    end
end

-- Set up highlights initially
setup_pick_highlights()

local config = {
    width = 40,
}

local state = {
    win_id = nil,
    buf_id = nil,
    is_sidebar_open = false,
    line_to_buffer_id = {}, -- Maps a line number in our window to a buffer ID
    hint_to_buffer_id = {}, -- Maps a hint character to a buffer ID
    was_picking = false, -- Track picking mode state to avoid spam
}

--- Refreshes the sidebar content with the current list of buffers.
function M.refresh()
    if not state.is_sidebar_open or not api.nvim_win_is_valid(state.win_id) then return end

    local bufferline_state = require('bufferline.state')
    if not bufferline_state or not bufferline_state.components then return end

    local components = bufferline_state.components
    local current_buffer_id = api.nvim_get_current_buf()
    
    -- Debug: Check bufferline state
    local is_picking = false
    local debug_info = ""
    
    -- Try different ways to detect picking mode
    if bufferline_state.is_picking then
        is_picking = true
        debug_info = debug_info .. "is_picking=true "
    end
    
    -- Check if any component has picking-related text
    for _, comp in ipairs(components) do
        if comp.text and comp.text:match("^%w") and #comp.text == 1 then
            is_picking = true
            debug_info = debug_info .. "found_hint_text "
            break
        end
    end
    
    -- Detect picking mode state changes
    if is_picking and not state.was_picking then
        state.was_picking = true
        
        -- Start highlight application timer during picking mode
        local highlight_timer = vim.loop.new_timer()
        highlight_timer:start(0, 50, vim.schedule_wrap(function()
            local current_state = require('bufferline.state')
            if current_state.is_picking and state.is_sidebar_open then
                M.apply_picking_highlights()
            else
                highlight_timer:stop()
                highlight_timer:close()
            end
        end))
    elseif not is_picking and state.was_picking then
        state.was_picking = false
    end

    local lines_text = {}
    local new_line_map = {}

    -- Clear old highlights
    api.nvim_buf_clear_namespace(state.buf_id, ns_id, 0, -1)

    api.nvim_buf_set_option(state.buf_id, "modifiable", true)

    for i, component in ipairs(components) do
        if component.id and component.name then
            local prefix = "  "
            local modified_indicator = ""
            
            -- Check if buffer is modified
            if api.nvim_buf_get_option(component.id, "modified") then
                modified_indicator = "● "
            end
            
            local icon = component.icon or ""
            if icon == "" then
                -- Fallback to basic file type detection
                local extension = component.name:match("%.([^%.]+)$")
                if extension then
                    local icon_map = {
                        lua = "🌙",
                        js = "📄",
                        py = "🐍",
                        go = "🟢",
                        rs = "🦀",
                        md = "📝",
                        txt = "📄",
                        json = "📋",
                        yaml = "📋",
                        yml = "📋",
                    }
                    icon = icon_map[extension] or "📄"
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
            
            -- Build line content
            local line_text
            local pick_highlight_group = nil
            local pick_highlight_end = 0
            
            if letter and is_picking then
                -- In picking mode: show hint character + buffer name
                -- Format: "a init.lua" instead of "[a] init.lua"
                line_text = letter .. " " .. modified_indicator .. icon .. " " .. component.name
                pick_highlight_end = 1  -- Only highlight the letter character
                
                -- Choose appropriate pick highlight based on buffer state
                if component.id == current_buffer_id then
                    pick_highlight_group = "VBufferLinePickSelected"
                elseif component.focused then
                    pick_highlight_group = "VBufferLinePickVisible"
                else
                    pick_highlight_group = "VBufferLinePick"
                end
                
            else
                -- Normal mode: regular display
                line_text = prefix .. modified_indicator .. icon .. " " .. component.name
            end
            
            table.insert(lines_text, line_text)
            new_line_map[i] = component.id
            
            -- Apply highlights
            if is_picking and pick_highlight_group then
                -- Highlight just the letter character in picking mode
                api.nvim_buf_add_highlight(state.buf_id, ns_id, pick_highlight_group, i - 1, 0, pick_highlight_end)
                
                -- Highlight the rest of the line normally, but only if there's content after the pick highlight
                if pick_highlight_end < #line_text then
                    local normal_highlight_group = "VBufferLineInactive"
                    if component.id == current_buffer_id then
                        normal_highlight_group = "VBufferLineCurrent"
                    elseif component.focused then
                        normal_highlight_group = "VBufferLineVisible"
                    elseif api.nvim_buf_get_option(component.id, "modified") then
                        normal_highlight_group = "VBufferLineModified"
                    end
                    api.nvim_buf_add_highlight(state.buf_id, ns_id, normal_highlight_group, i - 1, pick_highlight_end, -1)
                end
            else
                -- Normal highlighting for non-picking mode
                local highlight_group = "VBufferLineInactive"
                if component.id == current_buffer_id then
                    highlight_group = "VBufferLineCurrent"
                elseif component.focused then
                    highlight_group = "VBufferLineVisible"
                elseif api.nvim_buf_get_option(component.id, "modified") then
                    highlight_group = "VBufferLineModified"
                end
                api.nvim_buf_add_highlight(state.buf_id, ns_id, highlight_group, i - 1, 0, -1)
            end
        end
    end

    api.nvim_buf_set_lines(state.buf_id, 0, -1, false, lines_text)
    api.nvim_buf_set_option(state.buf_id, "modifiable", false)
    state.line_to_buffer_id = new_line_map
    
end


-- Make setup_pick_highlights available globally
M.setup_pick_highlights = setup_pick_highlights

--- Apply picking highlights continuously during picking mode
function M.apply_picking_highlights()
    if not state.is_sidebar_open then return end
    
    local bufferline_state = require('bufferline.state')
    if not bufferline_state.is_picking then return end
    
    -- Re-setup highlights to ensure they're current
    setup_pick_highlights()
    
    -- Get current components
    local components = bufferline_state.components
    local current_buffer_id = api.nvim_get_current_buf()
    
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
                -- Choose appropriate pick highlight based on buffer state
                local pick_highlight_group
                if component.id == current_buffer_id then
                    pick_highlight_group = "VBufferLinePickSelected"
                elseif component.focused then
                    pick_highlight_group = "VBufferLinePickVisible"
                else
                    pick_highlight_group = "VBufferLinePick"
                end
                
                -- Apply highlight with both namespace and without
                api.nvim_buf_add_highlight(state.buf_id, 0, pick_highlight_group, i - 1, 0, 1)
                api.nvim_buf_add_highlight(state.buf_id, ns_id, pick_highlight_group, i - 1, 0, 1)
            end
        end
    end
    
    vim.cmd("redraw!")
end



--- Closes the sidebar window.
function M.close_sidebar()
    if not state.is_sidebar_open or not api.nvim_win_is_valid(state.win_id) then return end
    local current_win = api.nvim_get_current_win()
    api.nvim_set_current_win(state.win_id)
    vim.cmd("close")
    if api.nvim_win_is_valid(current_win) then
        api.nvim_set_current_win(current_win)
    end
    state.is_sidebar_open = false
    state.win_id = nil
end

--- Opens the sidebar window.
local function open_sidebar()
    if state.is_sidebar_open then return end
    local buf_id = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf_id, 'bufhidden', 'wipe')
    local current_win = api.nvim_get_current_win()
    vim.cmd("botright vsplit")
    local new_win_id = api.nvim_get_current_win()
    api.nvim_win_set_buf(new_win_id, buf_id)
    api.nvim_win_set_width(new_win_id, config.width)
    api.nvim_win_set_option(new_win_id, 'number', false)
    api.nvim_win_set_option(new_win_id, 'relativenumber', false)
    api.nvim_win_set_option(new_win_id, 'cursorline', true)
    state.win_id = new_win_id
    state.buf_id = buf_id
    state.is_sidebar_open = true

    local keymap_opts = { noremap = true, silent = true }
    api.nvim_buf_set_keymap(buf_id, "n", "j", "j", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "k", "k", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "<CR>", ":lua require('vertical-bufferline').handle_selection()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "d", ":lua require('vertical-bufferline').close_buffer()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "q", ":lua require('vertical-bufferline').close_sidebar()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "<Esc>", ":lua require('vertical-bufferline').close_sidebar()<CR>", keymap_opts)

    api.nvim_set_current_win(current_win)
    M.refresh()
end

function M.handle_selection()
    if not state.is_sidebar_open then return end
    local line_number = api.nvim_win_get_cursor(state.win_id)[1]
    local bufnr = state.line_to_buffer_id[line_number]
    if bufnr and api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr) then
        local success, err = pcall(api.nvim_set_current_buf, bufnr)
        if not success then
            vim.notify("Error switching to buffer: " .. err, vim.log.levels.ERROR)
        end
    end
end

function M.close_buffer()
    if not state.is_sidebar_open then return end
    local line_number = api.nvim_win_get_cursor(state.win_id)[1]
    local bufnr = state.line_to_buffer_id[line_number]
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

--- Hook into bufferline's UI refresh to mirror its state
local function setup_bufferline_hook()
    -- Try to hook into bufferline's UI refresh
    local bufferline_ui = require('bufferline.ui')
    local original_refresh = bufferline_ui.refresh
    
    bufferline_ui.refresh = function(...)
        local result = original_refresh(...)
        -- Immediately update our sidebar synchronously during picking
        if state.is_sidebar_open then
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

--- Toggles the visibility of the sidebar.
function M.toggle()
    if state.is_sidebar_open then
        M.close_sidebar()
        -- Remove autocommands when closing
        api.nvim_command("autocmd! VerticalBufferline")
    else
        open_sidebar()
        -- Set up autocommands to refresh on buffer changes
        api.nvim_command("augroup VerticalBufferline")
        api.nvim_command("autocmd!")
        api.nvim_command("autocmd BufEnter,BufDelete,BufWipeout * lua require('vertical-bufferline').refresh()")
        api.nvim_command("augroup END")
        
        -- Set up the bufferline hook
        setup_bufferline_hook()
        
        -- Re-setup highlights to ensure they match bufferline
        setup_pick_highlights()
    end
end

return M