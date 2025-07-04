-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/bufferline-integration.lua
-- 与 bufferline.nvim 的集成模块，实现分组过滤功能

local M = {}

local groups = require('vertical-bufferline.groups')

-- 创建空分组的scratch buffer
local empty_group_buffer = nil

local function get_or_create_empty_buffer()
    -- 如果buffer不存在或无效，创建新的
    if not empty_group_buffer or not vim.api.nvim_buf_is_valid(empty_group_buffer) then
        empty_group_buffer = vim.api.nvim_create_buf(false, true)
        
        -- 设置buffer属性
        vim.api.nvim_buf_set_option(empty_group_buffer, 'buftype', 'nofile')
        vim.api.nvim_buf_set_option(empty_group_buffer, 'bufhidden', 'hide')
        vim.api.nvim_buf_set_option(empty_group_buffer, 'swapfile', false)
        vim.api.nvim_buf_set_option(empty_group_buffer, 'modifiable', false)
        
        -- 设置buffer名称
        vim.api.nvim_buf_set_name(empty_group_buffer, "[Empty Group]")
    end
    
    return empty_group_buffer
end

local function update_empty_buffer_content()
    if not empty_group_buffer or not vim.api.nvim_buf_is_valid(empty_group_buffer) then
        return
    end
    
    local active_group = groups.get_active_group()
    local all_groups = groups.get_all_groups()
    
    local lines = {
        "",
        "   📭 Empty Group",
        "",
        "   Group: " .. (active_group and active_group.name or "Unknown"),
        "   Total groups: " .. #all_groups,
        "",
        "   Open any file to add it to this group",
        ""
    }
    
    vim.api.nvim_buf_set_option(empty_group_buffer, 'modifiable', true)
    vim.api.nvim_buf_set_lines(empty_group_buffer, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(empty_group_buffer, 'modifiable', false)
end

-- 保存原始的 bufferline 函数引用
local original_functions = {}
local is_hooked = false

-- 过滤 buffer 列表，只返回当前分组的 buffer
local function filter_buffers_by_group(buffers)
    local active_group_buffers = groups.get_active_group_buffers()
    local active_group = groups.get_active_group()
    
    if #active_group_buffers == 0 then
        -- 如果当前分组没有 buffer，返回空列表
        return {}
    end
    
    -- 创建快速查找表
    local group_buffer_set = {}
    for _, buffer_id in ipairs(active_group_buffers) do
        group_buffer_set[buffer_id] = true
    end
    
    -- 过滤 buffer 列表
    local filtered_buffers = {}
    for _, buffer in ipairs(buffers) do
        if buffer.id and group_buffer_set[buffer.id] then
            table.insert(filtered_buffers, buffer)
        end
    end
    
    return filtered_buffers
end

-- 钩入 bufferline 的 get_components 函数
local function hook_get_components()
    local bufferline_buffers = require('bufferline.buffers')
    
    if not original_functions.get_components then
        original_functions.get_components = bufferline_buffers.get_components
    end
    
    bufferline_buffers.get_components = function(state)
        -- 如果启用了分组过滤，我们需要在创建components之前就过滤buffer list
        if M.is_group_filtering_enabled() then
            -- 获取原始的 get_components 逻辑，但修改buffer列表
            local bufferline_utils = require('bufferline.utils')
            local options = require('bufferline.config').options
            local buf_nums = bufferline_utils.get_valid_buffers()
            local filter = options.custom_filter
            -- 应用custom_filter（从原buffers.lua复制的逻辑）
            if filter then
                local filtered_buf_nums = {}
                for _, buf_id in ipairs(buf_nums) do
                    if filter(buf_id, buf_nums) then
                        table.insert(filtered_buf_nums, buf_id)
                    end
                end
                buf_nums = filtered_buf_nums
            end
            
            -- 应用分组过滤到buffer numbers
            local active_group_buffers = groups.get_active_group_buffers()
            
            -- 调试信息
            local debug_msg = string.format("BufferLine integration: %d valid buffers, %d group buffers", 
                #buf_nums, #active_group_buffers)
            
            -- 详细调试：显示具体的buffer信息
            if os.getenv("NVIM_VBL_DEBUG") == "1" then
                print("=== Buffer Mismatch Debug ===")
                print("Valid buffers from bufferline:")
                for i, buf_id in ipairs(buf_nums) do
                    local name = vim.api.nvim_buf_get_name(buf_id)
                    local loaded = vim.api.nvim_buf_is_loaded(buf_id)
                    local listed = vim.bo[buf_id].buflisted
                    print(string.format("  [%d] %s (loaded:%s, listed:%s)", 
                        buf_id, vim.fn.fnamemodify(name, ":t"), loaded, listed))
                end
                
                print("Group buffers:")
                for i, buf_id in ipairs(active_group_buffers) do
                    if vim.api.nvim_buf_is_valid(buf_id) then
                        local name = vim.api.nvim_buf_get_name(buf_id)
                        local loaded = vim.api.nvim_buf_is_loaded(buf_id)
                        local listed = vim.bo[buf_id].buflisted
                        local exists = vim.fn.filereadable(name)
                        print(string.format("  [%d] %s (loaded:%s, listed:%s, exists:%d)", 
                            buf_id, vim.fn.fnamemodify(name, ":t"), loaded, listed, exists))
                    else
                        print(string.format("  [%d] INVALID", buf_id))
                    end
                end
                print("========================")
            end
            
            if #active_group_buffers == 0 then
                -- 在session加载期间，如果分组缓冲区为空，但有有效缓冲区，暂时显示所有缓冲区
                -- 这避免了在session加载过程中出现空的tabline
                local all_groups = groups.get_all_groups()
                if #all_groups > 0 and #buf_nums > 0 then
                    -- 有分组存在但分组为空，可能是session加载中的临时状态
                    -- 暂时不过滤，让bufferline显示所有缓冲区
                    debug_msg = debug_msg .. " (session loading, showing all buffers temporarily)"
                else
                    buf_nums = {}
                    debug_msg = debug_msg .. " (no group buffers, empty result)"
                end
            else
                local group_buffer_set = {}
                for _, buffer_id in ipairs(active_group_buffers) do
                    group_buffer_set[buffer_id] = true
                end
                
                local filtered_buf_nums = {}
                for _, buf_id in ipairs(buf_nums) do
                    if group_buffer_set[buf_id] then
                        table.insert(filtered_buf_nums, buf_id)
                    end
                end
                buf_nums = filtered_buf_nums
                debug_msg = debug_msg .. string.format(" (filtered to %d)", #buf_nums)
            end
            
            -- 仅在开发模式下打印调试信息
            if os.getenv("NVIM_VBL_DEBUG") == "1" then
                print(debug_msg)
            end
            
            -- 现在使用过滤后的buffer list重新构建components
            local pick = require("bufferline.pick")
            local duplicates = require("bufferline.duplicates")
            local diagnostics = require("bufferline.diagnostics")
            local models = require("bufferline.models")
            local ui = require("bufferline.ui")
            
            -- 从原函数复制的逻辑，但使用过滤后的buf_nums
            local function get_updated_buffers(buf_nums, sorted)
                if not sorted then return buf_nums end
                local nums = { unpack(buf_nums) }
                local utils = require('bufferline.utils')
                local reverse_lookup_sorted = utils.tbl_reverse_lookup(sorted)
                
                local sort_by_sorted = function(buf_id_1, buf_id_2)
                    local buf_1_rank = reverse_lookup_sorted[buf_id_1]
                    local buf_2_rank = reverse_lookup_sorted[buf_id_2]
                    if not buf_1_rank then return false end
                    if not buf_2_rank then return true end
                    return buf_1_rank < buf_2_rank
                end
                
                table.sort(nums, sort_by_sorted)
                return nums
            end
            
            buf_nums = get_updated_buffers(buf_nums, state.custom_sort)
            
            pick.reset()
            duplicates.reset()
            local components = {}
            local all_diagnostics = diagnostics.get(options)
            local Buffer = models.Buffer
            
            for i, buf_id in ipairs(buf_nums) do
                local buf = Buffer:new({
                    path = vim.api.nvim_buf_get_name(buf_id),
                    id = buf_id,
                    ordinal = i,  -- 这里i现在是分组内的正确序号
                    diagnostics = all_diagnostics[buf_id],
                    name_formatter = options.name_formatter,
                })
                buf.letter = pick.get(buf)
                buf.group = require('bufferline.groups').set_id(buf)
                components[i] = buf
            end
            
            return vim.tbl_map(function(buf) return ui.element(state, buf) end, duplicates.mark(components))
        else
            -- 如果没有启用分组过滤，使用原始函数
            return original_functions.get_components(state)
        end
    end
end

-- 钩入 bufferline 的状态管理
local function hook_bufferline_state()
    local bufferline_state = require('bufferline.state')
    
    -- 保存原始的 set 函数
    if not original_functions.state_set then
        original_functions.state_set = bufferline_state.set
    end
    
    bufferline_state.set = function(state)
        -- 在设置状态时，如果启用了分组过滤，则过滤 components
        if state.components and M.is_group_filtering_enabled() then
            state.components = filter_buffers_by_group(state.components)
        end
        
        return original_functions.state_set(state)
    end
end

-- 检查是否启用了分组过滤
function M.is_group_filtering_enabled()
    local all_groups = groups.get_all_groups()
    local active_group = groups.get_active_group()
    
    if not active_group then
        return false
    end
    
    -- 只要有分组存在就启用过滤（包括只有默认分组的情况）
    -- 这样用户可以看到分组功能的界面
    local enabled = #all_groups > 0
    return enabled
end

-- 启用 bufferline 集成
function M.enable()
    if is_hooked then
        return
    end
    
    -- 确保 bufferline 已加载
    local ok_utils, _ = pcall(require, 'bufferline.utils')
    local ok_state, _ = pcall(require, 'bufferline.state')
    
    if not ok_utils or not ok_state then
        vim.notify("bufferline.nvim not found, group filtering disabled", vim.log.levels.WARN)
        return false
    end
    
    -- 钩入相关函数
    hook_get_components()
    hook_bufferline_state()
    
    is_hooked = true
    
    -- 监听分组变化事件，自动刷新 bufferline
    vim.api.nvim_create_autocmd("User", {
        pattern = {
            "VBufferLineGroupChanged", 
            "VBufferLineGroupCreated", 
            "VBufferLineGroupDeleted",
            "VBufferLineBufferAddedToGroup", 
            "VBufferLineBufferRemovedFromGroup"
        },
        callback = function()
            -- 检查是否需要切换到空buffer
            vim.schedule(function()
                M.handle_empty_group_display()
            end)
            
            -- 延迟刷新以避免递归调用
            M.force_refresh()
        end,
        desc = "Refresh bufferline when groups change"
    })
    
    -- bufferline集成已启用
    
    -- 立即刷新以显示分组信息
    vim.schedule(function()
        local bufferline_ui = require('bufferline.ui')
        if bufferline_ui.refresh then
            bufferline_ui.refresh()
        end
        -- 也刷新我们的侧边栏
        if require('vertical-bufferline').refresh then
            require('vertical-bufferline').refresh()
        end
    end)
    
    return true
end

-- 禁用 bufferline 集成
function M.disable()
    if not is_hooked then
        return
    end
    
    -- 恢复原始函数
    if original_functions.get_components then
        require('bufferline.buffers').get_components = original_functions.get_components
    end
    
    if original_functions.state_set then
        require('bufferline.state').set = original_functions.state_set
    end
    
    is_hooked = false
    
    -- 移除事件监听
    vim.api.nvim_del_augroup_by_name("VBufferLineGroupIntegration")
    
    -- 刷新 bufferline 以显示所有 buffer
    vim.schedule(function()
        local bufferline_ui = require('bufferline.ui')
        if bufferline_ui.refresh then
            bufferline_ui.refresh()
        end
    end)
    
    -- bufferline集成已禁用
end

-- 切换 bufferline 集成
function M.toggle()
    if is_hooked then
        M.disable()
    else
        M.enable()
    end
end

-- 处理空分组的显示
function M.handle_empty_group_display()
    local active_group_buffers = groups.get_active_group_buffers()
    local current_buffer = vim.api.nvim_get_current_buf()
    
    if #active_group_buffers == 0 then
        -- 当前分组为空，切换到empty buffer
        local empty_buf = get_or_create_empty_buffer()
        update_empty_buffer_content()
        
        -- 只有当前不是empty buffer时才切换
        if current_buffer ~= empty_buf then
            vim.api.nvim_set_current_buf(empty_buf)
        end
    else
        -- 当前分组不为空
        local should_switch = false
        
        -- 如果显示的是empty buffer，需要切换
        if current_buffer == empty_group_buffer then
            should_switch = true
        end
        
        -- 如果当前buffer不在活跃分组中，也需要切换
        if not vim.tbl_contains(active_group_buffers, current_buffer) then
            should_switch = true
        end
        
        if should_switch then
            -- 临时禁用自动添加以防止unwanted migration
            local groups = require('vertical-bufferline.groups')
            local was_disabled = groups.is_auto_add_disabled()
            groups.set_auto_add_disabled(true)
            
            -- 找到第一个有效的buffer
            for _, buffer_id in ipairs(active_group_buffers) do
                if vim.api.nvim_buf_is_valid(buffer_id) then
                    vim.api.nvim_set_current_buf(buffer_id)
                    break
                end
            end
            
            -- 延迟恢复自动添加状态，避免立即触发的BufEnter事件
            vim.defer_fn(function()
                groups.set_auto_add_disabled(was_disabled)
            end, 100)
        end
    end
end

-- 强制刷新 bufferline（增强版本）
function M.force_refresh()
    -- 立即同步刷新
    local bufferline_ui = require('bufferline.ui')
    if bufferline_ui.refresh then
        bufferline_ui.refresh()
    end
    
    -- 使用多个调度时间点来确保完全同步
    vim.schedule(function()
        -- 第一轮：基础刷新
        if bufferline_ui.refresh then
            bufferline_ui.refresh()
        end
        
        -- 刷新我们的侧边栏
        local vbl = require('vertical-bufferline')
        if vbl.state and vbl.state.is_sidebar_open and vbl.refresh then
            vbl.refresh()
        end
        
        -- 强制重绘
        vim.cmd('redraw!')
        
        -- 第二轮：延迟确保同步（用于session加载等场景）
        vim.defer_fn(function()
            if bufferline_ui.refresh then
                bufferline_ui.refresh()
            end
            
            if vbl.state and vbl.state.is_sidebar_open and vbl.refresh then
                vbl.refresh()
            end
            
            vim.cmd('redraw!')
        end, 50)
    end)
end

-- 获取当前分组的 buffer 统计信息（增强调试版本）
function M.get_group_buffer_info()
    local active_group = groups.get_active_group()
    if not active_group then
        return {
            group_name = "No group",
            total_buffers = 0,
            visible_buffers = 0,
            debug_info = "No active group found"
        }
    end
    
    local active_buffers = groups.get_active_group_buffers()
    local valid_buffers = 0
    local buffer_details = {}
    
    -- 收集调试信息
    for _, buf_id in ipairs(active_buffers) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            valid_buffers = valid_buffers + 1
            local name = vim.api.nvim_buf_get_name(buf_id)
            table.insert(buffer_details, {
                id = buf_id,
                name = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]",
                valid = true
            })
        else
            table.insert(buffer_details, {
                id = buf_id,
                name = "[Invalid]",
                valid = false
            })
        end
    end
    
    return {
        group_name = active_group.name,
        group_id = active_group.id,
        total_buffers = #active_buffers,
        valid_buffers = valid_buffers,
        visible_buffers = valid_buffers,  -- 使用有效缓冲区数量
        max_buffers = 10,  -- 对应用户的快捷键数量
        buffer_details = buffer_details,
        debug_info = string.format("Group '%s' (ID: %s) has %d/%d valid buffers", 
            active_group.name, active_group.id, valid_buffers, #active_buffers)
    }
end

-- 自动管理新 buffer
function M.auto_manage_new_buffer(buffer_id)
    if not M.is_group_filtering_enabled() then
        return
    end
    
    -- 如果当前分组建议已满，提示用户但仍然添加
    local active_group = groups.get_active_group()
    if active_group and #active_group.buffers >= 10 then
        vim.notify("Group '" .. active_group.name .. "' has many buffers. Consider creating a new group with <leader>gc", vim.log.levels.INFO)
    end
    
    -- 自动添加到当前分组
    groups.auto_add_buffer(buffer_id)
end

-- 检查集成状态（增强调试版本）
function M.status()
    local all_groups = groups.get_all_groups()
    local group_info = M.get_group_buffer_info()
    
    return {
        is_hooked = is_hooked,
        filtering_enabled = M.is_group_filtering_enabled(),
        group_info = group_info,
        total_groups = #all_groups,
        bufferline_state = {
            has_ui = pcall(require, 'bufferline.ui'),
            has_state = pcall(require, 'bufferline.state'),
            has_buffers = pcall(require, 'bufferline.buffers')
        },
        integration_health = {
            original_functions_preserved = {
                get_components = original_functions.get_components ~= nil,
                state_set = original_functions.state_set ~= nil
            }
        }
    }
end

-- 调试函数：打印详细状态信息
function M.debug_session_sync()
    local status = M.status()
    local active_group = groups.get_active_group()
    
    print("=== BufferLine Integration Debug ===")
    print("Hooked:", status.is_hooked)
    print("Filtering enabled:", status.filtering_enabled)
    print("Total groups:", status.total_groups)
    
    if active_group then
        print("\nActive Group:")
        print("  Name:", active_group.name)
        print("  ID:", active_group.id)
        print("  Buffers count:", #active_group.buffers)
        
        local group_info = status.group_info
        print("\nBuffer Details:")
        for i, detail in ipairs(group_info.buffer_details) do
            print(string.format("  %d. [%d] %s (valid: %s)", 
                i, detail.id, detail.name, detail.valid))
        end
    else
        print("\nNo active group")
    end
    
    print("\nBufferLine Health:")
    print("  UI module:", status.bufferline_state.has_ui)
    print("  State module:", status.bufferline_state.has_state)
    print("  Buffers module:", status.bufferline_state.has_buffers)
    
    print("\nIntegration Health:")
    print("  get_components preserved:", status.integration_health.original_functions_preserved.get_components)
    print("  state_set preserved:", status.integration_health.original_functions_preserved.state_set)
    
    return status
end

return M