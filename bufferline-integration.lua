-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/bufferline-integration.lua
-- Integration module with bufferline.nvim, simple bidirectional copy strategy

local M = {}

local groups = require('vertical-bufferline.groups')

-- Simple state
local sync_timer = nil
local is_enabled = false
-- Pointer: points to the target group ID for copying data from bufferline
local sync_target_group_id = nil
-- Cache last buffer state for detecting buffer content changes
local last_buffer_state = {}
-- Cache last current buffer for detecting current buffer changes
local last_current_buffer = nil
-- No longer need global cache - position info is stored in each group

-- Prevent reload protection
if _G._vertical_bufferline_integration_loaded then
    return _G._vertical_bufferline_integration_instance
end

_G._vertical_bufferline_integration_loaded = true


-- Get buffer index in our target list (for sorting)
local function get_buffer_index_in_list(buf_id, buffer_list)
    for i, list_buf_id in ipairs(buffer_list) do
        if list_buf_id == buf_id then
            return i
        end
    end
    -- Return a large number for buffers not in our list (will be sorted last)
    return 999999
end

-- Check if it's a special buffer (based on buftype)
local function is_special_buffer(buf_id)
    if not vim.api.nvim_buf_is_valid(buf_id) then
        return true -- Invalid buffer is also considered special
    end
    local buftype = vim.api.nvim_buf_get_option(buf_id, 'buftype')
    return buftype ~= '' -- Non-empty indicates special buffer (nofile, quickfix, help, terminal, etc.)
end

-- Get bufferline's custom sort order for proper buffer ordering
local function get_bufferline_sorted_buffers()
    local bufferline_utils = require('bufferline.utils')
    local bufferline_state = require('bufferline.state')
    
    -- Get all valid buffers from bufferline
    local all_valid_buffers = {}
    if bufferline_utils and bufferline_utils.get_valid_buffers then
        all_valid_buffers = bufferline_utils.get_valid_buffers()
    end
    
    -- If bufferline has a custom sort order, use it
    if bufferline_state and bufferline_state.custom_sort then
        local custom_sort = bufferline_state.custom_sort
        local reverse_lookup = {}
        for i, buf_id in ipairs(custom_sort) do
            reverse_lookup[buf_id] = i
        end
        
        -- Sort valid buffers according to custom_sort order
        local sorted_buffers = {}
        for _, buf_id in ipairs(all_valid_buffers) do
            table.insert(sorted_buffers, buf_id)
        end
        
        table.sort(sorted_buffers, function(a, b)
            local a_rank = reverse_lookup[a]
            local b_rank = reverse_lookup[b]
            if not a_rank then return false end
            if not b_rank then return true end
            return a_rank < b_rank
        end)
        
        return sorted_buffers
    end
    
    -- Fallback to default order
    return all_valid_buffers
end

--- Get real buffer position information from bufferline state
--- @return table Buffer position mapping {buffer_id -> {local_pos = N or nil, global_pos = M}}
local function get_real_position_info()
    local state = require('bufferline.state')
    local all_buffers = state.components or {}
    local visible_buffers = state.visible_components or {}
    
    local position_info = {}
    
    -- Build visible buffer ID to local position mapping
    local visible_positions = {}
    for local_idx, component in ipairs(visible_buffers) do
        if component and component.id then
            visible_positions[component.id] = local_idx
        end
    end
    
    -- Build position info for visible buffers only (local positions)
    for buffer_id, local_pos in pairs(visible_positions) do
        position_info[buffer_id] = local_pos
    end
    
    return position_info
end

--- Update position info for current active group when cursor is in a normal file buffer
local function update_active_group_position_info()
    local current_buf = vim.api.nvim_get_current_buf()
    local state_module = require('vertical-bufferline.state')
    
    -- Only update when current buffer is not sidebar and is a normal file buffer
    if state_module.get_buf_id and current_buf ~= state_module.get_buf_id() and not is_special_buffer(current_buf) then
        local active_group = groups.get_active_group()
        if active_group then
            local position_info = get_real_position_info()
            groups.update_group_position_info(active_group.id, position_info)
        end
    end
end

-- Direction 1: bufferline → current group (timer, 99% of the time)
local function sync_bufferline_to_group()
    if not is_enabled then
        return
    end

    -- Check pointer: if nil, copy is invalid
    if not sync_target_group_id then
        return
    end

    -- Get all valid buffer list from bufferline with proper ordering
    local all_valid_buffers = get_bufferline_sorted_buffers()


    -- Filter out special buffers (based on buftype)
    local filtered_buffer_ids = {}
    for _, buf_id in ipairs(all_valid_buffers) do
        local should_include = not is_special_buffer(buf_id)

        -- Ensure special buffers remain unlisted
        if is_special_buffer(buf_id) then
            pcall(vim.api.nvim_buf_set_option, buf_id, 'buflisted', false)
        end


        if should_include then
            table.insert(filtered_buffer_ids, buf_id)
        end
    end

    local target_group = groups.find_group_by_id(sync_target_group_id)

    if target_group then
        -- Build current buffer state snapshot (including ID and name)
        local current_buffer_state = {}
        for _, buf_id in ipairs(filtered_buffer_ids) do
            if vim.api.nvim_buf_is_valid(buf_id) then
                current_buffer_state[buf_id] = vim.api.nvim_buf_get_name(buf_id)
            end
        end

        -- Check for changes: buffer list changes, buffer name changes, or current buffer changes
        local buffers_changed = not vim.deep_equal(target_group.buffers, filtered_buffer_ids)
        local names_changed = not vim.deep_equal(last_buffer_state, current_buffer_state)
        local current_buf = vim.api.nvim_get_current_buf()
        local current_buffer_changed = last_current_buffer ~= current_buf

        if buffers_changed or names_changed or current_buffer_changed then
            -- Update cached state
            last_buffer_state = current_buffer_state
            last_current_buffer = current_buf

            -- Update position info for active group when we're not in sidebar
            update_active_group_position_info()

            -- Directly update the target group's buffer list
            target_group.buffers = filtered_buffer_ids
            
            -- Sync group history with current buffer (only when current buffer is actually in the group)
            local current_buffer_in_group = vim.tbl_contains(filtered_buffer_ids, current_buf) and current_buf or nil
            if current_buffer_in_group then
                groups.sync_group_history_with_current(sync_target_group_id, current_buffer_in_group)
            end

            -- Trigger event to notify that group content has been updated
            vim.api.nvim_exec_autocmds("User", {
                pattern = "VBufferLineGroupBuffersUpdated",
                data = { group_id = sync_target_group_id, buffers = target_group.buffers }
            })

            -- Actively refresh sidebar display
            local vbl = require('vertical-bufferline')
            if vbl.state and vbl.state.is_sidebar_open and vbl.refresh then
                vbl.refresh("bufferline_sync")
            end
        end
    end
end


--- Direction 2: group → bufferline (when switching groups, 1% of the time)
--- @param buffer_list table List of buffer IDs to show in bufferline
function M.set_bufferline_buffers(buffer_list)
    if not is_enabled then
        return
    end

    -- 2. Copy buffer_list to bufferline
    -- Get all buffers (not using bufferline_utils, as it may not check buflisted)
    local all_buffers = vim.api.nvim_list_bufs()

    -- Create buffer set for fast lookup
    local target_buffer_set = {}
    for _, buf_id in ipairs(buffer_list) do
        target_buffer_set[buf_id] = true
    end

    -- Hide buffers not in target list (set to unlisted)
    for _, buf_id in ipairs(all_buffers) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            if target_buffer_set[buf_id] then
                -- Ensure target buffer is listed
                pcall(vim.api.nvim_buf_set_option, buf_id, 'buflisted', true)
            else
                -- Hide buffers not in target list
                pcall(vim.api.nvim_buf_set_option, buf_id, 'buflisted', false)
            end
        end
    end

    -- Force bufferline to follow our buffer order
    if #buffer_list > 1 then
        -- Use vim.schedule to ensure bufferline state is updated first
        vim.schedule(function()
            local ok, bufferline = pcall(require, 'bufferline')
            if ok and bufferline.sort_buffers_by then
                -- Force bufferline to sort according to our buffer_list order
                bufferline.sort_buffers_by(function(buf_a, buf_b)
                    local index_a = get_buffer_index_in_list(buf_a.id, buffer_list)
                    local index_b = get_buffer_index_in_list(buf_b.id, buffer_list)
                    return index_a < index_b
                end)
            end
        end)
    end

    -- Handle empty group case: if buffer_list is empty, need to display empty state
    if #buffer_list == 0 then
        M.handle_empty_group_display()
    else
        -- If there are buffers, switch to the first valid buffer
        for _, buf_id in ipairs(buffer_list) do
            if vim.api.nvim_buf_is_valid(buf_id) then
                pcall(vim.api.nvim_set_current_buf, buf_id)
                break
            end
        end
    end

    -- Refresh bufferline
    local bufferline_ui = require('bufferline.ui')
    if bufferline_ui.refresh then
        bufferline_ui.refresh()
    end

    -- 3. Point the pointer to the new group (set by caller)
    -- This step is completed by the set_sync_target function
end

--- Handle empty group display: create or switch to an empty temporary buffer
function M.handle_empty_group_display()
    -- First hide all currently listed normal buffers (keep special buffers)
    local all_buffers = vim.api.nvim_list_bufs()
    for _, buf_id in ipairs(all_buffers) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            local buftype = vim.api.nvim_buf_get_option(buf_id, 'buftype')
            local buflisted = vim.api.nvim_buf_get_option(buf_id, 'buflisted')
            local buf_name = vim.api.nvim_buf_get_name(buf_id)

            -- If it's a normal empty buffer (no name), hide it
            if buftype == '' and buflisted and (buf_name == '' or buf_name:match('^%s*$')) then
                pcall(vim.api.nvim_buf_set_option, buf_id, 'buflisted', false)
            end
        end
    end

    -- Find or create a dedicated empty group buffer
    local empty_group_buffer = nil

    -- Find existing empty group buffer (using buftype check)
    for _, buf_id in ipairs(all_buffers) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            local buftype = vim.api.nvim_buf_get_option(buf_id, 'buftype')
            local buf_name = vim.api.nvim_buf_get_name(buf_id)
            if buftype == 'nofile' and buf_name:match('%[Empty Group%]') then
                empty_group_buffer = buf_id
                break
            end
        end
    end

    -- If not found, create a new empty buffer
    if not empty_group_buffer then
        empty_group_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(empty_group_buffer, '[Empty Group]')
        vim.api.nvim_buf_set_option(empty_group_buffer, 'buftype', 'nofile')
        vim.api.nvim_buf_set_option(empty_group_buffer, 'swapfile', false)
        vim.api.nvim_buf_set_option(empty_group_buffer, 'buflisted', false)

        -- Set some help text
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

    -- Switch to empty buffer
    pcall(vim.api.nvim_set_current_buf, empty_group_buffer)
end

--- Set sync target group (step 3 of atomic operation)
--- @param group_id string Group ID to sync with bufferline
function M.set_sync_target(group_id)
    sync_target_group_id = group_id
end

--- Manual sync function
function M.manual_sync()
    local bufferline_ui = require('bufferline.ui')
    if bufferline_ui and bufferline_ui.refresh then
        bufferline_ui.refresh()
    end

    local vbl = require('vertical-bufferline')
    if vbl.state and vbl.state.is_sidebar_open and vbl.refresh then
        vbl.refresh("manual_sync")
    end

    vim.notify("Manual sync triggered", vim.log.levels.INFO)
end

--- Enable integration
--- @return boolean success
function M.enable()
    if is_enabled then
        return true
    end

    -- Ensure bufferline is loaded
    local ok_state, _ = pcall(require, 'bufferline.state')
    if not ok_state then
        vim.notify("bufferline.nvim not found", vim.log.levels.WARN)
        return false
    end

    -- Start timed sync: bufferline → group
    sync_timer = vim.loop.new_timer()
    if sync_timer then
        sync_timer:start(100, 100, vim.schedule_wrap(sync_bufferline_to_group))
    end

    -- Set initial sync target to current active group
    local active_group = groups.get_active_group()
    if active_group then
        sync_target_group_id = active_group.id
    end

    -- Initialize position info for current active group
    update_active_group_position_info()

    is_enabled = true
    return true
end

--- Disable integration
function M.disable()
    if not is_enabled then
        return
    end

    -- Stop timer
    if sync_timer then
        sync_timer:stop()
        sync_timer:close()
        sync_timer = nil
    end

    is_enabled = false
end

--- Toggle integration
function M.toggle()
    if is_enabled then
        M.disable()
    else
        M.enable()
    end
end

--- Status check
--- @return table Integration status information
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

--- Get current group's buffer information (for compatibility with init.lua)
--- @return table Buffer information
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

--- Get bufferline's sorted buffer list (public API)
--- @return number[] List of buffer IDs in bufferline's display order
function M.get_sorted_buffers()
    return get_bufferline_sorted_buffers()
end

--- Get buffer position information for dual numbering display
--- For current group: get fresh data from bufferline
--- For other groups: use saved data to maintain consistency
--- @param group_id string|nil Group ID to get position info for (nil = current active group)
--- @return table Buffer position mapping {buffer_id -> {local_pos = N or nil, global_pos = M}}
function M.get_buffer_position_info(group_id)
    -- Default to active group if no group_id specified
    if not group_id then
        local active_group = groups.get_active_group()
        group_id = active_group and active_group.id
    end
    
    if not group_id then
        return {}
    end
    
    local active_group = groups.get_active_group()
    local is_current_group = active_group and (group_id == active_group.id)
    
    if is_current_group then
        -- For current group: always get fresh position info from bufferline
        local position_info = get_real_position_info()
        
        -- Update group's position info
        groups.update_group_position_info(group_id, position_info)
        
        return position_info
    else
        -- For other groups: use saved position info to maintain consistency
        local saved_info = groups.get_group_position_info(group_id)
        -- If no saved info (e.g., newly loaded session), return empty table
        -- This will cause all local positions to be nil, showing as "-"
        return saved_info
    end
end

--- Force refresh (for compatibility with session.lua)
function M.force_refresh()
    vim.schedule(function()
        local bufferline_ui = require('bufferline.ui')
        if bufferline_ui.refresh then
            bufferline_ui.refresh()
        end

        -- Refresh our sidebar
        local vbl = require('vertical-bufferline')
        if vbl.state and vbl.state.is_sidebar_open and vbl.refresh then
            vbl.refresh("force_refresh")
        end
    end)
end

--- Safe buffer close function, avoiding E85 error
--- @param target_buf number Optional buffer ID to close
--- @return boolean success
function M.smart_close_buffer(target_buf)
    target_buf = target_buf or vim.api.nvim_get_current_buf()

    -- Check if there are unsaved modifications
    if vim.api.nvim_buf_get_option(target_buf, "modified") then
        local choice = vim.fn.confirm("Buffer has unsaved changes. Close anyway?", "&Yes\n&No", 2)
        if choice ~= 1 then
            return false
        end
    end

    -- Get all listed buffers
    local all_buffers = vim.api.nvim_list_bufs()
    local listed_buffers = {}
    for _, buf_id in ipairs(all_buffers) do
        if vim.api.nvim_buf_is_valid(buf_id) and vim.api.nvim_buf_get_option(buf_id, 'buflisted') then
            table.insert(listed_buffers, buf_id)
        end
    end

    -- If this is the last listed buffer, directly use empty group display
    if #listed_buffers <= 1 then
        -- First delete target buffer
        if vim.api.nvim_buf_is_valid(target_buf) then
            pcall(vim.api.nvim_buf_delete, target_buf, { force = true })
        end

        -- Directly handle empty group display (this will create [Empty Group] buffer and switch to it)
        M.handle_empty_group_display()
    else
        -- If there are other buffers, first switch to the next one
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

        -- Then delete target buffer
        if vim.api.nvim_buf_is_valid(target_buf) then
            pcall(vim.api.nvim_buf_delete, target_buf, { force = true })
        end
    end

    return true
end

-- Save global instance
_G._vertical_bufferline_integration_instance = M

return M
