-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/groups.lua
-- 动态分组管理模块

local M = {}

local api = vim.api

-- 分组数据结构
local groups_data = {
    -- 所有分组的定义
    groups = {
        -- 示例：
        -- {
        --     id = "group1",
        --     name = "Main",
        --     buffers = {12, 15, 18}, -- buffer IDs
        --     created_at = os.time(),
        --     color = "#e06c75" -- 可选的颜色标识
        -- }
    },
    
    -- 当前活跃的分组ID
    active_group_id = nil,
    
    -- 默认分组ID（所有buffer的后备分组）
    default_group_id = "default",
    
    -- 下一个分组ID的计数器
    next_group_id = 1,
    
    -- 分组设置
    settings = {
        max_buffers_per_group = 10,
        auto_create_groups = true,
        auto_add_new_buffers = true,
        group_name_prefix = "Group",
    }
}

-- 初始化默认分组
local function init_default_group()
    if #groups_data.groups == 0 then
        local default_group = {
            id = groups_data.default_group_id,
            name = "Default",
            buffers = {},
            created_at = os.time(),
            color = "#61afef"
        }
        table.insert(groups_data.groups, default_group)
        groups_data.active_group_id = groups_data.default_group_id
        
        -- 初始化时不自动添加buffer，由调用方负责
    end
end

-- 查找分组
local function find_group_by_id(group_id)
    for _, group in ipairs(groups_data.groups) do
        if group.id == group_id then
            return group
        end
    end
    return nil
end

-- 查找分组索引
local function find_group_index_by_id(group_id)
    for i, group in ipairs(groups_data.groups) do
        if group.id == group_id then
            return i
        end
    end
    return nil
end

-- 生成新的分组ID
local function generate_group_id()
    local id = "group_" .. groups_data.next_group_id
    groups_data.next_group_id = groups_data.next_group_id + 1
    return id
end

-- 创建新分组
function M.create_group(name, color)
    local group_id = generate_group_id()
    local group_name = name or ""  -- 允许空名字
    
    local new_group = {
        id = group_id,
        name = group_name,
        buffers = {},
        created_at = os.time(),
        color = color or "#98c379"
    }
    
    table.insert(groups_data.groups, new_group)
    
    -- 触发事件
    vim.api.nvim_exec_autocmds("User", {
        pattern = "VBufferLineGroupCreated",
        data = { group = new_group }
    })
    
    return group_id
end

-- 删除分组
function M.delete_group(group_id)
    if group_id == groups_data.default_group_id then
        vim.notify("Cannot delete default group", vim.log.levels.WARN)
        return false
    end
    
    local group_index = find_group_index_by_id(group_id)
    if not group_index then
        vim.notify("Group not found: " .. group_id, vim.log.levels.ERROR)
        return false
    end
    
    local group = groups_data.groups[group_index]
    
    -- 将该分组的所有buffer移动到默认分组
    local default_group = find_group_by_id(groups_data.default_group_id)
    if default_group then
        for _, buffer_id in ipairs(group.buffers) do
            if not vim.tbl_contains(default_group.buffers, buffer_id) then
                table.insert(default_group.buffers, buffer_id)
            end
        end
    end
    
    -- 删除分组
    table.remove(groups_data.groups, group_index)
    
    -- 如果删除的是当前活跃分组，切换到默认分组
    if groups_data.active_group_id == group_id then
        groups_data.active_group_id = groups_data.default_group_id
    end
    
    -- 触发事件
    vim.api.nvim_exec_autocmds("User", {
        pattern = "VBufferLineGroupDeleted",
        data = { group_id = group_id }
    })
    
    return true
end

-- 重命名分组
function M.rename_group(group_id, new_name)
    local group = find_group_by_id(group_id)
    if not group then
        vim.notify("Group not found: " .. group_id, vim.log.levels.ERROR)
        return false
    end
    
    local old_name = group.name
    group.name = new_name
    
    -- 触发事件
    vim.api.nvim_exec_autocmds("User", {
        pattern = "VBufferLineGroupRenamed",
        data = { group_id = group_id, old_name = old_name, new_name = new_name }
    })
    
    return true
end

-- 获取所有分组
function M.get_all_groups()
    return vim.deepcopy(groups_data.groups)
end

-- 获取当前活跃分组
function M.get_active_group()
    return find_group_by_id(groups_data.active_group_id)
end

-- 获取当前活跃分组ID
function M.get_active_group_id()
    return groups_data.active_group_id
end

-- 设置活跃分组
function M.set_active_group(group_id)
    local group = find_group_by_id(group_id)
    if not group then
        vim.notify("Group not found: " .. group_id, vim.log.levels.ERROR)
        return false
    end
    
    local old_group_id = groups_data.active_group_id
    groups_data.active_group_id = group_id
    
    -- 触发事件
    vim.api.nvim_exec_autocmds("User", {
        pattern = "VBufferLineGroupChanged",
        data = { old_group_id = old_group_id, new_group_id = group_id }
    })
    
    return true
end

-- 将buffer添加到分组
function M.add_buffer_to_group(buffer_id, group_id)
    if not api.nvim_buf_is_valid(buffer_id) then
        return false
    end
    
    local group = find_group_by_id(group_id)
    if not group then
        vim.notify("Group not found: " .. group_id, vim.log.levels.ERROR)
        return false
    end
    
    -- 检查是否已经在分组中
    if vim.tbl_contains(group.buffers, buffer_id) then
        return true
    end
    
    -- 检查分组是否建议已满（只是警告，不阻止）
    if #group.buffers >= groups_data.settings.max_buffers_per_group then
        vim.notify("Group '" .. group.name .. "' has " .. #group.buffers .. " buffers (recommended max: " .. groups_data.settings.max_buffers_per_group .. ")", vim.log.levels.WARN)
        -- 继续执行，不return false
    end
    
    -- 允许buffer同时存在于多个分组中（注释掉原来的限制）
    -- M.remove_buffer_from_all_groups(buffer_id)
    
    -- 添加到指定分组
    table.insert(group.buffers, buffer_id)
    
    -- 触发事件
    vim.api.nvim_exec_autocmds("User", {
        pattern = "VBufferLineBufferAddedToGroup",
        data = { buffer_id = buffer_id, group_id = group_id }
    })
    
    return true
end

-- 从分组中移除buffer
function M.remove_buffer_from_group(buffer_id, group_id)
    local group = find_group_by_id(group_id)
    if not group then
        return false
    end
    
    for i, buf_id in ipairs(group.buffers) do
        if buf_id == buffer_id then
            table.remove(group.buffers, i)
            
            -- 触发事件
            vim.api.nvim_exec_autocmds("User", {
                pattern = "VBufferLineBufferRemovedFromGroup",
                data = { buffer_id = buffer_id, group_id = group_id }
            })
            
            return true
        end
    end
    
    return false
end

-- 从所有分组中移除buffer
function M.remove_buffer_from_all_groups(buffer_id)
    for _, group in ipairs(groups_data.groups) do
        M.remove_buffer_from_group(buffer_id, group.id)
    end
end

-- 查找buffer所属的分组（返回第一个找到的分组）
function M.find_buffer_group(buffer_id)
    for _, group in ipairs(groups_data.groups) do
        if vim.tbl_contains(group.buffers, buffer_id) then
            return group
        end
    end
    return nil
end

-- 查找buffer所属的所有分组
function M.find_buffer_groups(buffer_id)
    local found_groups = {}
    for _, group in ipairs(groups_data.groups) do
        if vim.tbl_contains(group.buffers, buffer_id) then
            table.insert(found_groups, group)
        end
    end
    return found_groups
end

-- 获取指定分组的所有buffer
function M.get_group_buffers(group_id)
    local group = find_group_by_id(group_id)
    if not group then
        return {}
    end
    
    -- 过滤无效的buffer
    local valid_buffers = {}
    for _, buffer_id in ipairs(group.buffers) do
        if api.nvim_buf_is_valid(buffer_id) then
            table.insert(valid_buffers, buffer_id)
        end
    end
    
    -- 更新分组的buffer列表，移除无效的buffer
    group.buffers = valid_buffers
    
    return valid_buffers
end

-- 获取当前分组的所有buffer
function M.get_active_group_buffers()
    local active_group = M.get_active_group()
    if not active_group then
        return {}
    end
    
    return M.get_group_buffers(active_group.id)
end

-- 向上移动分组
function M.move_group_up(group_id)
    local group_index = find_group_index_by_id(group_id)
    if not group_index or group_index == 1 then
        return false -- 已经是第一个分组或分组不存在
    end
    
    -- 交换当前分组和上一个分组的位置
    local temp = groups_data.groups[group_index]
    groups_data.groups[group_index] = groups_data.groups[group_index - 1]
    groups_data.groups[group_index - 1] = temp
    
    -- 触发事件
    vim.api.nvim_exec_autocmds("User", {
        pattern = "VBufferLineGroupReordered",
        data = { group_id = group_id, direction = "up", from_index = group_index, to_index = group_index - 1 }
    })
    
    return true
end

-- 向下移动分组
function M.move_group_down(group_id)
    local group_index = find_group_index_by_id(group_id)
    if not group_index or group_index == #groups_data.groups then
        return false -- 已经是最后一个分组或分组不存在
    end
    
    -- 交换当前分组和下一个分组的位置
    local temp = groups_data.groups[group_index]
    groups_data.groups[group_index] = groups_data.groups[group_index + 1]
    groups_data.groups[group_index + 1] = temp
    
    -- 触发事件
    vim.api.nvim_exec_autocmds("User", {
        pattern = "VBufferLineGroupReordered",
        data = { group_id = group_id, direction = "down", from_index = group_index, to_index = group_index + 1 }
    })
    
    return true
end

-- 移动分组到指定位置
function M.move_group_to_position(group_id, target_position)
    local group_index = find_group_index_by_id(group_id)
    if not group_index then
        return false -- 分组不存在
    end
    
    -- 验证目标位置
    if target_position < 1 or target_position > #groups_data.groups then
        return false -- 目标位置无效
    end
    
    if group_index == target_position then
        return true -- 已经在目标位置
    end
    
    -- 移除分组
    local group = table.remove(groups_data.groups, group_index)
    
    -- 插入到目标位置
    table.insert(groups_data.groups, target_position, group)
    
    -- 触发事件
    vim.api.nvim_exec_autocmds("User", {
        pattern = "VBufferLineGroupReordered",
        data = { group_id = group_id, direction = "position", from_index = group_index, to_index = target_position }
    })
    
    return true
end

-- 自动添加新buffer到当前分组
function M.auto_add_buffer(buffer_id)
    if not groups_data.settings.auto_add_new_buffers then
        return
    end
    
    if not api.nvim_buf_is_valid(buffer_id) then
        return
    end
    
    -- 获取当前活跃分组
    local active_group_id = M.get_active_group_id()
    if not active_group_id then
        return
    end
    
    -- 检查buffer是否已经在当前分组中
    local active_group = M.get_active_group()
    if active_group and vim.tbl_contains(active_group.buffers, buffer_id) then
        return  -- 已经在当前分组中了
    end
    
    -- 检查是否是特殊buffer（如侧边栏本身、empty group buffer等）
    local buf_name = vim.api.nvim_buf_get_name(buffer_id)
    local buf_type = vim.api.nvim_buf_get_option(buffer_id, 'buftype')
    if buf_type ~= "" or buf_name == "" or buf_name:match("^%s*$") or buf_name:match("%[Empty Group%]") then
        return  -- 跳过特殊buffer
    end
    
    -- 添加到当前活跃分组
    M.add_buffer_to_group(buffer_id, active_group_id)
end

-- 清理无效的buffer
function M.cleanup_invalid_buffers()
    for _, group in ipairs(groups_data.groups) do
        local valid_buffers = {}
        for _, buffer_id in ipairs(group.buffers) do
            if api.nvim_buf_is_valid(buffer_id) then
                table.insert(valid_buffers, buffer_id)
            end
        end
        group.buffers = valid_buffers
    end
end

-- 获取分组统计信息
function M.get_group_stats()
    return {
        total_groups = #groups_data.groups,
        active_group_id = groups_data.active_group_id,
        total_buffers = vim.tbl_count(vim.api.nvim_list_bufs()),
        managed_buffers = vim.tbl_count(vim.iter(groups_data.groups):map(function(group) return group.buffers end):flatten():totable())
    }
end

-- 初始化模块
function M.setup(opts)
    opts = opts or {}
    
    -- 合并设置
    groups_data.settings = vim.tbl_deep_extend("force", groups_data.settings, opts)
    
    -- 初始化默认分组
    init_default_group()
    
    -- 强制刷新以确保初始状态正确显示
    vim.schedule(function()
        -- 触发界面更新事件
        vim.api.nvim_exec_autocmds("User", {
            pattern = "VBufferLineGroupChanged",
            data = { new_group_id = groups_data.active_group_id }
        })
    end)
    
    -- 设置自动命令
    if groups_data.settings.auto_add_new_buffers then
        api.nvim_create_autocmd("BufEnter", {
            pattern = "*",
            callback = function(args)
                vim.schedule(function()
                    M.auto_add_buffer(args.buf)
                end)
            end,
            desc = "Auto add new buffers to current group"
        })
    end
    
    -- 清理无效buffer的自动命令
    api.nvim_create_autocmd("BufDelete", {
        pattern = "*",
        callback = function(args)
            vim.schedule(function()
                M.remove_buffer_from_all_groups(args.buf)
            end)
        end,
        desc = "Remove deleted buffers from groups"
    })
    
    -- 定期清理无效buffer
    vim.defer_fn(function()
        M.cleanup_invalid_buffers()
    end, 5000)
end

-- 导出调试信息
function M.debug_info()
    return {
        groups_data = groups_data,
        stats = M.get_group_stats()
    }
end

return M