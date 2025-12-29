-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/bufferline-integration.lua
-- Integration module with bufferline.nvim, simple bidirectional copy strategy

local M = {}

local groups = require('vertical-bufferline.groups')
local logger = require('vertical-bufferline.logger')
local utils = require('vertical-bufferline.utils')

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

local function is_bufferline_available()
    local ok_state, _ = pcall(require, 'bufferline.state')
    return ok_state
end

function M.is_available()
    return is_bufferline_available()
end


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

-- Use shared utility function
local function is_special_buffer(buf_id)
    return utils.is_special_buffer(buf_id)
end

-- Get bufferline's custom sort order for proper buffer ordering
local function get_bufferline_sorted_buffers()
    if not is_bufferline_available() then
        return {}
    end

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
    if not is_bufferline_available() then
        return {}
    end

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
    if not is_bufferline_available() then
        return
    end

    -- Auto-enable logging for sync debugging (disabled for normal use)
    -- if not logger.is_enabled() and not _G._vbl_auto_logging_enabled then
    --     logger.enable(vim.fn.expand("~/vbl-sync-debug.log"), "DEBUG")
    --     logger.info("sync", "auto-enabled debug logging for sync debugging")
    --     _G._vbl_auto_logging_enabled = true
    -- end
    
    if not is_enabled then
        return
    end

    local state_module = require('vertical-bufferline.state')
    if state_module.is_session_loading() then
        return
    end

    -- Check pointer: if nil, copy is invalid
    if not sync_target_group_id then
        return
    end

    -- Get all valid buffer list from bufferline with proper ordering
    local all_valid_buffers = get_bufferline_sorted_buffers()

    -- Also check what bufferline.get_elements() returns for comparison
    local bufferline_ok, bufferline = pcall(require, 'bufferline')
    local bufferline_buffer_ids = {}
    if bufferline_ok then
        local elements = bufferline.get_elements().elements
        for _, elem in ipairs(elements) do
            table.insert(bufferline_buffer_ids, elem.id)
        end
    end

    -- Filter out special buffers (based on buftype)
    local filtered_buffer_ids = {}
    for _, buf_id in ipairs(all_valid_buffers) do
        local should_include = not is_special_buffer(buf_id)

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

        -- Log the change detection details
        logger.log_sync_state("sync", "change_detection", 
            buffers_changed or names_changed or current_buffer_changed, {
            buffers_changed = buffers_changed,
            names_changed = names_changed,
            current_buffer_changed = current_buffer_changed,
            current_buf = current_buf,
            last_current_buffer = last_current_buffer,
            target_group_id = sync_target_group_id,
            filtered_buffer_count = #filtered_buffer_ids,
            target_group_buffer_count = #target_group.buffers
        })

        if buffers_changed or names_changed or current_buffer_changed then
            -- Update cached state
            last_buffer_state = current_buffer_state
            last_current_buffer = current_buf

            -- Update position info for active group when we're not in sidebar
            update_active_group_position_info()

            -- Merge with existing buffers instead of replacing completely
            local merged_buffers = {}
            local seen_buffers = {}

            -- First, add all buffers from bufferline (in proper order)
            for _, buf_id in ipairs(filtered_buffer_ids) do
                if vim.api.nvim_buf_is_valid(buf_id) then
                    table.insert(merged_buffers, buf_id)
                    seen_buffers[buf_id] = true
                end
            end

            -- Use only bufferline buffers for strict synchronization
            -- If user removes buffer from bufferline, it should also be removed from VBL

            -- Update buffers and automatically sync history
            groups.update_group_buffers(sync_target_group_id, merged_buffers)

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
                logger.info("sync", "triggering VBL refresh", {
                    reason = "bufferline_sync",
                    sidebar_open = vbl.state.is_sidebar_open,
                    current_buffer_in_group = current_buffer_in_group
                })
                vbl.refresh("bufferline_sync")
            else
                logger.warn("sync", "VBL refresh not available", {
                    vbl_exists = vbl ~= nil,
                    state_exists = vbl and vbl.state ~= nil,
                    sidebar_open = vbl and vbl.state and vbl.state.is_sidebar_open,
                    refresh_exists = vbl and vbl.refresh ~= nil
                })
            end
        end
    end
end


--- Direction 2: group → bufferline (when switching groups, 1% of the time)
--- @param buffer_list table List of buffer IDs to show in bufferline
function M.set_bufferline_buffers(buffer_list)
    if not is_enabled or not is_bufferline_available() then
        return
    end

    -- Control bufferline's buffer visibility to match target group
    -- Get all buffers for visibility control
    local all_buffers = vim.api.nvim_list_bufs()

    -- Create buffer set for fast lookup
    local target_buffer_set = {}
    for _, buf_id in ipairs(buffer_list) do
        target_buffer_set[buf_id] = true
    end

    -- Update buffer visibility based on target list
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
    local ok_ui, bufferline_ui = pcall(require, 'bufferline.ui')
    if ok_ui and bufferline_ui.refresh then
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

            -- VBL should not hide unnamed buffers - users might be editing them
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
    if is_bufferline_available() then
        local ok_ui, bufferline_ui = pcall(require, 'bufferline.ui')
        if ok_ui and bufferline_ui.refresh then
            bufferline_ui.refresh()
        end
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
    if not is_bufferline_available() then
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
    local bufferline_available = is_bufferline_available()
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
    
    if is_current_group and is_bufferline_available() then
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
        if is_bufferline_available() then
            local ok_ui, bufferline_ui = pcall(require, 'bufferline.ui')
            if ok_ui and bufferline_ui.refresh then
                bufferline_ui.refresh()
            end
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

    -- CRITICAL: Pause sync timer to prevent race conditions
    -- The sync timer might unlist buffers while we're in the middle of closing
    local saved_sync_target = sync_target_group_id
    M.set_sync_target(nil)

    -- Get all listed buffers
    local all_buffers = vim.api.nvim_list_bufs()
    local listed_buffers = {}
    for _, buf_id in ipairs(all_buffers) do
        if vim.api.nvim_buf_is_valid(buf_id) and vim.api.nvim_buf_get_option(buf_id, 'buflisted') then
            table.insert(listed_buffers, buf_id)
        end
    end

    -- Log buffer state for debugging
    logger.info("smart_close", "closing buffer", {
        target_buf = target_buf,
        target_buf_name = vim.api.nvim_buf_get_name(target_buf),
        total_listed = #listed_buffers,
        total_all_buffers = #all_buffers
    })

    -- CRITICAL: Check if there are other buffers in the CURRENT GROUP
    -- Don't just check global listed_buffers count, as some group buffers
    -- might be temporarily unlisted by set_bufferline_buffers()
    local groups = require('vertical-bufferline.groups')
    local current_group = groups.get_active_group()
    local group_has_other_buffers = false
    local next_buf_in_group = nil

    if current_group then
        -- Check if group has other valid buffers besides target_buf
        for _, buf_id in ipairs(current_group.buffers) do
            if buf_id ~= target_buf and vim.api.nvim_buf_is_valid(buf_id) then
                group_has_other_buffers = true
                -- Find first valid buffer to switch to
                if not next_buf_in_group then
                    next_buf_in_group = buf_id
                end
            end
        end

        logger.info("smart_close", "group buffer check", {
            group_id = current_group.id,
            group_name = current_group.name,
            group_buffer_count = #current_group.buffers,
            group_has_other_buffers = group_has_other_buffers,
            next_buf_in_group = next_buf_in_group
        })
    end

    -- Check if target buffer is currently displayed
    local current_buf = vim.api.nvim_get_current_buf()
    local is_target_current = (target_buf == current_buf)

    logger.info("smart_close", "buffer context", {
        target_buf = target_buf,
        current_buf = current_buf,
        is_target_current = is_target_current
    })

    -- Only need to switch buffers if we're closing the current buffer
    if is_target_current then
        -- CRITICAL FIX: Find a fallback buffer to switch to before deleting
        local fallback_buf = nil

        if group_has_other_buffers and next_buf_in_group then
            -- Group still has other buffers - switch to one of them
            fallback_buf = next_buf_in_group
            -- Ensure it's listed (it might have been unlisted by sync)
            pcall(vim.api.nvim_buf_set_option, fallback_buf, 'buflisted', true)
            logger.info("smart_close", "using group buffer as fallback", {
                fallback_buf = fallback_buf,
                fallback_name = vim.api.nvim_buf_get_name(fallback_buf)
            })
        elseif #listed_buffers > 1 then
            -- Find another listed buffer
            for _, buf_id in ipairs(listed_buffers) do
                if buf_id ~= target_buf then
                    fallback_buf = buf_id
                    logger.info("smart_close", "using listed buffer as fallback", {
                        fallback_buf = fallback_buf,
                        fallback_name = vim.api.nvim_buf_get_name(fallback_buf)
                    })
                    break
                end
            end
        end

        -- If we found a fallback buffer, switch to it
        if fallback_buf and vim.api.nvim_buf_is_valid(fallback_buf) then
            pcall(vim.api.nvim_set_current_buf, fallback_buf)
            logger.info("smart_close", "switched to fallback", {
                current_buf = vim.api.nvim_get_current_buf(),
                target_buf = target_buf,
                fallback_buf = fallback_buf
            })
        else
            -- No fallback found - create a NEW LISTED buffer to prevent exit
            -- DON'T use handle_empty_group_display() as it creates unlisted buffer
            logger.warn("smart_close", "no fallback found, creating new listed buffer", {})
            vim.cmd("enew")
            local new_buf = vim.api.nvim_get_current_buf()
            -- Explicitly ensure it's listed
            vim.api.nvim_buf_set_option(new_buf, 'buflisted', true)
            logger.info("smart_close", "created emergency buffer", {
                new_buf = new_buf,
                is_listed = vim.api.nvim_buf_get_option(new_buf, 'buflisted')
            })
        end
    else
        -- Not closing the current buffer, no need to switch
        logger.info("smart_close", "target is not current buffer, no switch needed")
    end

    -- Now safe to delete target buffer
    if vim.api.nvim_buf_is_valid(target_buf) then
        logger.info("smart_close", "deleting target buffer", { target_buf = target_buf })

        -- Only set alternate buffer if we closed the current buffer
        -- Otherwise, preserve the existing alternate buffer relationship
        if is_target_current then
            -- Find a suitable alternate buffer from group history or other group buffers
            -- This ensures Ctrl-^ switches to a valid buffer instead of unnamed/deleted buffer
            local alternate_buf = nil
            local current_buf_after_switch = vim.api.nvim_get_current_buf()

            if current_group and current_group.history then
                -- Look for the most recent buffer in history that isn't the target or current
                for i = #current_group.history, 1, -1 do
                    local hist_buf = current_group.history[i]
                    if hist_buf ~= target_buf and hist_buf ~= current_buf_after_switch and
                       vim.api.nvim_buf_is_valid(hist_buf) and
                       vim.tbl_contains(current_group.buffers, hist_buf) then
                        alternate_buf = hist_buf
                        break
                    end
                end
            end

            -- If we didn't find an alternate from history, use any other buffer in group
            if not alternate_buf and current_group then
                for _, buf_id in ipairs(current_group.buffers) do
                    if buf_id ~= target_buf and buf_id ~= current_buf_after_switch and
                       vim.api.nvim_buf_is_valid(buf_id) then
                        alternate_buf = buf_id
                        break
                    end
                end
            end

            -- Set alternate buffer by briefly switching to it then back
            -- This is the standard Vim way to set the alternate buffer
            if alternate_buf and vim.api.nvim_buf_is_valid(alternate_buf) then
                vim.cmd(string.format("silent! buffer %d", alternate_buf))
                vim.cmd(string.format("silent! buffer %d", current_buf_after_switch))
                logger.info("smart_close", "set alternate buffer", {
                    alternate_buf = alternate_buf,
                    alternate_name = vim.api.nvim_buf_get_name(alternate_buf)
                })
            end
        end

        -- Now delete the target buffer
        pcall(vim.api.nvim_buf_delete, target_buf, { force = true })
    end

    -- Restore sync timer immediately to prevent sync gaps
    -- Buffer operations above are all synchronous, so safe to restore now
    M.set_sync_target(saved_sync_target)

    return true
end

-- Get status for debugging
function M.get_status()
    return {
        enabled = is_enabled,
        has_timer = sync_timer ~= nil,
        timer_active = sync_timer and sync_timer:is_active() or false,
        target_group_id = sync_target_group_id
    }
end

-- Manual sync trigger for debugging
function M.sync_once()
    sync_bufferline_to_group()
end

-- Save global instance
_G._vertical_bufferline_integration_instance = M

return M
