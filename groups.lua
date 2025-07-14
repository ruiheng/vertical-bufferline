-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/groups.lua
-- Dynamic group management module

-- Anti-reload protection
if _G._vertical_bufferline_groups_loaded then
    return _G._vertical_bufferline_groups_instance
end

local config_module = require('vertical-bufferline.config')

local M = {}

local api = vim.api

-- Group data structure
local groups_data = {
    -- All group definitions
    groups = {
        -- Example:
        -- {
        --     id = "group1",
        --     name = "Main",
        --     buffers = {12, 15, 18}, -- buffer IDs
        --     created_at = os.time(),
        --     color = "#e06c75" -- Optional color identifier
        -- }
    },

    -- Current active group ID
    active_group_id = nil,

    -- Previous active group ID (for switching back)
    previous_group_id = nil,

    -- Default group ID (fallback group for all buffers)
    default_group_id = "default",

    -- Counter for next group ID
    next_group_id = config_module.SYSTEM.FIRST_INDEX,
    
    -- Counter for stable display numbers (never decreases)
    next_display_number = config_module.SYSTEM.FIRST_INDEX,

    -- Group settings
    settings = {
        auto_create_groups = config_module.DEFAULTS.auto_create_groups,
        auto_add_new_buffers = config_module.DEFAULTS.auto_add_new_buffers,
        group_name_prefix = "Group",
    },

    -- Flag to temporarily disable auto-adding
    auto_add_disabled = false,
    
    -- Flag to temporarily disable history sync (when clicking history items)
    history_sync_disabled = false,
}

-- Initialize default group
local function init_default_group()
    if #groups_data.groups == 0 then
        local default_group = {
            id = groups_data.default_group_id,
            name = "Default",
            buffers = {},
            current_buffer = nil,  -- Track current buffer within this group
            created_at = os.time(),
            color = config_module.COLORS.BLUE,
            display_number = groups_data.next_display_number,
            buffer_states = {},  -- Store per-buffer window states (cursor, scroll, etc.)
            position_info = {},   -- Store bufferline position info {buffer_id -> local_pos}
            history = {}  -- Store recent file access history
        }
        groups_data.next_display_number = groups_data.next_display_number + 1
        table.insert(groups_data.groups, default_group)
        groups_data.active_group_id = groups_data.default_group_id

        -- Don't auto-add buffers during initialization, left to caller
    end
end

-- Find group
local function find_group_by_id(group_id)
    for _, group in ipairs(groups_data.groups) do
        if group.id == group_id then
            return group
        end
    end
    return nil
end

-- Find group by display number
local function find_group_by_display_number(display_number)
    for _, group in ipairs(groups_data.groups) do
        if group.display_number == display_number then
            return group
        end
    end
    return nil
end

-- Buffer state management utilities (defined early to be available everywhere)
local function save_buffer_state(group, buffer_id)
    if not group or not buffer_id or not api.nvim_buf_is_valid(buffer_id) then
        return
    end
    
    -- Only save state if the buffer is currently displayed in a window
    local buf_windows = vim.fn.win_findbuf(buffer_id)
    if #buf_windows == 0 then
        return  -- Buffer not currently displayed, nothing to save
    end
    
    -- Get current window showing this buffer
    local current_win = api.nvim_get_current_win()
    local target_win = current_win
    
    -- If current window doesn't show this buffer, find one that does
    if api.nvim_win_get_buf(current_win) ~= buffer_id then
        for _, win_id in ipairs(buf_windows) do
            if api.nvim_win_is_valid(win_id) then
                target_win = win_id
                break
            end
        end
    end
    
    -- Save comprehensive window state
    local saved_win = api.nvim_get_current_win()
    api.nvim_set_current_win(target_win)
    
    local state = {
        cursor_pos = api.nvim_win_get_cursor(target_win),
        view_state = vim.fn.winsaveview(),
        last_accessed = os.time()
    }
    
    group.buffer_states[buffer_id] = state
    api.nvim_set_current_win(saved_win)
end

local function restore_buffer_state(group, buffer_id)
    if not group or not buffer_id or not api.nvim_buf_is_valid(buffer_id) then
        return false
    end
    
    local state = group.buffer_states[buffer_id]
    if not state then
        return false  -- No saved state for this buffer
    end
    
    -- Only restore if buffer is currently displayed
    local buf_windows = vim.fn.win_findbuf(buffer_id)
    if #buf_windows == 0 then
        return false  -- Buffer not displayed, can't restore
    end
    
    -- Find appropriate window to restore state to
    local current_win = api.nvim_get_current_win()
    local target_win = current_win
    
    if api.nvim_win_get_buf(current_win) ~= buffer_id then
        for _, win_id in ipairs(buf_windows) do
            if api.nvim_win_is_valid(win_id) then
                target_win = win_id
                break
            end
        end
    end
    
    -- Restore state
    local saved_win = api.nvim_get_current_win()
    api.nvim_set_current_win(target_win)
    
    -- Restore cursor position (fallback method)
    pcall(api.nvim_win_set_cursor, target_win, state.cursor_pos)
    
    -- Restore comprehensive view state (primary method)
    pcall(vim.fn.winrestview, state.view_state)
    
    api.nvim_set_current_win(saved_win)
    return true
end

local function cleanup_buffer_states(group, max_age_seconds)
    if not group or not group.buffer_states then
        return
    end
    
    max_age_seconds = max_age_seconds or (30 * 60)  -- Default 30 minutes
    local current_time = os.time()
    
    for buffer_id, state in pairs(group.buffer_states) do
        -- Remove states for invalid buffers or old states
        if not api.nvim_buf_is_valid(buffer_id) or 
           (state.last_accessed and (current_time - state.last_accessed) > max_age_seconds) then
            group.buffer_states[buffer_id] = nil
        end
    end
end

-- Find group index
local function find_group_index_by_id(group_id)
    for i, group in ipairs(groups_data.groups) do
        if group.id == group_id then
            return i
        end
    end
    return nil
end

-- Generate new group ID
local function generate_group_id()
    local id = "group_" .. groups_data.next_group_id
    groups_data.next_group_id = groups_data.next_group_id + 1
    return id
end


--- Create new group
--- @param name string Optional group name
--- @param color string Optional color identifier
--- @return string group_id
function M.create_group(name, color)
    local group_id = generate_group_id()
    local group_name = name or ""  -- Allow empty name

    local new_group = {
        id = group_id,
        name = group_name,
        buffers = {},
        current_buffer = nil,  -- Track current buffer within this group
        created_at = os.time(),
        color = color or config_module.COLORS.GREEN,
        display_number = groups_data.next_display_number,
        buffer_states = {},  -- Store per-buffer window states (cursor, scroll, etc.)
        position_info = {},  -- Store bufferline position info {buffer_id -> local_pos}
        history = {},        -- Store recent file access history {buffer_id, ...} (newest first, excludes current)
        last_current_buffer = nil  -- Track previous current buffer for history updates
    }
    groups_data.next_display_number = groups_data.next_display_number + 1

    table.insert(groups_data.groups, new_group)

    -- Trigger event
    vim.api.nvim_exec_autocmds("User", {
        pattern = config_module.EVENTS.GROUP_CREATED,
        data = { group = new_group }
    })

    return group_id
end

--- Delete group
--- @param group_id string ID of group to delete
--- @return boolean success
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

    -- Only preserve unsaved (modified) buffers by moving them to default group
    local default_group = find_group_by_id(groups_data.default_group_id)
    if default_group then
        for _, buffer_id in ipairs(group.buffers) do
            -- Check if buffer is modified (has unsaved changes)
            local is_modified = false
            if api.nvim_buf_is_valid(buffer_id) then
                is_modified = api.nvim_buf_get_option(buffer_id, "modified")
            end
            
            if is_modified then
                -- Check if this unsaved buffer exists in any other group
                local exists_in_other_groups = false
                for _, other_group in ipairs(groups_data.groups) do
                    if other_group.id ~= group_id and vim.tbl_contains(other_group.buffers, buffer_id) then
                        exists_in_other_groups = true
                        break
                    end
                end
                
                -- Only move to default group if it doesn't exist in other groups
                if not exists_in_other_groups and not vim.tbl_contains(default_group.buffers, buffer_id) then
                    table.insert(default_group.buffers, buffer_id)
                end
            end
            -- Saved buffers are simply discarded (not moved anywhere)
        end
    end

    -- Delete group
    table.remove(groups_data.groups, group_index)

    -- If deleting current active group, switch to default group
    if groups_data.active_group_id == group_id then
        groups_data.active_group_id = groups_data.default_group_id
    end

    -- Trigger event
    vim.api.nvim_exec_autocmds("User", {
        pattern = config_module.EVENTS.GROUP_DELETED,
        data = { group_id = group_id }
    })

    return true
end

--- Rename group
--- @param group_id string ID of group to rename
--- @param new_name string New name for the group
--- @return boolean success
function M.rename_group(group_id, new_name)
    local group = find_group_by_id(group_id)
    if not group then
        vim.notify("Group not found: " .. group_id, vim.log.levels.ERROR)
        return false
    end

    local old_name = group.name
    group.name = new_name

    -- Trigger event
    vim.api.nvim_exec_autocmds("User", {
        pattern = config_module.EVENTS.GROUP_RENAMED,
        data = { group_id = group_id, old_name = old_name, new_name = new_name }
    })

    return true
end

--- Get all groups
--- @return table List of all groups
function M.get_all_groups()
    return vim.deepcopy(groups_data.groups)
end

--- Get current active group
--- @return table|nil Active group or nil if none
function M.get_active_group()
    return find_group_by_id(groups_data.active_group_id)
end

-- Get current active group ID
function M.get_active_group_id()
    return groups_data.active_group_id
end

--- Set active group
--- @param group_id string ID of group to activate
--- @return boolean success
function M.set_active_group(group_id)
    local group = find_group_by_id(group_id)
    if not group then
        vim.notify("Group not found: " .. group_id, vim.log.levels.ERROR)
        return false
    end

    if group_id == groups_data.active_group_id then
        return false
    end

    local old_group_id = groups_data.active_group_id
    
    -- Store previous group ID for switching back
    if old_group_id then
        groups_data.previous_group_id = old_group_id
    end
    
    -- Save current buffer state for the old group before switching
    local old_group = M.get_active_group()
    if old_group then
        local current_buf = vim.api.nvim_get_current_buf()
        if vim.tbl_contains(old_group.buffers, current_buf) then
            old_group.current_buffer = current_buf
            -- Save comprehensive window state for current buffer
            save_buffer_state(old_group, current_buf)
        end
        
        -- Save current group's position info before switching (only local positions)
        local ok, position_info = pcall(function()
            -- Get fresh position info from bufferline for the current group
            local state = require('bufferline.state')
            local visible_buffers = state.visible_components or {}
            
            local info = {}
            
            -- Build visible buffer ID to local position mapping
            for local_idx, component in ipairs(visible_buffers) do
                if component and component.id then
                    info[component.id] = local_idx
                end
            end
            
            return info
        end)
        if ok and position_info then
            old_group.position_info = position_info
        end
    end

    -- disable copying bufferline buffer list to group
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    bufferline_integration.set_sync_target(nil)

    -- Reverse control: set new group's buffer list to bufferline
    bufferline_integration.set_bufferline_buffers(group.buffers)

    -- Switch to group's remembered current buffer or fallback intelligently
    if #group.buffers > 0 then
        local target_buffer = nil
        
        -- First priority: use group's remembered current buffer if valid
        if group.current_buffer and vim.api.nvim_buf_is_valid(group.current_buffer) 
           and vim.tbl_contains(group.buffers, group.current_buffer) then
            target_buffer = group.current_buffer
        else
            -- Second priority: keep current buffer if it's in the group
            local current_buf = vim.api.nvim_get_current_buf()
            if vim.api.nvim_buf_is_valid(current_buf) and vim.tbl_contains(group.buffers, current_buf) then
                target_buffer = current_buf
            else
                -- Fallback: use first valid buffer in group
                for _, buf_id in ipairs(group.buffers) do
                    if vim.api.nvim_buf_is_valid(buf_id) then
                        target_buffer = buf_id
                        break
                    end
                end
            end
        end
        
        -- Switch to the determined buffer
        if target_buffer then
            vim.api.nvim_set_current_buf(target_buffer)
            -- Update group's current buffer record
            group.current_buffer = target_buffer
            
            -- Restore saved window state for this buffer in this group
            vim.schedule(function()
                restore_buffer_state(group, target_buffer)
            end)
        end
    end
    -- If group is empty, keep current buffer unchanged, let bufferline show empty list

    -- Restore sync pointer to new group (step 3 of atomic operation)
    -- First update active group ID
    groups_data.active_group_id = group_id

    -- Sync pointer to new group
    bufferline_integration.set_sync_target(group_id)

    -- Initialize position info for the new active group after bufferline sync
    vim.schedule(function()
        -- Force refresh bufferline first
        local bufferline_ui = require('bufferline.ui')
        if bufferline_ui.refresh then
            bufferline_ui.refresh()
        end
        
        -- Then update position info for new active group
        vim.defer_fn(function()
            local position_info = bufferline_integration.get_buffer_position_info(group_id)
            M.update_group_position_info(group_id, position_info)
        end, 50)  -- Small delay to ensure bufferline is updated
    end)

    -- Note: Additional refresh will be triggered by the GROUP_CHANGED autocmd

    -- Trigger event
    vim.api.nvim_exec_autocmds("User", {
        pattern = config_module.EVENTS.GROUP_CHANGED,
        data = { old_group_id = old_group_id, new_group_id = group_id }
    })

    return true
end

--- Add buffer to group
--- @param buffer_id number Buffer ID to add
--- @param group_id string Group ID to add buffer to
--- @return boolean success
function M.add_buffer_to_group(buffer_id, group_id)
    if not api.nvim_buf_is_valid(buffer_id) then
        return false
    end

    local group = find_group_by_id(group_id)
    if not group then
        vim.notify("Group not found: " .. group_id, vim.log.levels.ERROR)
        return false
    end

    -- Check if already in group
    if vim.tbl_contains(group.buffers, buffer_id) then
        return true
    end

    -- Allow buffer to exist in multiple groups (commented out original restriction)
    -- M.remove_buffer_from_all_groups(buffer_id)

    -- Add to specified group in correct order based on bufferline's sorting
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    local sorted_buffers = bufferline_integration.get_sorted_buffers()
    
    -- Find the correct position to insert the buffer
    local insert_position = #group.buffers + 1
    
    -- Get buffer's position in bufferline's sorted order
    local buffer_position_in_sorted = nil
    for i, buf_id in ipairs(sorted_buffers) do
        if buf_id == buffer_id then
            buffer_position_in_sorted = i
            break
        end
    end
    
    if buffer_position_in_sorted then
        -- Find the correct insertion point by comparing with existing buffers
        for i, existing_buf_id in ipairs(group.buffers) do
            local existing_position_in_sorted = nil
            for j, buf_id in ipairs(sorted_buffers) do
                if buf_id == existing_buf_id then
                    existing_position_in_sorted = j
                    break
                end
            end
            
            -- If we found the position and the new buffer should come before this one
            if existing_position_in_sorted and buffer_position_in_sorted < existing_position_in_sorted then
                insert_position = i
                break
            end
        end
    end
    
    -- Insert at the calculated position
    table.insert(group.buffers, insert_position, buffer_id)

    -- Trigger event
    vim.api.nvim_exec_autocmds("User", {
        pattern = config_module.EVENTS.BUFFER_ADDED_TO_GROUP,
        data = { buffer_id = buffer_id, group_id = group_id }
    })

    return true
end

--- Remove buffer from group
--- @param buffer_id number Buffer ID to remove
--- @param group_id string Group ID to remove buffer from
--- @return boolean success
function M.remove_buffer_from_group(buffer_id, group_id)
    local group = find_group_by_id(group_id)
    if not group then
        return false
    end

    for i, buf_id in ipairs(group.buffers) do
        if buf_id == buffer_id then
            table.remove(group.buffers, i)

            -- Trigger event
            vim.api.nvim_exec_autocmds("User", {
                pattern = config_module.EVENTS.BUFFER_REMOVED_FROM_GROUP,
                data = { buffer_id = buffer_id, group_id = group_id }
            })

            return true
        end
    end

    return false
end

-- Remove buffer from all groups
function M.remove_buffer_from_all_groups(buffer_id)
    for _, group in ipairs(groups_data.groups) do
        M.remove_buffer_from_group(buffer_id, group.id)
    end
end

-- Find group that buffer belongs to (returns first found group)
function M.find_buffer_group(buffer_id)
    for _, group in ipairs(groups_data.groups) do
        if vim.tbl_contains(group.buffers, buffer_id) then
            return group
        end
    end
    return nil
end

-- Find all groups that buffer belongs to
function M.find_buffer_groups(buffer_id)
    local found_groups = {}
    for _, group in ipairs(groups_data.groups) do
        if vim.tbl_contains(group.buffers, buffer_id) then
            table.insert(found_groups, group)
        end
    end
    return found_groups
end

-- Get all buffers from specified group
function M.get_group_buffers(group_id)
    local group = find_group_by_id(group_id)
    if not group then
        return {}
    end

    -- Only filter invalid buffers, don't modify original list
    local valid_buffers = {}
    local found_invalid = false
    for _, buffer_id in ipairs(group.buffers) do
        if api.nvim_buf_is_valid(buffer_id) then
            table.insert(valid_buffers, buffer_id)
        else
            found_invalid = true
        end
    end

    -- Only update group's buffer list when invalid buffers are found
    if found_invalid then
        group.buffers = valid_buffers
    end

    return group.buffers
end

-- Get all buffers from current group
function M.get_active_group_buffers()
    local active_group = M.get_active_group()
    if not active_group then
        return {}
    end

    return M.get_group_buffers(active_group.id)
end

--- Switch to previous group
--- @return boolean success
function M.switch_to_previous_group()
    local current_group_id = groups_data.active_group_id
    local previous_group_id = groups_data.previous_group_id
    
    -- If no previous group, cannot switch
    if not previous_group_id then
        vim.notify("No previous group to switch to", vim.log.levels.WARN)
        return false
    end
    
    -- If previous group is invalid, cannot switch
    if not find_group_by_id(previous_group_id) then
        vim.notify("Previous group no longer exists", vim.log.levels.WARN)
        groups_data.previous_group_id = nil
        return false
    end
    
    -- If previous group is the same as current (edge case), cannot switch
    if previous_group_id == current_group_id then
        vim.notify("Previous group is the same as current group", vim.log.levels.WARN)
        return false
    end
    
    -- Switch to previous group
    return M.set_active_group(previous_group_id)
end

-- Move group up
function M.move_group_up(group_id)
    local group_index = find_group_index_by_id(group_id)
    if not group_index or group_index == config_module.SYSTEM.FIRST_INDEX then
        return false -- Already first group or group doesn't exist
    end

    -- Swap current group with previous group
    local temp = groups_data.groups[group_index]
    groups_data.groups[group_index] = groups_data.groups[group_index - 1]
    groups_data.groups[group_index - 1] = temp

    -- Trigger event
    vim.api.nvim_exec_autocmds("User", {
        pattern = config_module.EVENTS.GROUP_REORDERED,
        data = { group_id = group_id, direction = "up", from_index = group_index, to_index = group_index - 1 }
    })

    return true
end

-- Move group down
function M.move_group_down(group_id)
    local group_index = find_group_index_by_id(group_id)
    if not group_index or group_index == #groups_data.groups then
        return false -- Already last group or group doesn't exist
    end

    -- Swap current group with next group
    local temp = groups_data.groups[group_index]
    groups_data.groups[group_index] = groups_data.groups[group_index + 1]
    groups_data.groups[group_index + 1] = temp

    -- Trigger event
    vim.api.nvim_exec_autocmds("User", {
        pattern = config_module.EVENTS.GROUP_REORDERED,
        data = { group_id = group_id, direction = "down", from_index = group_index, to_index = group_index + 1 }
    })

    return true
end

-- Move group to specified position
function M.move_group_to_position(group_id, target_position)
    local group_index = find_group_index_by_id(group_id)
    if not group_index then
        return false -- Group doesn't exist
    end

    -- Validate target position
    if target_position < config_module.SYSTEM.FIRST_INDEX or target_position > #groups_data.groups then
        return false -- Invalid target position
    end

    if group_index == target_position then
        return true -- Already at target position
    end

    -- Remove group
    local group = table.remove(groups_data.groups, group_index)

    -- Insert at target position
    table.insert(groups_data.groups, target_position, group)

    -- Trigger event
    vim.api.nvim_exec_autocmds("User", {
        pattern = config_module.EVENTS.GROUP_REORDERED,
        data = { group_id = group_id, direction = "position", from_index = group_index, to_index = target_position }
    })

    return true
end

-- Enforce single group policy: ensure buffer belongs to only one group
function M.enforce_single_group_policy(buffer_id, target_group_id)
    -- First remove from all groups
    M.remove_buffer_from_all_groups(buffer_id)
    -- Then only add to target group
    return M.add_buffer_to_group(buffer_id, target_group_id)
end

-- Temporarily disable/enable auto-adding
function M.set_auto_add_disabled(disabled)
    groups_data.auto_add_disabled = disabled
end

function M.is_auto_add_disabled()
    return groups_data.auto_add_disabled
end

-- History sync control
function M.set_history_sync_disabled(disabled)
    groups_data.history_sync_disabled = disabled
end

function M.is_history_sync_disabled()
    return groups_data.history_sync_disabled
end


-- Sync update current group's buffer list through bufferline
function M.sync_active_group_with_bufferline(buffer_list)
    local active_group_id = M.get_active_group_id()
    if not active_group_id then
        return
    end

    local active_group = find_group_by_id(active_group_id)
    if not active_group then
        return
    end

    -- Directly update current active group's buffer list to bufferline result
    active_group.buffers = buffer_list or {}

    vim.schedule(function()
        if require('vertical-bufferline').refresh then
            require('vertical-bufferline').refresh("group_buffers_update")
        end
    end)

    -- Trigger event to notify group content updated
    vim.api.nvim_exec_autocmds("User", {
        pattern = config_module.EVENTS.GROUP_BUFFERS_UPDATED,
        data = { group_id = active_group_id, buffers = active_group.buffers }
    })
end

-- Clean up invalid buffers
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

-- Get group statistics
function M.get_group_stats()
    return {
        total_groups = #groups_data.groups,
        active_group_id = groups_data.active_group_id,
        total_buffers = vim.tbl_count(vim.api.nvim_list_bufs()),
        managed_buffers = vim.tbl_count(vim.iter(groups_data.groups):map(function(group) return group.buffers end):flatten():totable())
    }
end

--- Update position info for a specific group
--- @param group_id string Group ID to update
--- @param position_info table Buffer position mapping {buffer_id -> local_pos (number or nil)}
function M.update_group_position_info(group_id, position_info)
    local group = find_group_by_id(group_id)
    if group then
        group.position_info = position_info or {}
    end
end

--- Get position info for a specific group
--- @param group_id string Group ID to get position info for
--- @return table Buffer position mapping {buffer_id -> local_pos (number or nil)}
function M.get_group_position_info(group_id)
    local group = find_group_by_id(group_id)
    if group then
        return group.position_info or {}
    end
    return {}
end

--- Initialize module
--- @param opts table Configuration options
function M.setup(opts)
    opts = opts or {}

    -- Merge settings
    groups_data.settings = vim.tbl_deep_extend("force", groups_data.settings, opts)

    -- Initialize default group
    init_default_group()

    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    bufferline_integration.set_sync_target(groups_data.active_group_id)

    -- Force refresh to ensure initial state displays correctly
    vim.schedule(function()
        -- Trigger UI update event
        vim.api.nvim_exec_autocmds("User", {
            pattern = config_module.EVENTS.GROUP_CHANGED,
            data = { new_group_id = groups_data.active_group_id }
        })
    end)

    -- No longer need BufEnter autocmd for buffer management, changed to sync through bufferline
    -- Cleanup invalid buffer autocmd also no longer needed, handled by bufferline state sync

    -- Periodically clean up invalid buffers and buffer states
    vim.defer_fn(function()
        M.cleanup_invalid_buffers()
        -- Clean up old buffer states from all groups
        for _, group in ipairs(groups_data.groups) do
            cleanup_buffer_states(group)
        end
    end, config_module.UI.AUTO_SAVE_DELAY)
end

--- Switch to group by display number (for quick switch shortcuts)
--- @param display_number number Display number shown in UI (1, 2, 3, etc.)
--- @return boolean success
function M.switch_to_group_by_display_number(display_number)
    local group = find_group_by_display_number(display_number)
    if not group then
        return false
    end
    return M.set_active_group(group.id)
end

--- Save current buffer state for active group (call before switching buffers within group)
function M.save_current_buffer_state()
    local active_group = M.get_active_group()
    if not active_group then
        return false
    end
    
    local current_buf = api.nvim_get_current_buf()
    if vim.tbl_contains(active_group.buffers, current_buf) then
        save_buffer_state(active_group, current_buf)
        return true
    end
    return false
end

--- Restore buffer state for specified buffer in active group (call after switching to buffer)
--- @param buffer_id number Buffer ID to restore state for
function M.restore_buffer_state_for_current_group(buffer_id)
    local active_group = M.get_active_group()
    if not active_group then
        return false
    end
    
    if vim.tbl_contains(active_group.buffers, buffer_id) then
        return restore_buffer_state(active_group, buffer_id)
    end
    return false
end


--- Sync group history with current buffer (called during bufferline sync)
--- @param group_id string Group ID to sync history for
--- @param current_buffer_id number|nil Current buffer ID in this group (nil if no current buffer)
function M.sync_group_history_with_current(group_id, current_buffer_id)
    local group = find_group_by_id(group_id)
    if not group then
        return
    end
    
    -- Skip history sync if temporarily disabled (e.g., when clicking history items)
    if groups_data.history_sync_disabled then
        return
    end
    
    -- Helper function to check if buffer is a normal file (not special buffer)
    local function is_normal_file_buffer(buf_id)
        if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
            return false
        end
        
        local buftype = vim.api.nvim_buf_get_option(buf_id, 'buftype')
        -- Only normal files (empty buftype) should be in history
        return buftype == ''
    end
    
    -- UNIFIED FILTER: Skip if current_buffer_id is a non-normal file buffer (but allow nil)
    if current_buffer_id and not is_normal_file_buffer(current_buffer_id) then
        return
    end
    
    -- Initialize fields if not exists (for groups created before history feature or during session loading)
    if not group.history then
        group.history = {}
    end
    if group.last_current_buffer == nil then
        group.last_current_buffer = nil
    end
    
    local old_current = group.last_current_buffer
    local new_current = current_buffer_id
    
    -- Remove new current buffer from history (current buffer should not be in history)
    if new_current then
        for i, hist_buf_id in ipairs(group.history) do
            if hist_buf_id == new_current then
                table.remove(group.history, i)
                break
            end
        end
    end
    
    -- If current buffer changed and old current is valid AND is a normal file, add old current to history front
    if new_current ~= old_current and old_current and 
       vim.api.nvim_buf_is_valid(old_current) and 
       vim.tbl_contains(group.buffers, old_current) and
       is_normal_file_buffer(old_current) then
        
        -- Remove old current from history if it exists
        for i, hist_buf_id in ipairs(group.history) do
            if hist_buf_id == old_current then
                table.remove(group.history, i)
                break
            end
        end
        
        -- Add old current to front of history
        table.insert(group.history, 1, old_current)
        
        -- Limit history size
        local max_size = config_module.DEFAULTS.history_size
        while #group.history > max_size do
            table.remove(group.history)
        end
    end
    
    -- Update last current buffer tracker
    group.last_current_buffer = new_current
end

--- Get history for a group
--- @param group_id string Group ID to get history for
--- @return table Array of buffer IDs in access order (newest first)
function M.get_group_history(group_id)
    local group = find_group_by_id(group_id)
    if not group then
        return {}
    end
    
    -- Initialize history if not exists
    if not group.history then
        group.history = {}
        return {}
    end
    
    -- Filter out invalid buffers from history
    local valid_history = {}
    for _, buffer_id in ipairs(group.history) do
        if vim.api.nvim_buf_is_valid(buffer_id) and vim.tbl_contains(group.buffers, buffer_id) then
            table.insert(valid_history, buffer_id)
        end
    end
    
    -- Update group history with filtered list
    group.history = valid_history
    
    return valid_history
end

--- Remove buffer from history of all groups
--- @param buffer_id number Buffer ID to remove
function M.remove_buffer_from_history(buffer_id)
    for _, group in ipairs(groups_data.groups) do
        -- Initialize history if not exists
        if not group.history then
            group.history = {}
        else
            for i, hist_buf_id in ipairs(group.history) do
                if hist_buf_id == buffer_id then
                    table.remove(group.history, i)
                    break
                end
            end
        end
    end
end

--- Check if history should be shown for a group based on configuration
--- @param group_id string Group ID to check
--- @return boolean Whether to show history for this group
function M.should_show_history(group_id)
    local show_history = config_module.DEFAULTS.show_history
    
    if show_history == "no" then
        return false
    elseif show_history == "yes" then
        return true
    else -- "auto"
        local history = M.get_group_history(group_id)
        return #history >= config_module.DEFAULTS.history_auto_threshold
    end
end

M.find_group_by_id = find_group_by_id

-- Save global instance and set flag
_G._vertical_bufferline_groups_loaded = true
_G._vertical_bufferline_groups_instance = M

return M
