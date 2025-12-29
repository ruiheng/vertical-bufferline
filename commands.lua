-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/commands.lua
-- User commands for group management

local M = {}

local groups = require('vertical-bufferline.groups')
local logger = require('vertical-bufferline.logger')
local utils = require('vertical-bufferline.utils')

-- Create group command
local function create_group_command(args)
    local name = args.args
    if name == "" then
        name = nil  -- Use default name
    end

    local group_id = groups.create_group(name)
    local all_groups = groups.get_all_groups()

    for _, g in ipairs(all_groups) do
        if g.id == group_id then
            vim.notify("Created group: " .. g.name .. " (ID: " .. group_id .. ")", vim.log.levels.INFO)
            break
        end
    end

    groups.set_active_group(group_id) -- this will refresh UI

    return group_id
end

-- Delete group command
local function delete_group_command(args)
    local input = args.args
    local all_groups = groups.get_all_groups()
    local target_group = nil

    if input == "" then
        -- No argument provided: delete current active group
        local active_group = groups.get_active_group()
        if active_group then
            target_group = active_group
        else
            vim.notify("No active group to delete", vim.log.levels.ERROR)
            return
        end
    else
        -- Argument provided: find by sequence number, name, or ID
        local group_number = tonumber(input)
        if group_number then
            if group_number >= 1 and group_number <= #all_groups then
                target_group = all_groups[group_number]
            end
        else
            -- If not a number, find by name or ID (backward compatibility)
            for _, group in ipairs(all_groups) do
                if group.id == input or (group.name ~= "" and group.name == input) then
                    target_group = group
                    break
                end
            end
        end
    end

    if not target_group then
        if input ~= "" then
            -- Error when explicit argument was provided but not found
            local group_number = tonumber(input)
            if group_number then
                vim.notify("Invalid group number: " .. input .. " (valid range: 1-" .. #all_groups .. ")", vim.log.levels.ERROR)
            else
                vim.notify("Group not found: " .. input, vim.log.levels.ERROR)
            end
        end
        return
    end

    -- Prevent deletion of default group
    if target_group.id == "default" then
        vim.notify("Cannot delete the default group", vim.log.levels.WARN)
        return
    end

    if groups.delete_group(target_group.id) then
        vim.notify("Deleted group: " .. target_group.name, vim.log.levels.INFO)

        -- Refresh interface
        vim.schedule(function()
            if require('vertical-bufferline').refresh then
                require('vertical-bufferline').refresh()
            end
        end)
    end
end

-- Rename group command
local function rename_group_command(args)
    local new_name = args.args
    if new_name == "" then
        vim.notify("Usage: VBufferLineRenameGroup <new_name>", vim.log.levels.ERROR)
        return
    end

    -- Get current active group
    local active_group = groups.get_active_group()
    if not active_group then
        vim.notify("No active group to rename", vim.log.levels.ERROR)
        return
    end

    local old_name = active_group.name == "" and "(unnamed)" or active_group.name

    if groups.rename_group(active_group.id, new_name) then
        vim.notify("Renamed group '" .. old_name .. "' to '" .. new_name .. "'", vim.log.levels.INFO)

        -- Refresh interface immediately
        vim.schedule(function()
            if require('vertical-bufferline').refresh then
                require('vertical-bufferline').refresh()
            end
        end)
    end
end

-- Switch group command
local function switch_group_command(args)
    local group_name_or_id = args.args
    if group_name_or_id == "" then
        -- Show current group information
        local active_group = groups.get_active_group()
        if active_group then
            vim.notify("Current group: " .. active_group.name .. " (" .. #active_group.buffers .. " buffers)", vim.log.levels.INFO)
        end
        return
    end

    -- Find and switch to specified group
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
        -- Group switching completed, sidebar will automatically update display

        -- Trigger bufferline force refresh
        local bufferline_integration = require('vertical-bufferline.bufferline-integration')
        bufferline_integration.force_refresh()

        -- Also refresh our sidebar
        vim.schedule(function()
            if require('vertical-bufferline').refresh then
                require('vertical-bufferline').refresh()
            end
        end)
    end
end


-- Add current buffer to group command
local function add_buffer_to_group_command(args)
    local group_name_or_id = args.args
    if group_name_or_id == "" then
        vim.notify("Usage: VBufferLineAddToGroup <group_name_or_id>", vim.log.levels.ERROR)
        return
    end

    local current_buffer = vim.api.nvim_get_current_buf()

    -- Find group
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


-- Quick switch to next group
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
    -- Switch to next group

    -- Trigger bufferline force refresh
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    bufferline_integration.force_refresh()

    -- Also refresh our sidebar
    vim.schedule(function()
        if require('vertical-bufferline').refresh then
            require('vertical-bufferline').refresh()
        end
    end)
end

-- Quick switch to previous group
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
    -- Switch to previous group

    -- Trigger bufferline force refresh
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    bufferline_integration.force_refresh()

    -- Also refresh our sidebar
    vim.schedule(function()
        if require('vertical-bufferline').refresh then
            require('vertical-bufferline').refresh()
        end
    end)
end

-- Toggle expand all groups mode
local function toggle_expand_all_command()
    local vbl = require('vertical-bufferline')
    vbl.toggle_expand_all()
end

-- Toggle show inactive group buffers mode
local function toggle_show_inactive_group_buffers_command()
    local vbl = require('vertical-bufferline')
    vbl.toggle_show_inactive_group_buffers()
end

-- Move current group up
local function move_group_up_command()
    local active_group = groups.get_active_group()
    if not active_group then
        vim.notify("No active group to move", vim.log.levels.ERROR)
        return
    end

    if groups.move_group_up(active_group.id) then
        vim.notify("Moved group '" .. active_group.name .. "' up", vim.log.levels.INFO)

        -- Refresh interface immediately
        vim.schedule(function()
            if require('vertical-bufferline').refresh then
                require('vertical-bufferline').refresh()
            end
        end)
    else
        vim.notify("Cannot move group up (already at top)", vim.log.levels.WARN)
    end
end

-- Move current group down
local function move_group_down_command()
    local active_group = groups.get_active_group()
    if not active_group then
        vim.notify("No active group to move", vim.log.levels.ERROR)
        return
    end

    if groups.move_group_down(active_group.id) then
        vim.notify("Moved group '" .. active_group.name .. "' down", vim.log.levels.INFO)

        -- Refresh interface immediately
        vim.schedule(function()
            if require('vertical-bufferline').refresh then
                require('vertical-bufferline').refresh()
            end
        end)
    else
        vim.notify("Cannot move group down (already at bottom)", vim.log.levels.WARN)
    end
end

-- Move current group to specified position
local function move_group_to_position_command(args)
    local position = tonumber(args.args)

    -- If no position parameter is provided, get it interactively
    if not position then
        local all_groups = groups.get_all_groups()
        local input = vim.fn.input("Move to position (1-" .. #all_groups .. "): ")
        if input == "" then
            return
        end
        position = tonumber(input)
        if not position then
            vim.notify("Invalid position: " .. input, vim.log.levels.ERROR)
            return
        end
    end

    local active_group = groups.get_active_group()
    if not active_group then
        vim.notify("No active group to move", vim.log.levels.ERROR)
        return
    end

    if groups.move_group_to_position(active_group.id, position) then
        vim.notify("Moved group '" .. active_group.name .. "' to position " .. position, vim.log.levels.INFO)

        -- Refresh interface immediately
        vim.schedule(function()
            if require('vertical-bufferline').refresh then
                require('vertical-bufferline').refresh()
            end
        end)
    else
        vim.notify("Cannot move group to position " .. position .. " (invalid position)", vim.log.levels.ERROR)
    end
end

-- Session management commands removed - sessions are now automatically managed
-- via auto_serialize and Neovim's native :mksession command
-- The plugin automatically serializes state to vim.g.VerticalBufferlineSession

-- Group completion function (for command completion)
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

local function edit_mode_command()
    require('vertical-bufferline.edit_mode').open()
end

--- Set up all user commands
function M.setup()
    -- Create group
    vim.api.nvim_create_user_command("VBufferLineCreateGroup", create_group_command, {
        nargs = "?",
        desc = "Create a new buffer group"
    })

    -- Edit group layout in a temporary buffer
    vim.api.nvim_create_user_command("VBufferLineEdit", edit_mode_command, {
        nargs = 0,
        desc = "Edit buffer groups in a temporary buffer"
    })

    -- Delete group
    vim.api.nvim_create_user_command("VBufferLineDeleteGroup", delete_group_command, {
        nargs = "?",
        desc = "Delete a buffer group by number, name, or current active group if no argument (e.g. :VBufferLineDeleteGroup 2)"
    })

    -- Rename group
    vim.api.nvim_create_user_command("VBufferLineRenameGroup", rename_group_command, {
        nargs = 1,
        desc = "Rename current buffer group"
    })

    -- Switch group
    vim.api.nvim_create_user_command("VBufferLineSwitchGroup", switch_group_command, {
        nargs = "?",
        complete = group_complete,
        desc = "Switch to a buffer group"
    })


    -- Add buffer to group
    vim.api.nvim_create_user_command("VBufferLineAddToGroup", add_buffer_to_group_command, {
        nargs = 1,
        complete = group_complete,
        desc = "Add current buffer to a group"
    })


    -- Next group
    vim.api.nvim_create_user_command("VBufferLineNextGroup", next_group_command, {
        nargs = 0,
        desc = "Switch to next buffer group"
    })

    -- Previous group
    vim.api.nvim_create_user_command("VBufferLinePrevGroup", prev_group_command, {
        nargs = 0,
        desc = "Switch to previous buffer group"
    })

    -- Toggle expand all groups mode
    vim.api.nvim_create_user_command("VBufferLineToggleExpandAll", toggle_expand_all_command, {
        nargs = 0,
        desc = "Toggle expand all groups mode"
    })

    -- Toggle show inactive group buffers mode
    vim.api.nvim_create_user_command("VBufferLineToggleInactiveGroupBuffers", toggle_show_inactive_group_buffers_command, {
        nargs = 0,
        desc = "Toggle showing buffer lists for inactive groups"
    })

    -- Picking commands
    vim.api.nvim_create_user_command("VBufferLinePick", function()
        require('vertical-bufferline').pick_buffer()
    end, {
        nargs = 0,
        desc = "Pick a buffer across groups"
    })

    vim.api.nvim_create_user_command("VBufferLinePickClose", function()
        require('vertical-bufferline').pick_close()
    end, {
        nargs = 0,
        desc = "Pick a buffer across groups and close it"
    })

    -- Group reordering commands
    vim.api.nvim_create_user_command("VBufferLineMoveGroupUp", move_group_up_command, {
        nargs = 0,
        desc = "Move current group up"
    })

    vim.api.nvim_create_user_command("VBufferLineMoveGroupDown", move_group_down_command, {
        nargs = 0,
        desc = "Move current group down"
    })

    vim.api.nvim_create_user_command("VBufferLineMoveGroupToPosition", move_group_to_position_command, {
        nargs = "?",
        desc = "Move current group to specified position (interactive if no position given)"
    })

    -- Session management commands removed
    -- Sessions are now automatically managed via auto_serialize and :mksession
    -- No user commands needed - everything is automatic

    -- Debug information
    vim.api.nvim_create_user_command("VBufferLineDebug", function()
        vim.notify("=== Debug Info ===", vim.log.levels.INFO)
        local all_groups = groups.get_all_groups()
        local active_group = groups.get_active_group()
        local stats = groups.get_group_stats()
        
        vim.notify("Groups count: " .. #all_groups, vim.log.levels.INFO)
        vim.notify("Active group: " .. (active_group and active_group.name or "none"), vim.log.levels.INFO)
        vim.notify("Stats: " .. vim.inspect(stats), vim.log.levels.INFO)

        -- Add bufferline integration status information
        local bufferline_integration = require('vertical-bufferline.bufferline-integration')
        local integration_status = bufferline_integration.status()

        vim.notify("\n=== Integration Status ===", vim.log.levels.INFO)
        vim.notify("Integration enabled: " .. tostring(integration_status.is_enabled), vim.log.levels.INFO)
        vim.notify("Timer active: " .. tostring(integration_status.timer_active), vim.log.levels.INFO)
    end, {
        nargs = 0,
        desc = "Show debug information"
    })


    -- Manual synchronization command
    vim.api.nvim_create_user_command("VBufferLineSyncGroups", function()
        local bufferline_integration = require('vertical-bufferline.bufferline-integration')
        bufferline_integration.manual_sync()
    end, {
        nargs = 0,
        desc = "Manually trigger synchronization between bufferline and groups"
    })

    -- Check buffer group duplicates
    vim.api.nvim_create_user_command("VBufferLineCheckDuplicates", function()
        vim.notify("=== Buffer Group Duplicates Check ===", vim.log.levels.INFO)
        local groups = require('vertical-bufferline.groups')
        local all_groups = groups.get_all_groups()
        local buffer_group_map = {}

        -- Collect group information for all buffers
        for i, group in ipairs(all_groups) do
            vim.notify(string.format("Group %d: '%s' (%d buffers)", i, group.name, #group.buffers), vim.log.levels.INFO)
            for _, buf_id in ipairs(group.buffers) do
                if not buffer_group_map[buf_id] then
                    buffer_group_map[buf_id] = {}
                end
                table.insert(buffer_group_map[buf_id], {group_id = group.id, group_name = group.name, group_index = i})
            end
        end

        -- Check for duplicates
        local duplicates_found = false
        vim.notify("\n=== Duplicate Analysis ===", vim.log.levels.INFO)
        for buf_id, group_list in pairs(buffer_group_map) do
            if #group_list > 1 then
                duplicates_found = true
                local name = vim.api.nvim_buf_get_name(buf_id)
                vim.notify(string.format("Buffer [%d] %s is in %d groups:",
                    buf_id, vim.fn.fnamemodify(name, ":t"), #group_list), vim.log.levels.WARN)
                for _, group_info in ipairs(group_list) do
                    vim.notify(string.format("  - %s (%s)", group_info.group_name, group_info.group_id), vim.log.levels.INFO)
                end
            end
        end

        if not duplicates_found then
            vim.notify("No duplicate buffer assignments found.", vim.log.levels.INFO)
        end
        vim.notify("========================", vim.log.levels.INFO)

        return duplicates_found
    end, {
        nargs = 0,
        desc = "Check for buffer group assignment duplicates"
    })

    -- Clean buffer group duplicates
    vim.api.nvim_create_user_command("VBufferLineCleanDuplicates", function()
        vim.notify("=== Cleaning Buffer Group Duplicates ===", vim.log.levels.INFO)
        local groups = require('vertical-bufferline.groups')
        local all_groups = groups.get_all_groups()
        local buffer_group_map = {}
        local cleaned_count = 0

        -- Collect group information for all buffers
        for i, group in ipairs(all_groups) do
            for _, buf_id in ipairs(group.buffers) do
                if not buffer_group_map[buf_id] then
                    buffer_group_map[buf_id] = {}
                end
                table.insert(buffer_group_map[buf_id], {group_id = group.id, group_name = group.name, group_index = i})
            end
        end

        -- Clean duplicates: keep first group, remove from others
        for buf_id, group_list in pairs(buffer_group_map) do
            if #group_list > 1 then
                local name = vim.api.nvim_buf_get_name(buf_id)
                vim.notify(string.format("Cleaning buffer [%d] %s from %d groups:",
                    buf_id, vim.fn.fnamemodify(name, ":t"), #group_list), vim.log.levels.INFO)

                -- Keep first group (usually active group or main group)
                local keep_group = group_list[1]
                vim.notify(string.format("  Keeping in: %s (%s)", keep_group.group_name, keep_group.group_id), vim.log.levels.INFO)

                -- Remove from other groups
                for i = 2, #group_list do
                    local remove_group = group_list[i]
                    groups.remove_buffer_from_group(buf_id, remove_group.group_id)
                    vim.notify(string.format("  Removed from: %s (%s)", remove_group.group_name, remove_group.group_id), vim.log.levels.INFO)
                    cleaned_count = cleaned_count + 1
                end
            end
        end

        if cleaned_count > 0 then
            vim.notify(string.format("Cleaned %d duplicate buffer assignments.", cleaned_count), vim.log.levels.INFO)
            -- Refresh interface
            local vbl = require('vertical-bufferline')
            if vbl.state and vbl.state.is_sidebar_open then
                vbl.refresh()
            end
        else
            vim.notify("No duplicate buffer assignments found to clean.", vim.log.levels.INFO)
        end
        vim.notify("========================", vim.log.levels.INFO)
    end, {
        nargs = 0,
        desc = "Clean buffer group assignment duplicates"
    })

    -- Rebuild group structure (thoroughly clean all issues)
    vim.api.nvim_create_user_command("VBufferLineRebuildGroups", function()
        vim.notify("=== Rebuilding Group Structure ===", vim.log.levels.INFO)
        local groups = require('vertical-bufferline.groups')
        local all_groups = groups.get_all_groups()
        local active_group_id = groups.get_active_group_id()

        -- Collect all currently valid buffers
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

        vim.notify(string.format("Found %d valid buffers", #all_valid_buffers), vim.log.levels.INFO)

        -- Clear buffer lists of all groups
        for _, group in ipairs(all_groups) do
            vim.notify(string.format("Clearing group '%s' (%d buffers)", group.name, #group.buffers), vim.log.levels.INFO)
            groups.update_group_buffers(group.id, {})
        end

        -- Reassign: each buffer belongs only to the first group
        if #all_groups > 0 then
            local target_group = all_groups[1]  -- Use first group by default
            for _, buf_id in ipairs(all_valid_buffers) do
                table.insert(target_group.buffers, buf_id)
                local name = vim.api.nvim_buf_get_name(buf_id)
                vim.notify(string.format("Added [%d] %s to group '%s'",
                    buf_id, vim.fn.fnamemodify(name, ":t"), target_group.name), vim.log.levels.INFO)
            end

            -- Ensure there is an active group
            if not active_group_id or not groups.get_active_group() then
                groups.set_active_group(target_group.id)
                vim.notify(string.format("Set active group to '%s'", target_group.name), vim.log.levels.INFO)
            end
        end

        -- Refresh interface
        local vbl = require('vertical-bufferline')
        if vbl.state and vbl.state.is_sidebar_open then
            vbl.refresh()
        end

        vim.notify("Group structure rebuilt successfully.", vim.log.levels.INFO)
        vim.notify("===================================", vim.log.levels.INFO)
    end, {
        nargs = 0,
        desc = "Completely rebuild group structure to fix all issues"
    })

    -- Control automatic buffer addition feature
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

    -- Manually force sync session and bufferline
    vim.api.nvim_create_user_command("VBufferLineForceSync", function()
        vim.notify("=== Force Sync Started ===", vim.log.levels.INFO)
        local bufferline_integration = require('vertical-bufferline.bufferline-integration')
        local groups = require('vertical-bufferline.groups')

        -- Show current status
        local active_group = groups.get_active_group()
        if active_group then
            vim.notify(string.format("Active group: %s (%d buffers)", active_group.name, #active_group.buffers), vim.log.levels.INFO)
        else
            vim.notify("No active group", vim.log.levels.WARN)
        end

        -- Force refresh bufferline
        bufferline_integration.force_refresh()

        -- Ensure current buffer is in active group (compatible with scope.nvim)
        if active_group and #active_group.buffers > 0 then
            local current_buf = vim.api.nvim_get_current_buf()
            local target_buf = nil

            -- If current buffer is not in active group, find a suitable one
            if not vim.tbl_contains(active_group.buffers, current_buf) then
                for _, buf_id in ipairs(active_group.buffers) do
                    if vim.api.nvim_buf_is_valid(buf_id) and vim.api.nvim_buf_is_loaded(buf_id) then
                        target_buf = buf_id
                        break
                    end
                end
            end

            if target_buf then
                -- Ensure all buffers in groups are visible to scope
                for _, buf_id in ipairs(active_group.buffers) do
                    if vim.api.nvim_buf_is_valid(buf_id) then
                        vim.bo[buf_id].buflisted = true
                        -- Brief switch to let scope recognize
                        local old_buf = vim.api.nvim_get_current_buf()
                        vim.api.nvim_set_current_buf(buf_id)
                        vim.api.nvim_set_current_buf(old_buf)
                    end
                end

                vim.api.nvim_set_current_buf(target_buf)
                vim.api.nvim_exec_autocmds('BufEnter', { buffer = target_buf })
                vim.notify(string.format("Switched to buffer: [%d] %s", target_buf,
                    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(target_buf), ":t")), vim.log.levels.INFO)
            end
        end

        -- Refresh sidebar
        local vbl = require('vertical-bufferline')
        if vbl.state and vbl.state.is_sidebar_open then
            vbl.refresh()
        end

        -- Force refresh again
        bufferline_integration.force_refresh()
        vim.notify("=== Force Sync Completed ===", vim.log.levels.INFO)
    end, {
        nargs = 0,
        desc = "Manually force sync between session, groups, and bufferline"
    })

    -- Manually add current buffer to current group (supports multi-group)
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

            -- Check if it also exists in other groups
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

            -- Refresh interface
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

    -- Smart close buffer (similar to scope.nvim)
    vim.api.nvim_create_user_command("VBufferLineSmartClose", function()
        local bufferline_integration = require('vertical-bufferline.bufferline-integration')
        bufferline_integration.smart_close_buffer()
    end, {
        nargs = 0,
        desc = "Smart close buffer: remove from group if exists elsewhere, delete globally otherwise"
    })

    -- Remove buffer from current group (soft delete)
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
            -- Use echo to display concise information, no need to press Enter
            local remaining_groups = groups.find_buffer_groups(current_buffer)
            if #remaining_groups > 0 then
                local group_names = {}
                for _, group in ipairs(remaining_groups) do
                    table.insert(group_names, group.name)
                end
                vim.notify("Removed '" .. short_name .. "' from '" .. active_group.name .. "' (still in: " .. table.concat(group_names, ", ") .. ")", vim.log.levels.INFO)
            else
                vim.notify("Removed '" .. short_name .. "' from '" .. active_group.name .. "' (removed from all groups)", vim.log.levels.INFO)
            end

            -- Refresh interface
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

    -- Manually refresh buffer list
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

                -- Exclude sidebar's own buffer (by checking bufhidden attribute)
                local buf_hidden = pcall(vim.api.nvim_buf_get_option, buf, 'bufhidden')
                local is_sidebar_buf = (buf_hidden and vim.api.nvim_buf_get_option(buf, 'bufhidden') == 'wipe')

                -- Only add buffers that bufferline would track
                if not utils.is_special_buffer(buf) and
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

        -- Refresh interface
        vim.schedule(function()
            if require('vertical-bufferline').refresh then
                require('vertical-bufferline').refresh()
            end
        end)
    end, {
        nargs = 0,
        desc = "Manually refresh and add current buffers to active group"
    })

    -- Debug logging commands
    vim.api.nvim_create_user_command("VBufferLineDebugEnable", function(args)
        local args_str = args.args or ""
        local args_list = args_str ~= "" and vim.split(args_str, "%s+") or {}
        local log_file = args_list[1] or vim.fn.expand("~/vbl-debug.log")
        local log_level = args_list[2] or "INFO"
        
        logger.enable(log_file, log_level)
        vim.notify(string.format("VBL debug logging enabled: %s (level: %s)", log_file, log_level), vim.log.levels.INFO)
    end, {
        nargs = "*",
        desc = "Enable VBL debug logging. Args: [log_file] [log_level]. Example: :VBufferLineDebugEnable ~/vbl.log DEBUG"
    })

    vim.api.nvim_create_user_command("VBufferLineDebugDisable", function()
        logger.disable()
        vim.notify("VBL debug logging disabled", vim.log.levels.INFO)
    end, {
        nargs = 0,
        desc = "Disable VBL debug logging"
    })

    vim.api.nvim_create_user_command("VBufferLineDebugStatus", function()
        local status = logger.get_status()
        if status.enabled then
            vim.notify(string.format("VBL debug logging: ENABLED\nFile: %s\nLevel: %s\nSession: %s\nBuffer lines: %d", 
                status.log_file or "none", status.log_level, status.session_id or "none", status.buffer_lines), 
                vim.log.levels.INFO)
        else
            vim.notify("VBL debug logging: DISABLED", vim.log.levels.INFO)
        end
    end, {
        nargs = 0,
        desc = "Show VBL debug logging status"
    })

    vim.api.nvim_create_user_command("VBufferLineTestUnnamed", function()
        print("=== Testing unnamed buffer creation ===")

        -- Create a new unnamed buffer
        vim.cmd('enew')
        local new_buf = vim.api.nvim_get_current_buf()

        print("Newly created buffer:")
        print("  ID:", new_buf)
        print("  Name:", vim.api.nvim_buf_get_name(new_buf))
        print("  Type:", vim.api.nvim_buf_get_option(new_buf, 'buftype'))
        print("  Listed:", vim.api.nvim_buf_get_option(new_buf, 'buflisted'))

        -- Check if VBL's is_special_buffer thinks it's special
        local init_module = require('vertical-bufferline')
        -- Since is_special_buffer is local, let's check indirectly

        print("This tells us if vim creates unnamed buffers as unlisted by default")
    end, {
        nargs = 0,
        desc = "Test unnamed buffer creation behavior"
    })

    vim.api.nvim_create_user_command("VBufferLineDebugState", function()
        print("=== Current VBL State ===")

        -- Check unnamed buffers
        local unnamed_bufs = {}
        local all_bufs = vim.api.nvim_list_bufs()
        for _, buf in ipairs(all_bufs) do
            if vim.api.nvim_buf_is_valid(buf) then
                local buf_name = vim.api.nvim_buf_get_name(buf)
                if buf_name == "" then
                    table.insert(unnamed_bufs, buf)
                    local buftype = vim.api.nvim_buf_get_option(buf, 'buftype')
                    local buflisted = vim.api.nvim_buf_get_option(buf, 'buflisted')
                    print(string.format("Unnamed buf %d: type='%s', listed=%s", buf, buftype, buflisted))
                end
            end
        end

        -- Check active group
        local groups = require('vertical-bufferline.groups')
        local active_group = groups.get_active_group()
        if active_group then
            print("Active group:", active_group.name, "ID:", active_group.id)
            print("Group buffers:", vim.inspect(active_group.buffers))

            -- Check if unnamed buffers are in active group
            for _, unnamed_buf in ipairs(unnamed_bufs) do
                local in_group = vim.tbl_contains(active_group.buffers, unnamed_buf)
                print(string.format("Unnamed buf %d in active group: %s", unnamed_buf, in_group))
            end
        end

        -- Check bufferline elements
        local bufferline_ok, bufferline = pcall(require, 'bufferline')
        if bufferline_ok then
            local elements = bufferline.get_elements().elements
            print("Bufferline elements count:", #elements)
            for _, elem in ipairs(elements) do
                local is_unnamed = vim.tbl_contains(unnamed_bufs, elem.id)
                print(string.format("  elem id %d: name='%s'%s", elem.id, elem.name or "[unnamed]", is_unnamed and " [UNNAMED]" or ""))
            end
        end
    end, {
        nargs = 0,
        desc = "Debug current VBL and bufferline state"
    })

    vim.api.nvim_create_user_command("VBufferLineWatchUnnamed", function()
        -- Create autocmd to watch when unnamed buffers get unlisted
        vim.api.nvim_create_autocmd({"BufEnter", "BufLeave", "BufAdd", "BufDelete"}, {
            callback = function(args)
                local buf = args.buf
                if vim.api.nvim_buf_is_valid(buf) then
                    local buf_name = vim.api.nvim_buf_get_name(buf)
                    if buf_name == "" then
                        local buftype = vim.api.nvim_buf_get_option(buf, 'buftype')
                        local buflisted = vim.api.nvim_buf_get_option(buf, 'buflisted')
                        print(string.format("[%s] Unnamed buf %d: type='%s', listed=%s",
                            args.event, buf, buftype, buflisted))
                    end
                end
            end
        })
        print("Watching unnamed buffer state changes. Open files to see what happens.")
    end, {
        nargs = 0,
        desc = "Watch unnamed buffer state changes"
    })

    vim.api.nvim_create_user_command("VBufferLineDebugSync", function()
        print("=== Debugging unnamed buffer issue ===")

        -- Check all current buffers
        local all_bufs = vim.api.nvim_list_bufs()
        local unnamed_buffers = {}
        print("All vim buffers:")
        for _, buf in ipairs(all_bufs) do
            if vim.api.nvim_buf_is_valid(buf) then
                local buf_name = vim.api.nvim_buf_get_name(buf)
                local buftype = vim.api.nvim_buf_get_option(buf, 'buftype')
                local buflisted = vim.api.nvim_buf_get_option(buf, 'buflisted')
                if buf_name == "" and buftype == "" then
                    table.insert(unnamed_buffers, buf)
                    -- Check if our is_special_buffer function thinks this is special
                    local integration = require('vertical-bufferline.bufferline-integration')
                    local init_module = require('vertical-bufferline')
                    local is_special = init_module.is_special_buffer and init_module.is_special_buffer(buf)
                    print(string.format("  buf %d: name='[unnamed]', type='%s', listed=%s, is_special=%s",
                        buf, buftype, buflisted, tostring(is_special)))
                else
                    print(string.format("  buf %d: name='%s', type='%s', listed=%s",
                        buf, buf_name == "" and "[unnamed]" or buf_name, buftype, buflisted))
                end
            end
        end

        -- Check bufferline's view
        local bufferline_ok, bufferline = pcall(require, 'bufferline')
        local bufferline_has_unnamed = false
        if bufferline_ok then
            local elements = bufferline.get_elements().elements
            print("Bufferline elements:")
            for _, elem in ipairs(elements) do
                local elem_name = elem.name or "[unnamed]"
                if #unnamed_buffers > 0 and vim.tbl_contains(unnamed_buffers, elem.id) then
                    bufferline_has_unnamed = true
                    elem_name = elem_name .. " [UNNAMED]"
                end
                print(string.format("  elem id %d: name='%s'", elem.id, elem_name))
            end
        end

        -- Check VBL active group
        local groups = require('vertical-bufferline.groups')
        local active_group = groups.get_active_group()
        local vbl_has_unnamed = false
        if active_group then
            print("VBL active group buffers:")
            for _, buf in ipairs(active_group.buffers) do
                local buf_name = vim.api.nvim_buf_get_name(buf)
                if #unnamed_buffers > 0 and vim.tbl_contains(unnamed_buffers, buf) then
                    vbl_has_unnamed = true
                    buf_name = buf_name .. " [UNNAMED]"
                end
                print(string.format("  buf %d: name='%s'", buf, buf_name == "" and "[unnamed]" or buf_name))
            end
        end

        print("\nSummary:")
        print("  Unnamed buffers exist:", #unnamed_buffers > 0)
        print("  Bufferline has unnamed:", bufferline_has_unnamed)
        print("  VBL has unnamed:", vbl_has_unnamed)

        if #unnamed_buffers > 0 and bufferline_has_unnamed and not vbl_has_unnamed then
            print("  PROBLEM: Bufferline has unnamed buffer but VBL doesn't!")
        elseif #unnamed_buffers > 0 and not bufferline_has_unnamed then
            print("  PROBLEM: Unnamed buffer exists but bufferline ignores it (probably buflisted=false)")
            -- Try to fix it
            for _, buf in ipairs(unnamed_buffers) do
                print("  Fixing unnamed buffer", buf, "- setting buflisted=true")
                vim.api.nvim_buf_set_option(buf, 'buflisted', true)
                local new_listed = vim.api.nvim_buf_get_option(buf, 'buflisted')
                print("    Verification: buflisted is now", new_listed)
            end

            -- Force VBL refresh after fixing
            local vbl = require('vertical-bufferline')
            vbl.refresh()
            print("  Fixed and refreshed VBL! Test your scenario now.")
        end
    end, {
        nargs = 0,
        desc = "Debug unnamed buffer sync issue"
    })

    vim.api.nvim_create_user_command("VBufferLineDebugLogs", function(args)
        local args_str = args.args or ""
        local count = (args_str ~= "" and tonumber(args_str)) or 20
        local logs = logger.get_recent_logs(count)
        
        if #logs == 0 then
            vim.notify("No logs available", vim.log.levels.INFO)
            return
        end
        
        -- Create a new buffer to display logs
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(buf, "VBL Debug Logs")

        -- Split multi-line log entries into separate lines
        local split_logs = {}
        for _, log_line in ipairs(logs) do
            local lines = vim.split(log_line, '\n', { plain = true })
            for _, line in ipairs(lines) do
                table.insert(split_logs, line)
            end
        end

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, split_logs)
        vim.api.nvim_buf_set_option(buf, 'filetype', 'log')
        vim.api.nvim_buf_set_option(buf, 'modifiable', false)
        
        -- Open in a new split
        vim.cmd("split")
        vim.api.nvim_set_current_buf(buf)
    end, {
        nargs = "?",
        desc = "Show recent VBL debug logs. Args: [count] (default: 20)"
    })

    -- Clear history command
    vim.api.nvim_create_user_command("VBufferLineClearHistory", function(opts)
        local groups = require('vertical-bufferline.groups')
        local target_group = opts.args and opts.args ~= "" and opts.args or nil
        
        if target_group then
            -- Clear history for specific group
            local success = groups.clear_group_history(target_group)
            if success then
                vim.notify("History cleared for group: " .. target_group, vim.log.levels.INFO)
            else
                vim.notify("Group not found: " .. target_group, vim.log.levels.ERROR)
                return
            end
        else
            -- Clear history for all groups
            groups.clear_group_history()
            vim.notify("History cleared for all groups", vim.log.levels.INFO)
        end

        -- Refresh interface to update display
        vim.schedule(function()
            if require('vertical-bufferline').refresh then
                require('vertical-bufferline').refresh("clear_history")
            end
        end)
    end, {
        nargs = "?",
        desc = "Clear history for specific group or all groups (no args = all groups)"
    })

    -- Toggle cursor alignment
    vim.api.nvim_create_user_command("VBufferLineToggleCursorAlign", function()
        local config = require('vertical-bufferline.config')
        config.DEFAULTS.align_with_cursor = not config.DEFAULTS.align_with_cursor
        local status = config.DEFAULTS.align_with_cursor and "enabled" or "disabled"
        vim.notify(string.format("VBL cursor alignment: %s", status), vim.log.levels.INFO)

        -- Refresh to apply the change
        require('vertical-bufferline').refresh("cursor_align_toggle")
    end, {
        nargs = 0,
        desc = "Toggle cursor alignment for VBL content"
    })

    -- Toggle adaptive width
    vim.api.nvim_create_user_command("VBufferLineToggleAdaptiveWidth", function()
        local config = require('vertical-bufferline.config')
        config.DEFAULTS.adaptive_width = not config.DEFAULTS.adaptive_width
        local status = config.DEFAULTS.adaptive_width and "enabled" or "disabled"
        vim.notify(string.format("VBL adaptive width: %s", status), vim.log.levels.INFO)

        local state = require('vertical-bufferline.state')
        local win_id = state.get_win_id()
        if win_id and vim.api.nvim_win_is_valid(win_id) then
            vim.api.nvim_win_set_option(win_id, 'winfixwidth', not config.DEFAULTS.adaptive_width)
        end

        -- Refresh to apply the change
        require('vertical-bufferline').refresh("adaptive_width_toggle")
    end, {
        nargs = 0,
        desc = "Toggle adaptive width for VBL sidebar"
    })

    -- Debug pick mode hints
    vim.api.nvim_create_user_command("VBufferLineDebugPickMode", function()
        logger.enable(vim.fn.expand("~/vbl-pick-debug.log"), "DEBUG")
        vim.notify("VBL pick mode debug logging enabled: ~/vbl-pick-debug.log\nNow enter pick mode and check the log file", vim.log.levels.INFO)
    end, {
        nargs = 0,
        desc = "Enable debug logging for pick mode hints"
    })

    -- Pick mode commands removed - using VBufferLinePick and VBufferLinePickClose defined earlier
end

-- Export functions for use by other modules
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
