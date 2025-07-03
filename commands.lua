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
    
    -- 调试信息
    vim.api.nvim_create_user_command("VBufferLineDebug", function()
        local debug_info = groups.debug_info()
        print("=== Debug Info ===")
        print("Groups: " .. vim.inspect(debug_info.groups_data.groups))
        print("Active group: " .. (debug_info.groups_data.active_group_id or "none"))
        print("Stats: " .. vim.inspect(debug_info.stats))
    end, {
        nargs = 0,
        desc = "Show debug information"
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

return M