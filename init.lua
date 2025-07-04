-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/init.lua

local M = {}

local api = vim.api

-- 分组管理模块
local groups = require('vertical-bufferline.groups')
local commands = require('vertical-bufferline.commands')
local bufferline_integration = require('vertical-bufferline.bufferline-integration')

-- Namespace for our highlights
local ns_id = api.nvim_create_namespace("VerticalBufferline")

-- Default highlights
api.nvim_set_hl(0, "VBufferLineCurrent", { link = "Visual", default = true })
api.nvim_set_hl(0, "VBufferLineVisible", { link = "TabLineSel", default = true })
api.nvim_set_hl(0, "VBufferLineModified", { fg = "#e5c07b", italic = true, default = true })
api.nvim_set_hl(0, "VBufferLineInactive", { link = "TabLine", default = true })
api.nvim_set_hl(0, "VBufferLineError", { fg = "#e06c75", default = true })
api.nvim_set_hl(0, "VBufferLineWarning", { fg = "#e5c07b", default = true })

-- Group header highlights
api.nvim_set_hl(0, "VBufferLineGroupActive", { fg = "#61afef", bold = true, default = true })
api.nvim_set_hl(0, "VBufferLineGroupInactive", { fg = "#5c6370", bold = true, default = true })
api.nvim_set_hl(0, "VBufferLineGroupNumber", { fg = "#c678dd", bold = true, default = true })
api.nvim_set_hl(0, "VBufferLineGroupSeparator", { fg = "#3e4452", default = true })
api.nvim_set_hl(0, "VBufferLineGroupMarker", { fg = "#98c379", bold = true, default = true })

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
    expand_all_groups = true, -- Default mode: show all groups expanded
}

--- Refreshes the sidebar content with the current list of buffers.
function M.refresh()
    if not state.is_sidebar_open or not api.nvim_win_is_valid(state.win_id) then return end

    local bufferline_state = require('bufferline.state')
    if not bufferline_state or not bufferline_state.components then return end

    local components = bufferline_state.components
    local current_buffer_id = api.nvim_get_current_buf()
    
    -- 获取分组信息
    local group_info = bufferline_integration.get_group_buffer_info()
    local active_group = groups.get_active_group()
    
    -- bufferline集成已经处理了过滤，这里不需要再次过滤
    -- components 已经是经过分组过滤的结果
    
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
    local group_header_lines = {}  -- 记录组标题行的位置和信息

    -- 显示所有分组信息，根据expand_all_groups模式决定是否展开所有分组
    if active_group then
        local all_groups = groups.get_all_groups()
        
        for i, group in ipairs(all_groups) do
            local is_active = group.id == active_group.id
            local group_buffers = groups.get_group_buffers(group.id) or {}
            local buffer_count = #group_buffers
            
            -- 分组标题行，使用更显眼的格式
            local group_marker = is_active and "●" or "○"
            local group_name_display = group.name == "" and "(unnamed)" or group.name
            
            -- 添加视觉分隔符（除了第一个分组）
            if i > 1 then
                table.insert(lines_text, "")  -- 空行分隔
                local separator_line_num = #lines_text
                table.insert(lines_text, "────────────────────────────────────")  -- 分隔线
                table.insert(group_header_lines, {line = separator_line_num, type = "separator"})
            end
            
            local group_line = string.format("▎[%d] %s %s (%d buffers)", 
                i, group_marker, group_name_display, buffer_count)
            table.insert(lines_text, group_line)
            
            -- 记录组标题行信息
            table.insert(group_header_lines, {
                line = #lines_text - 1,  -- 0-based line number
                type = "header",
                is_active = is_active,
                group_number = i
            })
            
            -- 根据模式决定是否展开分组
            local should_expand = state.expand_all_groups or is_active
            if should_expand then
                -- 获取当前分组的buffers并显示
                local group_components = is_active and components or {}
                
                -- 如果是展开所有分组模式且不是当前活跃分组，需要手动构造components
                if state.expand_all_groups and not is_active then
                    group_components = {}
                    for _, buf_id in ipairs(group_buffers) do
                        if api.nvim_buf_is_valid(buf_id) then
                            local buf_name = api.nvim_buf_get_name(buf_id)
                            if buf_name ~= "" then
                                table.insert(group_components, {
                                    id = buf_id,
                                    name = vim.fn.fnamemodify(buf_name, ":t"),
                                    icon = "",
                                    focused = false
                                })
                            end
                        end
                    end
                end
                
                for j, component in ipairs(group_components) do
                    if component.id and component.name then
                        -- 使用树形结构的前缀，增加缩进以突出层次
                        local is_last = (j == #group_components)
                        local tree_prefix = is_last and "  └─ " or "  ├─ "
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
                        
                        -- 添加序号显示（1-9对应<leader>1-9，10用0表示）
                        local number_display = j <= 9 and tostring(j) or "0"
                        if j > 10 then
                            number_display = "·"  -- 超过10的用点表示
                        end
                        
                        -- 为当前buffer添加箭头标识
                        local current_marker = ""
                        if component.id == current_buffer_id then
                            current_marker = "► "
                        end
                        
                        if letter and is_picking then
                            -- In picking mode: show hint character + buffer name with tree structure
                            line_text = tree_prefix .. letter .. " " .. current_marker .. number_display .. " " .. modified_indicator .. icon .. " " .. component.name
                            pick_highlight_end = #tree_prefix + 1  -- Only highlight the letter character
                            
                            -- Choose appropriate pick highlight based on buffer state
                            if component.id == current_buffer_id then
                                pick_highlight_group = "VBufferLinePickSelected"
                            elseif component.focused then
                                pick_highlight_group = "VBufferLinePickVisible"
                            else
                                pick_highlight_group = "VBufferLinePick"
                            end
                            
                        else
                            -- Normal mode: regular display with tree structure, current marker and number
                            line_text = tree_prefix .. current_marker .. number_display .. " " .. modified_indicator .. icon .. " " .. component.name
                        end
                        
                        table.insert(lines_text, line_text)
                        -- 计算正确的行号，考虑前面的分组信息行
                        local actual_line_number = #lines_text
                        new_line_map[actual_line_number] = component.id
                        
                        -- Apply highlights
                        if is_picking and pick_highlight_group then
                            -- Highlight just the letter character in picking mode (starting after tree prefix)
                            -- 使用字节长度，因为nvim_buf_add_highlight使用字节位置
                            local highlight_start = #tree_prefix
                            local highlight_end = highlight_start + 1
                            api.nvim_buf_add_highlight(state.buf_id, ns_id, pick_highlight_group, actual_line_number - 1, highlight_start, highlight_end)
                            
                            -- Highlight the rest of the line normally, but only if there's content after the pick highlight
                            if highlight_end < #line_text then
                                local normal_highlight_group = "VBufferLineInactive"
                                if component.id == current_buffer_id then
                                    normal_highlight_group = "VBufferLineCurrent"
                                elseif component.focused then
                                    normal_highlight_group = "VBufferLineVisible"
                                elseif api.nvim_buf_get_option(component.id, "modified") then
                                    normal_highlight_group = "VBufferLineModified"
                                end
                                api.nvim_buf_add_highlight(state.buf_id, ns_id, normal_highlight_group, actual_line_number - 1, highlight_end, -1)
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
                            api.nvim_buf_add_highlight(state.buf_id, ns_id, highlight_group, actual_line_number - 1, 0, -1)
                        end
                    end
                end
                -- 如果是当前活跃分组且不是展开所有分组模式，设置标志避免下面重复处理
                if is_active and not state.expand_all_groups then
                    components = {}
                end
            end
        end
    end

    -- Clear old highlights
    api.nvim_buf_clear_namespace(state.buf_id, ns_id, 0, -1)

    api.nvim_buf_set_option(state.buf_id, "modifiable", true)

    -- buffer处理已经在上面的分组循环中完成

    api.nvim_buf_set_lines(state.buf_id, 0, -1, false, lines_text)
    
    -- 应用组标题高亮
    for _, header_info in ipairs(group_header_lines) do
        if header_info.type == "separator" then
            -- 分隔线高亮
            api.nvim_buf_add_highlight(state.buf_id, ns_id, "VBufferLineGroupSeparator", header_info.line, 0, -1)
        elseif header_info.type == "header" then
            -- 组标题行整体高亮
            local group_highlight = header_info.is_active and "VBufferLineGroupActive" or "VBufferLineGroupInactive"
            api.nvim_buf_add_highlight(state.buf_id, ns_id, group_highlight, header_info.line, 0, -1)
            
            -- 高亮组编号 [1]
            api.nvim_buf_add_highlight(state.buf_id, ns_id, "VBufferLineGroupNumber", header_info.line, 1, 4)
            
            -- 高亮组标记 (● 或 ○)
            local line_text = lines_text[header_info.line + 1] or ""
            local marker_start = string.find(line_text, "[●○]")
            if marker_start then
                api.nvim_buf_add_highlight(state.buf_id, ns_id, "VBufferLineGroupMarker", header_info.line, marker_start - 1, marker_start)
            end
        end
    end
    
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
    
    -- 我们需要找到每个component对应的实际行号
    -- 通过line_to_buffer_id映射来查找
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
                -- 查找这个buffer在sidebar中的实际行号
                local actual_line_number = nil
                for line_num, buffer_id in pairs(state.line_to_buffer_id) do
                    if buffer_id == component.id then
                        actual_line_number = line_num
                        break
                    end
                end
                
                if actual_line_number then
                    -- Choose appropriate pick highlight based on buffer state
                    local pick_highlight_group
                    if component.id == current_buffer_id then
                        pick_highlight_group = "VBufferLinePickSelected"
                    elseif component.focused then
                        pick_highlight_group = "VBufferLinePickVisible"
                    else
                        pick_highlight_group = "VBufferLinePick"
                    end
                    
                    -- 计算正确的高亮位置，跳过树形前缀
                    -- 确定是最后一个buffer还是中间的buffer
                    local is_last = (i == #components)
                    local tree_prefix = is_last and "  └─ " or "  ├─ "
                    local highlight_start = #tree_prefix
                    local highlight_end = highlight_start + 1
                    
                    -- Apply highlight with both namespace and without
                    api.nvim_buf_add_highlight(state.buf_id, 0, pick_highlight_group, actual_line_number - 1, highlight_start, highlight_end)
                    api.nvim_buf_add_highlight(state.buf_id, ns_id, pick_highlight_group, actual_line_number - 1, highlight_start, highlight_end)
                end
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
    api.nvim_win_set_option(new_win_id, 'cursorline', false)
    api.nvim_win_set_option(new_win_id, 'cursorcolumn', false)
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

--- Toggle expand all groups mode
function M.toggle_expand_all()
    state.expand_all_groups = not state.expand_all_groups
    local status = state.expand_all_groups and "enabled" or "disabled"
    vim.notify("Expand all groups mode " .. status, vim.log.levels.INFO)
    
    -- Refresh display
    if state.is_sidebar_open then
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
        
        -- 初始化分组功能
        groups.setup({
            max_buffers_per_group = 10,
            auto_create_groups = true,
            auto_add_new_buffers = true
        })
        
        -- 手动添加当前已经存在的buffer到默认分组
        -- 使用多个延迟时间点尝试，确保buffer被正确识别
        for _, delay in ipairs({50, 200, 500}) do
            vim.defer_fn(function()
                local all_buffers = vim.api.nvim_list_bufs()
                local default_group = groups.get_active_group()
                if default_group then
                    local added_count = 0
                    for _, buf in ipairs(all_buffers) do
                        if vim.api.nvim_buf_is_valid(buf) then
                            local buf_name = vim.api.nvim_buf_get_name(buf)
                            local buf_type = vim.api.nvim_buf_get_option(buf, 'buftype')
                            -- 只添加普通文件buffer，且不已经在分组中
                            if buf_name ~= "" and not buf_name:match("^%s*$") and 
                               buf_type == "" and
                               not vim.tbl_contains(default_group.buffers, buf) then
                                groups.add_buffer_to_group(buf, default_group.id)
                                added_count = added_count + 1
                            end
                        end
                    end
                    if added_count > 0 then
                        -- 刷新界面
                        M.refresh()
                    end
                end
            end, delay)
        end
        
        -- 设置命令
        commands.setup()
        
        -- 启用 bufferline 集成
        bufferline_integration.enable()
        
        -- 确保初始状态正确显示
        vim.schedule(function()
            M.refresh()
        end)
    end
end

-- 导出分组管理函数
M.groups = groups
M.commands = commands
M.bufferline_integration = bufferline_integration

-- 便捷的分组操作函数
M.create_group = function(name) return groups.create_group(name) end
M.switch_to_next_group = function() commands.next_group() end
M.switch_to_prev_group = function() commands.prev_group() end
M.add_current_buffer_to_group = function(group_name) 
    commands.add_buffer_to_group({args = group_name}) 
end
M.move_group_up = function() commands.move_group_up() end
M.move_group_down = function() commands.move_group_down() end

return M