-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/bufferline-integration.lua
-- 与 bufferline.nvim 的集成模块，简单的双向copy策略

local M = {}

local groups = require('vertical-bufferline.groups')

-- 简单状态
local sync_timer = nil
local is_enabled = false
-- 指针：指向当前从bufferline copy数据的目标分组ID
local sync_target_group_id = nil
-- 缓存上次的buffer状态，用于检测buffer内容变化
local last_buffer_state = {}

-- 防重载保护
if _G._vertical_bufferline_integration_loaded then
    print("bufferline-integration already loaded globally, returning existing instance")
    return _G._vertical_bufferline_integration_instance
end

_G._vertical_bufferline_integration_loaded = true

-- 添加调试标志
local debug = false

-- 方向1：bufferline → 当前分组（定时器，99%的时间）
local function sync_bufferline_to_group()
    if not is_enabled then
        return
    end
    
    -- 检查指针：如果为nil，copy失效
    if not sync_target_group_id then
        return
    end

    -- 获取bufferline的所有有效buffer列表（不只是可见的）
    local bufferline_utils = require('bufferline.utils')
    local all_valid_buffers = {}
    
    if bufferline_utils and bufferline_utils.get_valid_buffers then
        all_valid_buffers = bufferline_utils.get_valid_buffers()
    end
    
    -- 调试信息
    if debug then
        print("=== Sync Debug ===")
        print("all_valid_buffers count:", #all_valid_buffers)
        print("sync_target_group_id:", sync_target_group_id)
    end
    
    -- 过滤掉empty group buffer
    local filtered_buffer_ids = {}
    for _, buf_id in ipairs(all_valid_buffers) do
        local buf_name = vim.api.nvim_buf_get_name(buf_id)
        local should_include = not buf_name:match('%[Empty Group%]')
        
        if debug then
            print(string.format("Buffer %d: '%s' -> %s", 
                buf_id, 
                vim.fn.fnamemodify(buf_name, ":t") or "[No Name]", 
                should_include and "included" or "filtered"))
        end
        
        if should_include then
            table.insert(filtered_buffer_ids, buf_id)
        end
    end
    
    local target_group = groups.find_group_by_id(sync_target_group_id)
    
    if target_group then
        -- 构建当前buffer状态快照（包含ID和名称）
        local current_buffer_state = {}
        for _, buf_id in ipairs(filtered_buffer_ids) do
            if vim.api.nvim_buf_is_valid(buf_id) then
                current_buffer_state[buf_id] = vim.api.nvim_buf_get_name(buf_id)
            end
        end
        
        -- 检查是否有变化：buffer列表变化或buffer名称变化
        local buffers_changed = not vim.deep_equal(target_group.buffers, filtered_buffer_ids)
        local names_changed = not vim.deep_equal(last_buffer_state, current_buffer_state)
        
        if buffers_changed or names_changed then
            -- 更新缓存的状态
            last_buffer_state = current_buffer_state
            
            -- 直接更新目标分组的buffer列表
            target_group.buffers = filtered_buffer_ids
            
            -- 触发事件通知分组内容已更新
            vim.api.nvim_exec_autocmds("User", {
                pattern = "VBufferLineGroupBuffersUpdated",
                data = { group_id = sync_target_group_id, buffers = target_group.buffers }
            })
            
            -- 主动刷新侧边栏显示
            local vbl = require('vertical-bufferline')
            if vbl.state and vbl.state.is_sidebar_open and vbl.refresh then
                vbl.refresh()
            end
        end
    end
end

-- 调试函数
function M.toggle_debug()
    debug = not debug
    print("Bufferline integration debug:", debug)
    return debug
end

-- 导出debug状态
function M.get_debug()
    return debug
end

-- 方向2：分组 → bufferline（切换分组时，1%的时间）
function M.set_bufferline_buffers(buffer_list)
    if not is_enabled then
        return
    end
    
    -- 2. 把buffer_list copy到bufferline
    -- 获取所有buffer（不使用bufferline_utils，因为它可能不检查buflisted）
    local all_buffers = vim.api.nvim_list_bufs()
    
    -- 创建buffer集合用于快速查找
    local target_buffer_set = {}
    for _, buf_id in ipairs(buffer_list) do
        target_buffer_set[buf_id] = true
    end
    
    -- 隐藏不在目标列表中的buffer（设置为unlisted）
    for _, buf_id in ipairs(all_buffers) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            if target_buffer_set[buf_id] then
                -- 确保目标buffer是listed的
                pcall(vim.api.nvim_buf_set_option, buf_id, 'buflisted', true)
            else
                -- 隐藏不在目标列表中的buffer
                pcall(vim.api.nvim_buf_set_option, buf_id, 'buflisted', false)
            end
        end
    end
    
    -- 处理空分组的情况：如果buffer_list为空，需要显示空状态
    if #buffer_list == 0 then
        M.handle_empty_group_display()
    else
        -- 如果有buffer，切换到第一个有效的buffer
        for _, buf_id in ipairs(buffer_list) do
            if vim.api.nvim_buf_is_valid(buf_id) then
                pcall(vim.api.nvim_set_current_buf, buf_id)
                break
            end
        end
    end
    
    -- 刷新bufferline
    local bufferline_ui = require('bufferline.ui')
    if bufferline_ui.refresh then
        bufferline_ui.refresh()
    end
    
    -- 3. 把指针指向新的分组（由调用者设置）
    -- 这一步由 set_sync_target 函数完成
end

-- 处理空分组显示：创建或切换到一个空的临时buffer
function M.handle_empty_group_display()
    -- 查找或创建一个专用的空分组buffer
    local empty_group_buffer = nil
    local all_buffers = vim.api.nvim_list_bufs()
    
    -- 查找现有的空分组buffer
    for _, buf_id in ipairs(all_buffers) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            local buf_name = vim.api.nvim_buf_get_name(buf_id)
            if buf_name:match('%[Empty Group%]') then
                empty_group_buffer = buf_id
                break
            end
        end
    end
    
    -- 如果没有找到，创建一个新的空buffer
    if not empty_group_buffer then
        empty_group_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(empty_group_buffer, '[Empty Group]')
        vim.api.nvim_buf_set_option(empty_group_buffer, 'buftype', 'nofile')
        vim.api.nvim_buf_set_option(empty_group_buffer, 'swapfile', false)
        vim.api.nvim_buf_set_option(empty_group_buffer, 'buflisted', false)
        
        -- 设置一些帮助文本
        local lines = {
            "# Empty Group",
            "",
            "This group currently has no files.",
            "",
            "To add files to this group:",
            "• Open files in other groups and switch back",
            "• Or use :VBufferLineAddCurrentToGroup",
        }
        vim.api.nvim_buf_set_lines(empty_group_buffer, 0, -1, false, lines)
        vim.api.nvim_buf_set_option(empty_group_buffer, 'modifiable', false)
    end
    
    -- 切换到空buffer
    pcall(vim.api.nvim_set_current_buf, empty_group_buffer)
end

-- 设置同步目标分组（原子操作的第3步）
function M.set_sync_target(group_id)
    sync_target_group_id = group_id
end

-- 手动同步函数
function M.manual_sync()
    local bufferline_ui = require('bufferline.ui')
    if bufferline_ui and bufferline_ui.refresh then
        bufferline_ui.refresh()
    end
    
    local vbl = require('vertical-bufferline')
    if vbl.state and vbl.state.is_sidebar_open and vbl.refresh then
        vbl.refresh()
    end
    
    vim.notify("Manual sync triggered", vim.log.levels.INFO)
end

-- 启用集成
function M.enable()
    if is_enabled then
        return true
    end
    
    -- 确保 bufferline 已加载
    local ok_state, _ = pcall(require, 'bufferline.state')
    if not ok_state then
        vim.notify("bufferline.nvim not found", vim.log.levels.WARN)
        return false
    end
    
    -- 启动定时同步：bufferline → 分组
    sync_timer = vim.loop.new_timer()
    if sync_timer then
        sync_timer:start(100, 100, vim.schedule_wrap(sync_bufferline_to_group))
    end
    
    -- 设置初始同步目标为当前活跃分组
    local active_group = groups.get_active_group()
    if active_group then
        sync_target_group_id = active_group.id
    end
    
    is_enabled = true
    return true
end

-- 禁用集成
function M.disable()
    if not is_enabled then
        return
    end
    
    -- 停止定时器
    if sync_timer then
        sync_timer:stop()
        sync_timer:close()
        sync_timer = nil
    end
    
    is_enabled = false
end

-- 切换集成
function M.toggle()
    if is_enabled then
        M.disable()
    else
        M.enable()
    end
end

-- 状态检查
function M.status()
    local bufferline_available = pcall(require, 'bufferline.state')
    return {
        is_enabled = is_enabled,
        has_timer = sync_timer ~= nil,
        timer_active = sync_timer and sync_timer:is_active() or false,
        sync_target_group_id = sync_target_group_id,
        bufferline_available = bufferline_available
    }
end

-- 获取当前分组的 buffer 信息（为了兼容init.lua）
function M.get_group_buffer_info()
    local active_group = groups.get_active_group()
    if not active_group then
        return {
            group_name = "No group",
            total_buffers = 0,
            visible_buffers = 0
        }
    end
    
    local active_buffers = groups.get_active_group_buffers()
    local valid_buffers = 0
    
    for _, buf_id in ipairs(active_buffers) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            valid_buffers = valid_buffers + 1
        end
    end
    
    return {
        group_name = active_group.name,
        total_buffers = #active_buffers,
        visible_buffers = valid_buffers
    }
end

-- 强制刷新（为了兼容session.lua）
function M.force_refresh()
    vim.schedule(function()
        local bufferline_ui = require('bufferline.ui')
        if bufferline_ui.refresh then
            bufferline_ui.refresh()
        end
        
        -- 刷新我们的侧边栏
        local vbl = require('vertical-bufferline')
        if vbl.state and vbl.state.is_sidebar_open and vbl.refresh then
            vbl.refresh()
        end
    end)
end

-- 安全的buffer关闭函数，避免E85错误
function M.smart_close_buffer(target_buf)
    target_buf = target_buf or vim.api.nvim_get_current_buf()
    
    -- 检查是否有修改未保存
    if vim.api.nvim_buf_get_option(target_buf, "modified") then
        local choice = vim.fn.confirm("Buffer has unsaved changes. Close anyway?", "&Yes\n&No", 2)
        if choice ~= 1 then
            return false
        end
    end
    
    -- 获取所有listed buffers
    local all_buffers = vim.api.nvim_list_bufs()
    local listed_buffers = {}
    for _, buf_id in ipairs(all_buffers) do
        if vim.api.nvim_buf_is_valid(buf_id) and vim.api.nvim_buf_get_option(buf_id, 'buflisted') then
            table.insert(listed_buffers, buf_id)
        end
    end
    
    -- 如果这是最后一个listed buffer，创建一个新的empty buffer
    if #listed_buffers <= 1 then
        -- 创建新的empty buffer
        local new_buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_set_current_buf(new_buf)
        
        -- 然后安全地删除目标buffer
        if vim.api.nvim_buf_is_valid(target_buf) then
            pcall(vim.api.nvim_buf_delete, target_buf, { force = true })
        end
        
        -- 处理空分组显示
        M.handle_empty_group_display()
    else
        -- 如果还有其他buffer，先切换到下一个
        local next_buf = nil
        for _, buf_id in ipairs(listed_buffers) do
            if buf_id ~= target_buf then
                next_buf = buf_id
                break
            end
        end
        
        if next_buf then
            vim.api.nvim_set_current_buf(next_buf)
        end
        
        -- 然后删除目标buffer
        if vim.api.nvim_buf_is_valid(target_buf) then
            pcall(vim.api.nvim_buf_delete, target_buf, { force = true })
        end
    end
    
    return true
end

-- 保存全局实例
_G._vertical_bufferline_integration_instance = M

return M
