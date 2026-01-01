-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/groups.lua
-- Dynamic group management module

-- Anti-reload protection
if _G._vertical_bufferline_groups_loaded then
    return _G._vertical_bufferline_groups_instance
end

local config_module = require('vertical-bufferline.config')

local M = {}

local api = vim.api

local function new_groups_data()
    return {
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

        -- Group settings
        settings = {
            auto_create_groups = config_module.settings.auto_create_groups,
            auto_add_new_buffers = config_module.settings.auto_add_new_buffers,
            group_name_prefix = "Group",
            group_scope = config_module.settings.group_scope,
            inherit_on_new_window = config_module.settings.inherit_on_new_window,
        },

        -- Flag to temporarily disable auto-adding
        auto_add_disabled = false,

        -- Flag to temporarily disable history sync (when clicking history items)
        history_sync_disabled = false,
    }
end

local group_contexts = {}
local global_groups_data = new_groups_data()
local groups_data = global_groups_data

local function is_window_scope_enabled()
    if config_module.settings.group_scope ~= "window" then
        return false
    end
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    return not bufferline_integration.is_available()
end

local function with_groups_data(data, fn)
    local previous = groups_data
    groups_data = data
    local ok, result = pcall(fn)
    groups_data = previous
    if not ok then
        error(result)
    end
    return result
end

local function get_context_id_for_window(winid)
    return winid
end

function M.get_context_id_for_window(winid)
    return get_context_id_for_window(winid)
end

function M.is_window_scope_enabled()
    return is_window_scope_enabled()
end

local function seed_default_group_buffer(buf_id)
    if not buf_id or not api.nvim_buf_is_valid(buf_id) then
        return
    end

    local buftype = api.nvim_buf_get_option(buf_id, 'buftype')
    if buftype ~= '' then
        return
    end

    local bufname = api.nvim_buf_get_name(buf_id)
    if bufname == '' then
        return
    end

    M.add_buffer_to_group(buf_id, groups_data.default_group_id)
end

--- Re-index all groups to ensure display numbers are continuous
local function reindex_groups()
    for i, group in ipairs(groups_data.groups) do
        group.display_number = i
    end
end

--- Update group's buffer list and sync history accordingly
--- @param group table Group object
--- @param new_buffers table Array of buffer IDs
local function update_group_buffers_internal(group, new_buffers)
    group.buffers = new_buffers

    -- Sync history with updated buffers
    if group.history then
        local updated_history = {}
        for _, hist_buf_id in ipairs(group.history) do
            if vim.tbl_contains(new_buffers, hist_buf_id) then
                table.insert(updated_history, hist_buf_id)
            end
        end
        group.history = updated_history
    end
end

-- Initialize default group
local function init_default_group()
    if #groups_data.groups == 0 then
        local default_group = {
            id = groups_data.default_group_id,
            name = "Default",
            buffers = {},
            created_at = os.time(),
            color = config_module.COLORS.BLUE,
            display_number = config_module.SYSTEM.FIRST_INDEX,
            buffer_states = {},  -- Store per-buffer window states (cursor, scroll, etc.)
            position_info = {},   -- Store bufferline position info {buffer_id -> local_pos}
            history = {}  -- Store recent file access history, first item is current buffer
        }
        table.insert(groups_data.groups, default_group)
        groups_data.active_group_id = groups_data.default_group_id
        
        reindex_groups()

        -- Don't auto-add buffers during initialization, left to caller
    end
end

local function ensure_window_context(winid, opts)
    local context_id = get_context_id_for_window(winid)
    local created = false
    if not group_contexts[context_id] then
        created = true
        local data
        local can_inherit = opts and opts.inherit and opts.source_data and #opts.source_data.groups > 0
        if can_inherit then
            data = vim.deepcopy(opts.source_data)
        else
            data = new_groups_data()
            with_groups_data(data, function()
                init_default_group()
                if opts and opts.seed_on_create and opts.seed_buffer_id then
                    seed_default_group_buffer(opts.seed_buffer_id)
                end
            end)
        end
        group_contexts[context_id] = data
    end
    return group_contexts[context_id], created
end

local function is_eligible_window(winid)
    if not winid or not api.nvim_win_is_valid(winid) then
        return false
    end

    local state_module = require('vertical-bufferline.state')
    if state_module.get_win_id and winid == state_module.get_win_id() then
        return false
    end

    local win_config = api.nvim_win_get_config(winid)
    if win_config.relative ~= "" then
        return false
    end

    return true
end

local function find_primary_window()
    local current_win = api.nvim_get_current_win()
    if is_eligible_window(current_win) then
        return current_win
    end

    for _, win_id in ipairs(api.nvim_list_wins()) do
        if is_eligible_window(win_id) then
            return win_id
        end
    end

    return nil
end

function M.activate_window_context(winid, opts)
    if not is_window_scope_enabled() then
        groups_data = global_groups_data
        return groups_data
    end

    local target_win = winid or api.nvim_get_current_win()
    if not is_eligible_window(target_win) then
        target_win = find_primary_window()
    end

    if not target_win then
        return groups_data
    end

    opts = opts or {}
    local context = ensure_window_context(target_win, {
        inherit = config_module.settings.inherit_on_new_window,
        source_data = groups_data,
        seed_buffer_id = opts.seed_buffer_id,
        seed_on_create = opts.seed_on_create,
    })

    groups_data = context
    return groups_data
end

function M.get_vbl_groups_by_window(winid)
    if not is_window_scope_enabled() then
        return global_groups_data
    end

    local target_win = winid or api.nvim_get_current_win()
    if not is_eligible_window(target_win) then
        target_win = find_primary_window()
    end

    if not target_win then
        return groups_data
    end

    return ensure_window_context(target_win, {})
end

function M.reset_window_contexts()
    group_contexts = {}
    groups_data = global_groups_data
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
    -- Display numbers are now guaranteed to match the index (1-based)
    return groups_data.groups[display_number]
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

local function get_or_create_empty_group_buffer()
    local all_buffers = api.nvim_list_bufs()
    for _, buf_id in ipairs(all_buffers) do
        if api.nvim_buf_is_valid(buf_id) then
            local buftype = api.nvim_buf_get_option(buf_id, 'buftype')
            local buf_name = api.nvim_buf_get_name(buf_id)
            if buftype == 'nofile' and buf_name:match('%[Empty Group%]') then
                return buf_id
            end
        end
    end

    local empty_group_buffer = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(empty_group_buffer, '[Empty Group]')
    api.nvim_buf_set_option(empty_group_buffer, 'buftype', 'nofile')
    api.nvim_buf_set_option(empty_group_buffer, 'swapfile', false)
    api.nvim_buf_set_option(empty_group_buffer, 'buflisted', false)

    local lines = {
        "# Empty Group",
        "",
        "This group currently has no files.",
        "",
        "To add files to this group:",
        "- Open files in other groups and switch back",
        "- Or use :VBufferLineAddCurrentToGroup",
    }
    api.nvim_buf_set_lines(empty_group_buffer, 0, -1, false, lines)
    api.nvim_buf_set_option(empty_group_buffer, 'modifiable', false)

    return empty_group_buffer
end

function M.switch_to_empty_group_buffer()
    local empty_group_buffer = get_or_create_empty_group_buffer()
    pcall(api.nvim_set_current_buf, empty_group_buffer)
    return empty_group_buffer
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
        created_at = os.time(),
        color = color or config_module.COLORS.GREEN,
        display_number = 0, -- Will be set by reindex_groups
        buffer_states = {},  -- Store per-buffer window states (cursor, scroll, etc.)
        position_info = {},  -- Store bufferline position info {buffer_id -> local_pos}
        history = {}         -- Store recent file access history {buffer_id, ...} (newest first, first item is current buffer)
    }

    table.insert(groups_data.groups, new_group)
    reindex_groups()

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
    reindex_groups()

    -- If deleting current active group, switch to default group
    if groups_data.active_group_id == group_id then
        -- Use proper group switching logic instead of direct assignment
        M.set_active_group(groups_data.default_group_id)
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

--- Replace all groups with new layout from edit mode
--- @param group_specs table[] List of { name = string, buffers = number[] }
function M.replace_groups_from_edit(group_specs)
    local old_by_name = {}
    for _, group in ipairs(groups_data.groups) do
        old_by_name[group.name] = old_by_name[group.name] or {}
        table.insert(old_by_name[group.name], group)
    end

    local new_groups = {}
    for _, spec in ipairs(group_specs) do
        local group = nil
        local candidates = old_by_name[spec.name]
        if candidates and #candidates > 0 then
            group = table.remove(candidates, 1)
        end

        if not group then
            group = {
                id = generate_group_id(),
                name = spec.name or "",
                buffers = {},
                created_at = os.time(),
                color = config_module.COLORS.GREEN,
                display_number = 0,
                buffer_states = {},
                position_info = {},
                history = {},
            }
        else
            group.name = spec.name or ""
        end

        update_group_buffers_internal(group, spec.buffers or {})
        table.insert(new_groups, group)
    end

    groups_data.groups = new_groups
    reindex_groups()
    if #groups_data.groups == 0 then
        init_default_group()
    end

    local has_default = false
    for _, group in ipairs(groups_data.groups) do
        if group.id == groups_data.default_group_id then
            has_default = true
            break
        end
    end
    if not has_default and #groups_data.groups > 0 then
        groups_data.default_group_id = groups_data.groups[1].id
    end

    groups_data.active_group_id = nil
    groups_data.previous_group_id = nil
end

--- Get current active group
--- @return table|nil Active group or nil if none
function M.get_active_group()
    return find_group_by_id(groups_data.active_group_id)
end

--- Get current active group ID
--- @return string|nil Active group ID or nil if none
function M.get_active_group_id()
    return groups_data.active_group_id
end

--- Set active group
--- @param group_id string ID of group to activate
--- @return boolean success
function M.set_active_group(group_id, target_buffer_id)
    -- Safety: Clear any lingering extended_picking state when switching groups
    -- This prevents issues where picking mode might interfere with group switching
    local state_module = require('vertical-bufferline.state')
    if state_module.get_extended_picking_state().is_active then
        state_module.set_extended_picking_active(false)
    end

    local group = find_group_by_id(group_id)
    if not group then
        vim.notify("Group not found: " .. group_id, vim.log.levels.ERROR)
        return false
    end

    if group_id == groups_data.active_group_id then
        return false
    end

    local old_group_id = groups_data.active_group_id
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    
    -- Store previous group ID for switching back
    if old_group_id then
        groups_data.previous_group_id = old_group_id
    end
    
    -- Save current buffer state for the old group before switching
    local old_group = M.get_active_group()
    if old_group then
        local current_buf = vim.api.nvim_get_current_buf()
        if vim.tbl_contains(old_group.buffers, current_buf) then
            -- Update history with current buffer (add to front if not already there)
            M.sync_group_history_with_current(old_group.id, current_buf)
            -- Save comprehensive window state for current buffer
            save_buffer_state(old_group, current_buf)
        end
        
        -- Save current group's position info before switching (only local positions)
        if bufferline_integration.is_available() then
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
    end

    -- disable copying bufferline buffer list to group
    if bufferline_integration.is_available() then
        bufferline_integration.set_sync_target(nil)
        -- Reverse control: set new group's buffer list to bufferline
        bufferline_integration.set_bufferline_buffers(group.buffers)
    end

    -- Switch to group's remembered current buffer or fallback intelligently
    if #group.buffers > 0 then
        local target_buffer = nil
        
        -- Highest priority: use explicitly requested target buffer if valid
        if target_buffer_id and vim.api.nvim_buf_is_valid(target_buffer_id) 
           and vim.tbl_contains(group.buffers, target_buffer_id) then
            target_buffer = target_buffer_id
        -- First priority: use group's remembered current buffer if valid
        elseif group.current_buffer and vim.api.nvim_buf_is_valid(group.current_buffer)
               and vim.tbl_contains(group.buffers, group.current_buffer) then
            target_buffer = group.current_buffer
        -- Second priority: use first item in history (current buffer) if valid
        elseif #group.history > 0 and vim.api.nvim_buf_is_valid(group.history[1])
               and vim.tbl_contains(group.buffers, group.history[1]) then
            target_buffer = group.history[1]
        else
        -- Third priority: keep current buffer if it's in the group
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
        
        -- Switch to the determined buffer (suppress auto-add during programmatic switch)
        if target_buffer then
            M.set_auto_add_disabled(true)
            M.set_history_sync_disabled(true)
            local ok = pcall(vim.api.nvim_set_current_buf, target_buffer)
            M.set_history_sync_disabled(false)
            if ok then
                -- Update history with current buffer (ensure it's at the front)
                M.sync_group_history_with_current(group.id, target_buffer)
            end
            
            -- Restore saved window state for this buffer in this group
            vim.schedule(function()
                if ok then
                    restore_buffer_state(group, target_buffer)
                end
            end)
            vim.schedule(function()
                M.set_auto_add_disabled(false)
            end)
        end
    end
    -- If group is empty, switch to dedicated empty buffer to avoid carrying old context
    if #group.buffers == 0 then
        group.current_buffer = nil
        M.switch_to_empty_group_buffer()
    end

    -- Restore sync pointer to new group (step 3 of atomic operation)
    -- First update active group ID
    groups_data.active_group_id = group_id

    -- Sync pointer to new group
    if bufferline_integration.is_available() then
        bufferline_integration.set_sync_target(group_id)
    end

    -- Initialize position info for the new active group after bufferline sync
    if bufferline_integration.is_available() then
        vim.schedule(function()
            -- Force refresh bufferline first
            local ok_ui, bufferline_ui = pcall(require, 'bufferline.ui')
            if ok_ui and bufferline_ui.refresh then
                bufferline_ui.refresh()
            end
            
            -- Then update position info for new active group
            vim.defer_fn(function()
                local position_info = bufferline_integration.get_buffer_position_info(group_id)
                M.update_group_position_info(group_id, position_info)
            end, 50)  -- Small delay to ensure bufferline is updated
        end)
    end

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

    -- Add to specified group in correct order based on bufferline's sorting (if available)
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    local insert_position = #group.buffers + 1
    if bufferline_integration.is_available() then
        local sorted_buffers = bufferline_integration.get_sorted_buffers()

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

    -- Simply return the current buffer list
    -- All cleanup should be done via update_group_buffers, not here
    return group.buffers or {}
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
    
    reindex_groups()

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

    reindex_groups()

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

    reindex_groups()

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

-- Convenience functions for enabling/disabling auto-add
function M.disable_auto_add()
    groups_data.auto_add_disabled = true
end

function M.enable_auto_add()
    groups_data.auto_add_disabled = false
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
    update_group_buffers_internal(active_group, buffer_list or {})

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
        update_group_buffers_internal(group, valid_buffers)
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

    if is_window_scope_enabled() then
        M.activate_window_context(api.nvim_get_current_win())
        groups_data.settings = vim.tbl_deep_extend("force", groups_data.settings, opts)
    else
        -- Initialize default group
        init_default_group()
    end

    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    if bufferline_integration.is_available() then
        bufferline_integration.set_sync_target(groups_data.active_group_id)
    end

    -- Force refresh to ensure initial state displays correctly
    vim.schedule(function()
        -- Trigger UI update event
        vim.api.nvim_exec_autocmds("User", {
            pattern = config_module.EVENTS.GROUP_CHANGED,
            data = { new_group_id = groups_data.active_group_id }
        })
    end)

    -- Auto-add new buffers to active group (for VBL standalone mode without bufferline)
    vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "*",
        callback = function(args)
            if is_window_scope_enabled() then
                local buf_id = tonumber(args.buf)
                local target_win = buf_id and vim.fn.win_findbuf(buf_id)[1] or nil
                M.activate_window_context(target_win or api.nvim_get_current_win())
            end

            -- Only auto-add if bufferline is not available
            local bufferline_integration = require('vertical-bufferline.bufferline-integration')
            if bufferline_integration.is_available() then
                return  -- Let bufferline sync handle this
            end

            -- Only proceed if auto_add is enabled
            if not groups_data.settings.auto_add_new_buffers or groups_data.auto_add_disabled then
                return
            end

            -- Get buffer number - args.buf should be a number, but ensure it is
            local buf_id = tonumber(args.buf)
            if not buf_id then
                return  -- Invalid buffer number
            end

            -- Skip special buffers
            if not vim.api.nvim_buf_is_valid(buf_id) then return end

            local buftype = vim.api.nvim_buf_get_option(buf_id, 'buftype')
            if buftype ~= '' then return end  -- Skip special buffers

            local bufname = vim.api.nvim_buf_get_name(buf_id)
            if bufname == '' then return end  -- Skip unnamed buffers

            -- Add to active group
            local active_group = M.get_active_group()
            if active_group then
                M.add_buffer_to_group(buf_id, active_group.id)
            end
        end,
        desc = "Auto-add new buffers to active group (VBL standalone)"
    })

    -- Track history on every buffer enter in standalone mode
    vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "*",
        callback = function(args)
            if is_window_scope_enabled() then
                local buf_id = tonumber(args.buf)
                local target_win = buf_id and vim.fn.win_findbuf(buf_id)[1] or nil
                M.activate_window_context(target_win or api.nvim_get_current_win())
            end

            local bufferline_integration = require('vertical-bufferline.bufferline-integration')
            if bufferline_integration.is_available() then
                return -- bufferline handles history sync
            end

            local buf_id = tonumber(args.buf)
            if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
                return
            end

            local buftype = vim.api.nvim_buf_get_option(buf_id, 'buftype')
            if buftype ~= '' then
                return
            end

            local bufname = vim.api.nvim_buf_get_name(buf_id)
            if bufname == '' then
                return
            end

            local active_group = M.get_active_group()
            if not active_group then
                return
            end

            if vim.tbl_contains(active_group.buffers, buf_id) then
                M.sync_group_history_with_current(active_group.id, buf_id)
            end
        end,
        desc = "Sync history on BufEnter (VBL standalone)"
    })

    -- Periodically clean up invalid buffers and buffer states
    vim.defer_fn(function()
        if is_window_scope_enabled() then
            for _, context in pairs(group_contexts) do
                with_groups_data(context, function()
                    M.cleanup_invalid_buffers()
                    for _, group in ipairs(groups_data.groups) do
                        cleanup_buffer_states(group)
                    end
                end)
            end
        else
            M.cleanup_invalid_buffers()
            -- Clean up old buffer states from all groups
            for _, group in ipairs(groups_data.groups) do
                cleanup_buffer_states(group)
            end
        end
    end, config_module.UI.AUTO_SAVE_DELAY)

    if is_window_scope_enabled() then
        vim.api.nvim_create_autocmd("WinEnter", {
            pattern = "*",
            callback = function(args)
                local win_id = args.win or api.nvim_get_current_win()
                if type(win_id) ~= "number" then
                    return
                end
                M.activate_window_context(win_id, {
                    seed_on_create = true,
                    seed_buffer_id = api.nvim_win_get_buf(win_id),
                })
            end,
            desc = "Activate VBL group context for window",
        })

        vim.api.nvim_create_autocmd("WinClosed", {
            pattern = "*",
            callback = function(args)
                local win_id = tonumber(args.match)
                if win_id then
                    group_contexts[win_id] = nil
                end
            end,
            desc = "Remove VBL group context for closed window",
        })
    end
end

--- Switch to group by display number (for quick switch shortcuts)
--- @param display_number number Display number shown in UI (1, 2, 3, etc.)
--- @return boolean success
function M.switch_to_group_by_display_number(display_number)
    local group = find_group_by_display_number(display_number)
    if not group then
        return false
    end
    local function format_group_switch_label(target_group, fallback_number)
        local name = target_group and target_group.name or ""
        local number = fallback_number or (target_group and target_group.display_number) or target_group and target_group.id
        if number ~= nil then
            local label = "[" .. tostring(number) .. "]"
            if name ~= "" then
                label = label .. " " .. name
            end
            return label
        end

        if name ~= "" then
            return name
        end

        return "Group"
    end

    local switched = M.set_active_group(group.id)
    if switched then
        local label = format_group_switch_label(group, display_number)
        vim.notify("Switched to group: " .. label, vim.log.levels.INFO)
    end
    return switched
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
    
    -- If no current buffer, clear history and current buffer
    if not current_buffer_id then
        group.history = {}
        group.current_buffer = nil
        return
    end

    group.current_buffer = current_buffer_id
    
    -- Remove current buffer from any other position in history
    for i, hist_buf_id in ipairs(group.history) do
        if hist_buf_id == current_buffer_id then
            table.remove(group.history, i)
            break
        end
    end
    
    -- Add current buffer to front of history
    table.insert(group.history, 1, current_buffer_id)
    
    -- Limit history size
    local max_size = config_module.settings.history_size
    while #group.history > max_size do
        table.remove(group.history)
    end
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

--- Update group's buffer list and sync history accordingly
--- @param group_id string Group ID
--- @param new_buffers table Array of buffer IDs
function M.update_group_buffers(group_id, new_buffers)
    local group = find_group_by_id(group_id)
    if group then
        update_group_buffers_internal(group, new_buffers)
    end
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
    local show_history = config_module.settings.show_history
    
    if show_history == "no" then
        return false
    elseif show_history == "yes" then
        return true
    else -- "auto"
        local history = M.get_group_history(group_id)
        return #history >= config_module.settings.history_auto_threshold
    end
end

--- Clear history for a specific group or all groups
--- @param group_id string|nil Group ID to clear history for (nil = clear all groups)
--- @return boolean success
function M.clear_group_history(group_id)
    if group_id then
        -- Clear history for specific group
        local group = find_group_by_id(group_id)
        if group then
            group.history = {}
            return true
        end
        return false
    else
        -- Clear history for all groups
        for _, group in ipairs(groups_data.groups) do
            group.history = {}
        end
        return true
    end
end

--- Cycle through show_history settings: auto -> yes -> no -> auto
--- @return string new_setting The new show_history setting
function M.cycle_show_history()
    local current = config_module.settings.show_history
    local new_setting
    
    if current == "auto" then
        new_setting = "yes"
    elseif current == "yes" then
        new_setting = "no"
    else -- "no"
        new_setting = "auto"
    end
    
    config_module.settings.show_history = new_setting
    return new_setting
end

M.find_group_by_id = find_group_by_id

-- Save global instance and set flag
_G._vertical_bufferline_groups_loaded = true
_G._vertical_bufferline_groups_instance = M

return M
