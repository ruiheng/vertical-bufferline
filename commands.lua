-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/commands.lua
-- 分组管理的用户命令

local M = {}

local groups = require('vertical-bufferline.groups')

-- 创建分组命令
local function create_group_command(args)
    local name = args.args
    if name == "" then
        name = nil  -- 使用默认名称
    end
    
    local group_id = groups.create_group(name)
    local all_groups = groups.get_all_groups()
    
    for _, g in ipairs(all_groups) do
        if g.id == group_id then
            vim.notify("Created group: " .. g.name .. " (ID: " .. group_id .. ")", vim.log.levels.INFO)
            break
        end
    end
    
    -- 立即刷新界面
    vim.schedule(function()
        if require('vertical-bufferline').refresh then
            require('vertical-bufferline').refresh()
        end
    end)
    
    return group_id
end

-- 删除分组命令
local function delete_group_command(args)
    local group_name_or_id = args.args
    if group_name_or_id == "" then
        vim.notify("Usage: VBufferLineDeleteGroup <group_name_or_id>", vim.log.levels.ERROR)
        return
    end
    
    -- 查找分组（按名称或ID）
    local target_group = nil
    for _, group in ipairs(groups.get_all_groups()) do
        if group.id == group_name_or_id or (group.name ~= "" and group.name == group_name_or_id) then
            target_group = group
            break
        end
    end
    
    if not target_group then
        vim.notify("Group not found: " .. group_name_or_id, vim.log.levels.ERROR)
        return
    end
    
    if groups.delete_group(target_group.id) then
        vim.notify("Deleted group: " .. target_group.name, vim.log.levels.INFO)
    end
end

-- 重命名分组命令
local function rename_group_command(args)
    local new_name = args.args
    if new_name == "" then
        vim.notify("Usage: VBufferLineRenameGroup <new_name>", vim.log.levels.ERROR)
        return
    end
    
    -- 获取当前活跃分组
    local active_group = groups.get_active_group()
    if not active_group then
        vim.notify("No active group to rename", vim.log.levels.ERROR)
        return
    end
    
    local old_name = active_group.name == "" and "(unnamed)" or active_group.name
    
    if groups.rename_group(active_group.id, new_name) then
        vim.notify("Renamed group '" .. old_name .. "' to '" .. new_name .. "'", vim.log.levels.INFO)
        
        -- 立即刷新界面
        vim.schedule(function()
            if require('vertical-bufferline').refresh then
                require('vertical-bufferline').refresh()
            end
        end)
    end
end

-- 切换分组命令
local function switch_group_command(args)
    local group_name_or_id = args.args
    if group_name_or_id == "" then
        -- 显示当前分组信息
        local active_group = groups.get_active_group()
        if active_group then
            vim.notify("Current group: " .. active_group.name .. " (" .. #active_group.buffers .. " buffers)", vim.log.levels.INFO)
        end
        return
    end
    
    -- 查找并切换到指定分组
    local target_group = nil
    for _, group in ipairs(groups.get_all_groups()) do
        if group.id == group_name_or_id or (group.name ~= "" and group.name == group_name_or_id) then
            target_group = group
            break
        end
    end
    
    if not target_group then
        vim.notify("Group not found: " .. group_name_or_id, vim.log.levels.ERROR)
        return
    end
    
    if groups.set_active_group(target_group.id) then
        -- 分组切换完成，sidebar会自动更新显示
        
        -- 触发 bufferline 强制刷新
        local bufferline_integration = require('vertical-bufferline.bufferline-integration')
        bufferline_integration.force_refresh()
        
        -- 也刷新我们的侧边栏
        vim.schedule(function()
            if require('vertical-bufferline').refresh then
                require('vertical-bufferline').refresh()
            end
        end)
    end
end


-- 添加当前buffer到分组命令
local function add_buffer_to_group_command(args)
    local group_name_or_id = args.args
    if group_name_or_id == "" then
        vim.notify("Usage: VBufferLineAddToGroup <group_name_or_id>", vim.log.levels.ERROR)
        return
    end
    
    local current_buffer = vim.api.nvim_get_current_buf()
    
    -- 查找分组
    local target_group = nil
    for _, group in ipairs(groups.get_all_groups()) do
        if group.id == group_name_or_id or (group.name ~= "" and group.name == group_name_or_id) then
            target_group = group
            break
        end
    end
    
    if not target_group then
        vim.notify("Group not found: " .. group_name_or_id, vim.log.levels.ERROR)
        return
    end
    
    if groups.add_buffer_to_group(current_buffer, target_group.id) then
        local buffer_name = vim.api.nvim_buf_get_name(current_buffer)
        local short_name = vim.fn.fnamemodify(buffer_name, ":t")
        vim.notify("Added buffer '" .. short_name .. "' to group: " .. target_group.name, vim.log.levels.INFO)
    end
end


-- 快速切换到下一个分组
local function next_group_command()
    local all_groups = groups.get_all_groups()
    if #all_groups <= 1 then
        vim.notify("No other groups to switch to", vim.log.levels.WARN)
        return
    end
    
    local active_group_id = groups.get_active_group_id()
    local current_index = 1
    
    for i, group in ipairs(all_groups) do
        if group.id == active_group_id then
            current_index = i
            break
        end
    end
    
    local next_index = current_index % #all_groups + 1
    local next_group = all_groups[next_index]
    
    groups.set_active_group(next_group.id)
    -- 切换到下一个分组
    
    -- 触发 bufferline 强制刷新
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    bufferline_integration.force_refresh()
    
    -- 也刷新我们的侧边栏
    vim.schedule(function()
        if require('vertical-bufferline').refresh then
            require('vertical-bufferline').refresh()
        end
    end)
end

-- 快速切换到上一个分组
local function prev_group_command()
    local all_groups = groups.get_all_groups()
    if #all_groups <= 1 then
        vim.notify("No other groups to switch to", vim.log.levels.WARN)
        return
    end
    
    local active_group_id = groups.get_active_group_id()
    local current_index = 1
    
    for i, group in ipairs(all_groups) do
        if group.id == active_group_id then
            current_index = i
            break
        end
    end
    
    local prev_index = current_index == 1 and #all_groups or current_index - 1
    local prev_group = all_groups[prev_index]
    
    groups.set_active_group(prev_group.id)
    -- 切换到上一个分组
    
    -- 触发 bufferline 强制刷新
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    bufferline_integration.force_refresh()
    
    -- 也刷新我们的侧边栏
    vim.schedule(function()
        if require('vertical-bufferline').refresh then
            require('vertical-bufferline').refresh()
        end
    end)
end

-- 切换展开所有分组模式
local function toggle_expand_all_command()
    local vbl = require('vertical-bufferline')
    vbl.toggle_expand_all()
end

-- 向上移动当前分组
local function move_group_up_command()
    local active_group = groups.get_active_group()
    if not active_group then
        vim.notify("No active group to move", vim.log.levels.ERROR)
        return
    end
    
    if groups.move_group_up(active_group.id) then
        vim.notify("Moved group '" .. active_group.name .. "' up", vim.log.levels.INFO)
        
        -- 立即刷新界面
        vim.schedule(function()
            if require('vertical-bufferline').refresh then
                require('vertical-bufferline').refresh()
            end
        end)
    else
        vim.notify("Cannot move group up (already at top)", vim.log.levels.WARN)
    end
end

-- 向下移动当前分组
local function move_group_down_command()
    local active_group = groups.get_active_group()
    if not active_group then
        vim.notify("No active group to move", vim.log.levels.ERROR)
        return
    end
    
    if groups.move_group_down(active_group.id) then
        vim.notify("Moved group '" .. active_group.name .. "' down", vim.log.levels.INFO)
        
        -- 立即刷新界面
        vim.schedule(function()
            if require('vertical-bufferline').refresh then
                require('vertical-bufferline').refresh()
            end
        end)
    else
        vim.notify("Cannot move group down (already at bottom)", vim.log.levels.WARN)
    end
end

-- 移动当前分组到指定位置
local function move_group_to_position_command(args)
    local position = tonumber(args.args)
    if not position then
        vim.notify("Usage: VBufferLineMoveGroupToPosition <position>", vim.log.levels.ERROR)
        return
    end
    
    local active_group = groups.get_active_group()
    if not active_group then
        vim.notify("No active group to move", vim.log.levels.ERROR)
        return
    end
    
    if groups.move_group_to_position(active_group.id, position) then
        vim.notify("Moved group '" .. active_group.name .. "' to position " .. position, vim.log.levels.INFO)
        
        -- 立即刷新界面
        vim.schedule(function()
            if require('vertical-bufferline').refresh then
                require('vertical-bufferline').refresh()
            end
        end)
    else
        vim.notify("Cannot move group to position " .. position .. " (invalid position)", vim.log.levels.ERROR)
    end
end

-- Session管理命令
local function save_session_command(args)
    local session = require('vertical-bufferline.session')
    local filename = args.args ~= "" and args.args or nil
    session.save_session(filename)
end

local function load_session_command(args)
    local session = require('vertical-bufferline.session')
    local filename = args.args ~= "" and args.args or nil
    session.load_session(filename)
end

local function delete_session_command(args)
    local session = require('vertical-bufferline.session')
    local filename = args.args ~= "" and args.args or nil
    session.delete_session(filename)
end

local function list_sessions_command()
    local session = require('vertical-bufferline.session')
    local sessions = session.list_sessions()
    
    if #sessions == 0 then
        vim.notify("No sessions found", vim.log.levels.INFO)
        return
    end
    
    local lines = {"Available sessions:"}
    for i, sess in ipairs(sessions) do
        local time_str = os.date("%Y-%m-%d %H:%M:%S", sess.timestamp or sess.modified)
        local group_info = sess.group_count and (" (" .. sess.group_count .. " groups)") or ""
        local cwd_info = sess.working_directory and (" - " .. sess.working_directory) or ""
        local line = string.format("  %d. %s%s%s [%s]", 
            i, sess.name, group_info, cwd_info, time_str)
        table.insert(lines, line)
    end
    
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

-- 分组完成函数（用于命令补全）
local function group_complete(arglead, cmdline, cursorpos)
    local all_groups = groups.get_all_groups()
    local completions = {}
    
    for _, group in ipairs(all_groups) do
        local name_matches = group.name ~= "" and group.name:lower():find(arglead:lower(), 1, true)
        local id_matches = group.id:lower():find(arglead:lower(), 1, true)
        
        if name_matches or id_matches then
            if group.name ~= "" then
                table.insert(completions, group.name)
            end
            if group.name ~= group.id then
                table.insert(completions, group.id)
            end
        end
    end
    
    return completions
end

-- 设置所有用户命令
function M.setup()
    -- 创建分组
    vim.api.nvim_create_user_command("VBufferLineCreateGroup", create_group_command, {
        nargs = "?",
        desc = "Create a new buffer group"
    })
    
    -- 删除分组
    vim.api.nvim_create_user_command("VBufferLineDeleteGroup", delete_group_command, {
        nargs = 1,
        complete = group_complete,
        desc = "Delete a buffer group"
    })
    
    -- 重命名分组
    vim.api.nvim_create_user_command("VBufferLineRenameGroup", rename_group_command, {
        nargs = 1,
        desc = "Rename current buffer group"
    })
    
    -- 切换分组
    vim.api.nvim_create_user_command("VBufferLineSwitchGroup", switch_group_command, {
        nargs = "?",
        complete = group_complete,
        desc = "Switch to a buffer group"
    })
    
    
    -- 添加buffer到分组
    vim.api.nvim_create_user_command("VBufferLineAddToGroup", add_buffer_to_group_command, {
        nargs = 1,
        complete = group_complete,
        desc = "Add current buffer to a group"
    })
    
    
    -- 下一个分组
    vim.api.nvim_create_user_command("VBufferLineNextGroup", next_group_command, {
        nargs = 0,
        desc = "Switch to next buffer group"
    })
    
    -- 上一个分组
    vim.api.nvim_create_user_command("VBufferLinePrevGroup", prev_group_command, {
        nargs = 0,
        desc = "Switch to previous buffer group"
    })
    
    -- 切换展开所有分组模式
    vim.api.nvim_create_user_command("VBufferLineToggleExpandAll", toggle_expand_all_command, {
        nargs = 0,
        desc = "Toggle expand all groups mode"
    })
    
    -- 分组重排序命令
    vim.api.nvim_create_user_command("VBufferLineMoveGroupUp", move_group_up_command, {
        nargs = 0,
        desc = "Move current group up"
    })
    
    vim.api.nvim_create_user_command("VBufferLineMoveGroupDown", move_group_down_command, {
        nargs = 0,
        desc = "Move current group down"
    })
    
    vim.api.nvim_create_user_command("VBufferLineMoveGroupToPosition", move_group_to_position_command, {
        nargs = 1,
        desc = "Move current group to specified position"
    })
    
    -- Session管理命令
    vim.api.nvim_create_user_command("VBufferLineSaveSession", save_session_command, {
        nargs = "?",
        desc = "Save current groups configuration to session"
    })
    
    vim.api.nvim_create_user_command("VBufferLineLoadSession", load_session_command, {
        nargs = "?",
        desc = "Load groups configuration from session"
    })
    
    vim.api.nvim_create_user_command("VBufferLineDeleteSession", delete_session_command, {
        nargs = "?",
        desc = "Delete a session file"
    })
    
    vim.api.nvim_create_user_command("VBufferLineListSessions", list_sessions_command, {
        nargs = 0,
        desc = "List all available sessions"
    })
    
    -- 调试信息
    vim.api.nvim_create_user_command("VBufferLineDebug", function()
        local debug_info = groups.debug_info()
        print("=== Debug Info ===")
        print("Groups: " .. vim.inspect(debug_info.groups_data.groups))
        print("Active group: " .. (debug_info.groups_data.active_group_id or "none"))
        print("Stats: " .. vim.inspect(debug_info.stats))
        
        -- 添加 bufferline 集成调试信息
        local bufferline_integration = require('vertical-bufferline.bufferline-integration')
        local integration_status = bufferline_integration.debug_session_sync()
        
        print("\n=== Session Sync Status ===")
        print("Integration working properly:", integration_status.is_hooked and integration_status.filtering_enabled)
    end, {
        nargs = 0,
        desc = "Show debug information"
    })
    
    -- 专门的session同步调试命令
    vim.api.nvim_create_user_command("VBufferLineDebugSync", function()
        local bufferline_integration = require('vertical-bufferline.bufferline-integration')
        bufferline_integration.debug_session_sync()
    end, {
        nargs = 0,
        desc = "Show detailed session synchronization debug information"
    })
    
    -- 手动同步命令
    vim.api.nvim_create_user_command("VBufferLineSyncGroups", function()
        local bufferline_integration = require('vertical-bufferline.bufferline-integration')
        bufferline_integration.manual_sync()
    end, {
        nargs = 0,
        desc = "Manually trigger synchronization between bufferline and groups"
    })
    
    -- 检查buffer分组重复情况
    vim.api.nvim_create_user_command("VBufferLineCheckDuplicates", function()
        print("=== Buffer Group Duplicates Check ===")
        local groups = require('vertical-bufferline.groups')
        local all_groups = groups.get_all_groups()
        local buffer_group_map = {}
        
        -- 收集所有buffer的分组信息
        for i, group in ipairs(all_groups) do
            print(string.format("Group %d: '%s' (%d buffers)", i, group.name, #group.buffers))
            for _, buf_id in ipairs(group.buffers) do
                if not buffer_group_map[buf_id] then
                    buffer_group_map[buf_id] = {}
                end
                table.insert(buffer_group_map[buf_id], {group_id = group.id, group_name = group.name, group_index = i})
            end
        end
        
        -- 检查重复
        local duplicates_found = false
        print("\n=== Duplicate Analysis ===")
        for buf_id, group_list in pairs(buffer_group_map) do
            if #group_list > 1 then
                duplicates_found = true
                local name = vim.api.nvim_buf_get_name(buf_id)
                print(string.format("Buffer [%d] %s is in %d groups:", 
                    buf_id, vim.fn.fnamemodify(name, ":t"), #group_list))
                for _, group_info in ipairs(group_list) do
                    print(string.format("  - %s (%s)", group_info.group_name, group_info.group_id))
                end
            end
        end
        
        if not duplicates_found then
            print("No duplicate buffer assignments found.")
        end
        print("========================")
        
        return duplicates_found
    end, {
        nargs = 0,
        desc = "Check for buffer group assignment duplicates"
    })
    
    -- 清理buffer分组重复情况
    vim.api.nvim_create_user_command("VBufferLineCleanDuplicates", function()
        print("=== Cleaning Buffer Group Duplicates ===")
        local groups = require('vertical-bufferline.groups')
        local all_groups = groups.get_all_groups()
        local buffer_group_map = {}
        local cleaned_count = 0
        
        -- 收集所有buffer的分组信息
        for i, group in ipairs(all_groups) do
            for _, buf_id in ipairs(group.buffers) do
                if not buffer_group_map[buf_id] then
                    buffer_group_map[buf_id] = {}
                end
                table.insert(buffer_group_map[buf_id], {group_id = group.id, group_name = group.name, group_index = i})
            end
        end
        
        -- 清理重复：保留第一个分组，从其他分组中移除
        for buf_id, group_list in pairs(buffer_group_map) do
            if #group_list > 1 then
                local name = vim.api.nvim_buf_get_name(buf_id)
                print(string.format("Cleaning buffer [%d] %s from %d groups:", 
                    buf_id, vim.fn.fnamemodify(name, ":t"), #group_list))
                
                -- 保留第一个分组（通常是活跃分组或主分组）
                local keep_group = group_list[1]
                print(string.format("  Keeping in: %s (%s)", keep_group.group_name, keep_group.group_id))
                
                -- 从其他分组中移除
                for i = 2, #group_list do
                    local remove_group = group_list[i]
                    groups.remove_buffer_from_group(buf_id, remove_group.group_id)
                    print(string.format("  Removed from: %s (%s)", remove_group.group_name, remove_group.group_id))
                    cleaned_count = cleaned_count + 1
                end
            end
        end
        
        if cleaned_count > 0 then
            print(string.format("Cleaned %d duplicate buffer assignments.", cleaned_count))
            -- 刷新界面
            local vbl = require('vertical-bufferline')
            if vbl.state and vbl.state.is_sidebar_open then
                vbl.refresh()
            end
        else
            print("No duplicate buffer assignments found to clean.")
        end
        print("========================")
    end, {
        nargs = 0,
        desc = "Clean buffer group assignment duplicates"
    })
    
    -- 重建分组结构（彻底清理所有问题）
    vim.api.nvim_create_user_command("VBufferLineRebuildGroups", function()
        print("=== Rebuilding Group Structure ===")
        local groups = require('vertical-bufferline.groups')
        local all_groups = groups.get_all_groups()
        local active_group_id = groups.get_active_group_id()
        
        -- 收集当前所有有效的buffers
        local all_valid_buffers = {}
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
                local name = vim.api.nvim_buf_get_name(buf)
                local buf_type = vim.api.nvim_buf_get_option(buf, 'buftype')
                if name ~= "" and buf_type == "" then
                    table.insert(all_valid_buffers, buf)
                end
            end
        end
        
        print(string.format("Found %d valid buffers", #all_valid_buffers))
        
        -- 清空所有分组的buffer列表
        for _, group in ipairs(all_groups) do
            print(string.format("Clearing group '%s' (%d buffers)", group.name, #group.buffers))
            group.buffers = {}
        end
        
        -- 重新分配：每个buffer只属于第一个分组
        if #all_groups > 0 then
            local target_group = all_groups[1]  -- 默认使用第一个分组
            for _, buf_id in ipairs(all_valid_buffers) do
                table.insert(target_group.buffers, buf_id)
                local name = vim.api.nvim_buf_get_name(buf_id)
                print(string.format("Added [%d] %s to group '%s'", 
                    buf_id, vim.fn.fnamemodify(name, ":t"), target_group.name))
            end
            
            -- 确保有一个活跃分组
            if not active_group_id or not groups.get_active_group() then
                groups.set_active_group(target_group.id)
                print(string.format("Set active group to '%s'", target_group.name))
            end
        end
        
        -- 刷新界面
        local vbl = require('vertical-bufferline')
        if vbl.state and vbl.state.is_sidebar_open then
            vbl.refresh()
        end
        
        print("Group structure rebuilt successfully.")
        print("===================================")
    end, {
        nargs = 0,
        desc = "Completely rebuild group structure to fix all issues"
    })
    
    -- 控制自动添加buffer功能
    vim.api.nvim_create_user_command("VBufferLineToggleAutoAdd", function()
        local groups = require('vertical-bufferline.groups')
        local current_state = groups.is_auto_add_disabled()
        groups.set_auto_add_disabled(not current_state)
        local new_state = groups.is_auto_add_disabled()
        vim.notify("Auto-add buffers: " .. (new_state and "DISABLED" or "ENABLED"), vim.log.levels.INFO)
    end, {
        nargs = 0,
        desc = "Toggle automatic buffer addition to active group"
    })
    
    -- 手动强制同步session和bufferline
    vim.api.nvim_create_user_command("VBufferLineForceSync", function()
        print("=== Force Sync Started ===")
        local bufferline_integration = require('vertical-bufferline.bufferline-integration')
        local groups = require('vertical-bufferline.groups')
        
        -- 显示当前状态
        local active_group = groups.get_active_group()
        if active_group then
            print(string.format("Active group: %s (%d buffers)", active_group.name, #active_group.buffers))
        else
            print("No active group")
        end
        
        -- 强制刷新bufferline
        bufferline_integration.force_refresh()
        
        -- 确保当前缓冲区在活跃分组中（兼容scope.nvim）
        if active_group and #active_group.buffers > 0 then
            local current_buf = vim.api.nvim_get_current_buf()
            local target_buf = nil
            
            -- 如果当前buffer不在活跃分组中，找到一个合适的
            if not vim.tbl_contains(active_group.buffers, current_buf) then
                for _, buf_id in ipairs(active_group.buffers) do
                    if vim.api.nvim_buf_is_valid(buf_id) and vim.api.nvim_buf_is_loaded(buf_id) then
                        target_buf = buf_id
                        break
                    end
                end
            end
            
            if target_buf then
                -- 确保所有分组中的buffers对scope可见
                for _, buf_id in ipairs(active_group.buffers) do
                    if vim.api.nvim_buf_is_valid(buf_id) then
                        vim.bo[buf_id].buflisted = true
                        -- 短暂切换让scope识别
                        local old_buf = vim.api.nvim_get_current_buf()
                        vim.api.nvim_set_current_buf(buf_id)
                        vim.api.nvim_set_current_buf(old_buf)
                    end
                end
                
                vim.api.nvim_set_current_buf(target_buf)
                vim.api.nvim_exec_autocmds('BufEnter', { buffer = target_buf })
                print(string.format("Switched to buffer: [%d] %s", target_buf, 
                    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(target_buf), ":t")))
            end
        end
        
        -- 刷新sidebar
        local vbl = require('vertical-bufferline')
        if vbl.state and vbl.state.is_sidebar_open then
            vbl.refresh()
        end
        
        -- 再次强制刷新
        bufferline_integration.force_refresh()
        print("=== Force Sync Completed ===")
    end, {
        nargs = 0,
        desc = "Manually force sync between session, groups, and bufferline"
    })
    
    -- 手动添加当前buffer到当前分组（支持多分组）
    vim.api.nvim_create_user_command("VBufferLineAddCurrentToGroup", function()
        local groups = require('vertical-bufferline.groups')
        local active_group = groups.get_active_group()
        if not active_group then
            vim.notify("No active group found", vim.log.levels.ERROR)
            return
        end
        
        local current_buffer = vim.api.nvim_get_current_buf()
        local success = groups.add_buffer_to_group(current_buffer, active_group.id)
        
        if success then
            local buffer_name = vim.api.nvim_buf_get_name(current_buffer)
            local short_name = vim.fn.fnamemodify(buffer_name, ":t")
            
            -- 检查是否在其他分组中也存在
            local all_groups = groups.find_buffer_groups(current_buffer)
            if #all_groups > 1 then
                local group_names = {}
                for _, group in ipairs(all_groups) do
                    table.insert(group_names, group.name)
                end
                vim.cmd('echo "Added \'' .. short_name .. '\' to \'' .. active_group.name .. '\' (also in: ' .. table.concat(group_names, ", ") .. ')"')
            else
                vim.cmd('echo "Added \'' .. short_name .. '\' to \'' .. active_group.name .. '\'"')
            end
            
            -- 刷新界面
            local vbl = require('vertical-bufferline')
            if vbl.state and vbl.state.is_sidebar_open then
                vbl.refresh()
            end
        else
            vim.notify("Failed to add buffer to group (might already be there)", vim.log.levels.WARN)
        end
    end, {
        nargs = 0,
        desc = "Add current buffer to current group (allows multi-group)"
    })

    -- 智能关闭buffer（类似scope.nvim）
    vim.api.nvim_create_user_command("VBufferLineSmartClose", function()
        local bufferline_integration = require('vertical-bufferline.bufferline-integration')
        bufferline_integration.smart_close_buffer()
    end, {
        nargs = 0,
        desc = "Smart close buffer: remove from group if exists elsewhere, delete globally otherwise"
    })

    -- 从当前分组移除buffer（软删除）
    vim.api.nvim_create_user_command("VBufferLineRemoveFromGroup", function()
        local groups = require('vertical-bufferline.groups')
        local active_group = groups.get_active_group()
        if not active_group then
            vim.notify("No active group found", vim.log.levels.ERROR)
            return
        end
        
        local current_buffer = vim.api.nvim_get_current_buf()
        local success = groups.remove_buffer_from_group(current_buffer, active_group.id)
        
        if success then
            local buffer_name = vim.api.nvim_buf_get_name(current_buffer)
            local short_name = vim.fn.fnamemodify(buffer_name, ":t")
            -- 使用echo显示简洁信息，不需要按Enter
            local remaining_groups = groups.find_buffer_groups(current_buffer)
            if #remaining_groups > 0 then
                local group_names = {}
                for _, group in ipairs(remaining_groups) do
                    table.insert(group_names, group.name)
                end
                print("Removed '" .. short_name .. "' from '" .. active_group.name .. "' (still in: " .. table.concat(group_names, ", ") .. ")")
            else
                print("Removed '" .. short_name .. "' from '" .. active_group.name .. "' (removed from all groups)")
            end
            
            -- 刷新界面
            local vbl = require('vertical-bufferline')
            if vbl.state and vbl.state.is_sidebar_open then
                vbl.refresh()
            end
        else
            vim.notify("Failed to remove buffer from group", vim.log.levels.ERROR)
        end
    end, {
        nargs = 0,
        desc = "Remove current buffer from current group only (soft delete)"
    })

    -- 手动刷新buffer列表
    vim.api.nvim_create_user_command("VBufferLineRefreshBuffers", function()
        local active_group = groups.get_active_group()
        if not active_group then
            vim.notify("No active group found", vim.log.levels.ERROR)
            return
        end
        
        local added_count = 0
        local all_buffers = vim.api.nvim_list_bufs()
        
        for _, buf in ipairs(all_buffers) do
            if vim.api.nvim_buf_is_valid(buf) then
                local buf_name = vim.api.nvim_buf_get_name(buf)
                local buf_type = vim.api.nvim_buf_get_option(buf, 'buftype')
                
                -- 排除侧边栏自己的buffer（通过检查bufhidden属性）
                local buf_hidden = pcall(vim.api.nvim_buf_get_option, buf, 'bufhidden')
                local is_sidebar_buf = (buf_hidden and vim.api.nvim_buf_get_option(buf, 'bufhidden') == 'wipe')
                
                -- 只添加普通文件buffer
                if buf_name ~= "" and not buf_name:match("^%s*$") and 
                   buf_type == "" and
                   not is_sidebar_buf and
                   not vim.tbl_contains(active_group.buffers, buf) then
                    local success = groups.add_buffer_to_group(buf, active_group.id)
                    if success then
                        added_count = added_count + 1
                    end
                end
            end
        end
        
        vim.notify("Added " .. added_count .. " buffers to group '" .. active_group.name .. "'", vim.log.levels.INFO)
        
        -- 刷新界面
        vim.schedule(function()
            if require('vertical-bufferline').refresh then
                require('vertical-bufferline').refresh()
            end
        end)
    end, {
        nargs = 0,
        desc = "Manually refresh and add current buffers to active group"
    })
end

-- 导出函数供其他模块使用
M.create_group = create_group_command
M.delete_group = delete_group_command
M.rename_group = rename_group_command
M.switch_group = switch_group_command
M.add_buffer_to_group = add_buffer_to_group_command
M.next_group = next_group_command
M.prev_group = prev_group_command
M.move_group_up = move_group_up_command
M.move_group_down = move_group_down_command
M.move_group_to_position = move_group_to_position_command

return M