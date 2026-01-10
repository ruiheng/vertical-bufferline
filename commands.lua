-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/commands.lua
-- User commands for group management

local M = {}

local groups = require('buffer-nexus.groups')
local logger = require('buffer-nexus.logger')
local utils = require('buffer-nexus.utils')

-- Create group command
local function create_group_command(args)
    local name = args.args
    if name == "" then
        name = nil  -- Use default name
    end

    local group_id = groups.create_group(name)
    local new_buffer = vim.api.nvim_create_buf(true, false)
    if new_buffer then
        groups.add_buffer_to_group(new_buffer, group_id)
        pcall(vim.api.nvim_set_current_buf, new_buffer)
    end
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
            if require('buffer-nexus').refresh then
                require('buffer-nexus').refresh()
            end
        end)
    end
end

-- Rename group command
local function rename_group_command(args)
    local new_name = args.args
    if new_name == "" then
        vim.notify("Usage: BNRenameGroup <new_name>", vim.log.levels.ERROR)
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
            if require('buffer-nexus').refresh then
                require('buffer-nexus').refresh()
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
        local bufferline_integration = require('buffer-nexus.bufferline-integration')
        bufferline_integration.force_refresh()

        -- Also refresh our sidebar
        vim.schedule(function()
            if require('buffer-nexus').refresh then
                require('buffer-nexus').refresh()
            end
        end)
    end
end


-- Add current buffer to group command
local function add_buffer_to_group_command(args)
    local group_name_or_id = args.args
    if group_name_or_id == "" then
        vim.notify("Usage: BNAddToGroup <group_name_or_id>", vim.log.levels.ERROR)
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
    local bufferline_integration = require('buffer-nexus.bufferline-integration')
    bufferline_integration.force_refresh()

    -- Also refresh our sidebar
    vim.schedule(function()
        if require('buffer-nexus').refresh then
            require('buffer-nexus').refresh()
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
    local bufferline_integration = require('buffer-nexus.bufferline-integration')
    bufferline_integration.force_refresh()

    -- Also refresh our sidebar
    vim.schedule(function()
        if require('buffer-nexus').refresh then
            require('buffer-nexus').refresh()
        end
    end)
end

-- Toggle expand all groups mode
local function toggle_expand_all_command()
    local vbl = require('buffer-nexus')
    vbl.toggle_expand_all()
end

-- Toggle show inactive group buffers mode
local function toggle_show_inactive_group_buffers_command()
    local vbl = require('buffer-nexus')
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
            if require('buffer-nexus').refresh then
                require('buffer-nexus').refresh()
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
            if require('buffer-nexus').refresh then
                require('buffer-nexus').refresh()
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
            if require('buffer-nexus').refresh then
                require('buffer-nexus').refresh()
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
    require('buffer-nexus.edit_mode').open()
end

local function copy_groups_command(args)
    local register = args and args.args or ""
    if register ~= "" and #register ~= 1 then
        vim.notify("Usage: BNCopyGroups [register]", vim.log.levels.ERROR)
        return
    end
    require('buffer-nexus').copy_groups_to_register(register ~= "" and register or nil)
    vim.notify("Copied BN groups to register " .. (register ~= "" and register or '"'), vim.log.levels.INFO)
end

local group_file_extension = ".bngroups"

local function normalize_group_file_path(path)
    if not path or path == "" then
        return nil
    end
    local expanded = vim.fn.expand(path)
    if expanded:sub(-#group_file_extension) ~= group_file_extension then
        expanded = expanded .. group_file_extension
    end
    return expanded
end

local function prompt_group_file_path(kind, callback)
    local defaults = {
        save = "Session.bngroups",
        load = "Session.bngroups",
    }
    local prompts = {
        save = "Save buffer-nexus groups definition to file: ",
        load = "Load buffer-nexus groups definition from file: ",
    }
    vim.ui.input({
        prompt = prompts[kind] or "Buffer-nexus groups file: ",
        default = defaults[kind] or "bn-groups",
        completion = "file",
    }, function(input)
        if not input or input == "" then
            vim.notify("BN " .. kind .. " groups canceled", vim.log.levels.INFO)
            return
        end
        local target = normalize_group_file_path(input)
        if not target then
            vim.notify("BN " .. kind .. " groups canceled", vim.log.levels.INFO)
            return
        end
        callback(target)
    end)
end

local function save_groups_command(args)
    local path = args and args.args or ""
    local function do_save(target)
        local lines = require('buffer-nexus.edit_mode').build_edit_content_lines()
        local ok, result = pcall(vim.fn.writefile, lines, target)
        if not ok or result ~= 0 then
            vim.notify("Failed to save BN groups to " .. target, vim.log.levels.ERROR)
            return
        end
        vim.cmd("redraw")
        vim.notify("Saved BN groups to " .. target, vim.log.levels.INFO)
    end
    if path == "" then
        prompt_group_file_path("save", do_save)
        return
    end
    local target = normalize_group_file_path(path)
    if not target then
        vim.notify("Usage: BNSaveGroups [name]", vim.log.levels.ERROR)
        return
    end
    do_save(target)
end

local function load_groups_command(args)
    local path = args and args.args or ""
    local function do_load(target)
        local ok, lines = pcall(vim.fn.readfile, target)
        if not ok then
            vim.notify("Failed to read BN groups from " .. target, vim.log.levels.ERROR)
            return
        end
        require('buffer-nexus.edit_mode').apply_lines(lines, {
            prev_buf_id = vim.api.nvim_get_current_buf(),
            prev_win_id = vim.api.nvim_get_current_win(),
        })
        vim.cmd("redraw")
        vim.notify("Loaded BN groups from " .. target, vim.log.levels.INFO)
    end
    if path == "" then
        prompt_group_file_path("load", do_load)
        return
    end
    local target = normalize_group_file_path(path)
    if not target then
        vim.notify("Usage: BNLoadGroups [name]", vim.log.levels.ERROR)
        return
    end
    do_load(target)
end

--- Set up all user commands
function M.setup()
    -- Create group
    vim.api.nvim_create_user_command("BNCreateGroup", create_group_command, {
        nargs = "?",
        desc = "Create a new buffer group"
    })

    -- Edit group layout in a temporary buffer
    vim.api.nvim_create_user_command("BNEdit", edit_mode_command, {
        nargs = 0,
        desc = "Edit buffer groups in a temporary buffer"
    })

    vim.api.nvim_create_user_command("BNCopyGroups", copy_groups_command, {
        nargs = "?",
        desc = "Copy groups to a register (edit-mode format)"
    })

    vim.api.nvim_create_user_command("BNSaveGroups", save_groups_command, {
        nargs = "?",
        complete = "file",
        desc = "Save groups to a file (edit-mode format)"
    })

    vim.api.nvim_create_user_command("BNLoadGroups", load_groups_command, {
        nargs = "?",
        complete = "file",
        desc = "Load groups from a file (edit-mode format)"
    })

    -- Delete group
    vim.api.nvim_create_user_command("BNDeleteGroup", delete_group_command, {
        nargs = "?",
        desc = "Delete a buffer group by number, name, or current active group if no argument (e.g. :BNDeleteGroup 2)"
    })

    -- Rename group
    vim.api.nvim_create_user_command("BNRenameGroup", rename_group_command, {
        nargs = 1,
        desc = "Rename current buffer group"
    })

    -- Switch group
    vim.api.nvim_create_user_command("BNSwitchGroup", switch_group_command, {
        nargs = "?",
        complete = group_complete,
        desc = "Switch to a buffer group"
    })


    -- Add buffer to group
    vim.api.nvim_create_user_command("BNAddToGroup", add_buffer_to_group_command, {
        nargs = 1,
        complete = group_complete,
        desc = "Add current buffer to a group"
    })


    -- Next group
    vim.api.nvim_create_user_command("BNNextGroup", next_group_command, {
        nargs = 0,
        desc = "Switch to next buffer group"
    })

    -- Previous group
    vim.api.nvim_create_user_command("BNPrevGroup", prev_group_command, {
        nargs = 0,
        desc = "Switch to previous buffer group"
    })

    -- Toggle expand all groups mode
    vim.api.nvim_create_user_command("BNToggleExpandAll", toggle_expand_all_command, {
        nargs = 0,
        desc = "Toggle expand all groups mode"
    })

    -- Toggle show inactive group buffers mode
    vim.api.nvim_create_user_command("BNToggleInactiveGroupBuffers", toggle_show_inactive_group_buffers_command, {
        nargs = 0,
        desc = "Toggle showing buffer lists for inactive groups"
    })

    -- Picking commands
    vim.api.nvim_create_user_command("BNPick", function()
        require('buffer-nexus').pick_buffer()
    end, {
        nargs = 0,
        desc = "Pick a buffer across groups"
    })

    vim.api.nvim_create_user_command("BNPickClose", function()
        require('buffer-nexus').pick_close()
    end, {
        nargs = 0,
        desc = "Pick a buffer across groups and close it"
    })

    vim.api.nvim_create_user_command("BNPickGroup", function()
        require('buffer-nexus').pick_current_group()
    end, {
        nargs = 0,
        desc = "Pick a buffer in the current group with an external picker"
    })

    -- Group reordering commands
    vim.api.nvim_create_user_command("BNMoveGroupUp", move_group_up_command, {
        nargs = 0,
        desc = "Move current group up"
    })

    vim.api.nvim_create_user_command("BNMoveGroupDown", move_group_down_command, {
        nargs = 0,
        desc = "Move current group down"
    })

    vim.api.nvim_create_user_command("BNMoveGroupToPosition", move_group_to_position_command, {
        nargs = "?",
        desc = "Move current group to specified position (interactive if no position given)"
    })

    -- Session management commands removed
    -- Sessions are now automatically managed via auto_serialize and :mksession
    -- No user commands needed - everything is automatic

    -- Debug information
    vim.api.nvim_create_user_command("BNDebug", function()
        vim.notify("=== Debug Info ===", vim.log.levels.INFO)
        local all_groups = groups.get_all_groups()
        local active_group = groups.get_active_group()
        local stats = groups.get_group_stats()
        
        vim.notify("Groups count: " .. #all_groups, vim.log.levels.INFO)
        vim.notify("Active group: " .. (active_group and active_group.name or "none"), vim.log.levels.INFO)
        vim.notify("Stats: " .. vim.inspect(stats), vim.log.levels.INFO)

        -- Add bufferline integration status information
        local bufferline_integration = require('buffer-nexus.bufferline-integration')
        local integration_status = bufferline_integration.status()

        vim.notify("\n=== Integration Status ===", vim.log.levels.INFO)
        vim.notify("Integration enabled: " .. tostring(integration_status.is_enabled), vim.log.levels.INFO)
        vim.notify("Timer active: " .. tostring(integration_status.timer_active), vim.log.levels.INFO)
    end, {
        nargs = 0,
        desc = "Show debug information"
    })


    -- Control automatic buffer addition feature
    vim.api.nvim_create_user_command("BNToggleAutoAdd", function()
        local groups = require('buffer-nexus.groups')
        local current_state = groups.is_auto_add_disabled()
        groups.set_auto_add_disabled(not current_state)
        local new_state = groups.is_auto_add_disabled()
        vim.notify("Auto-add buffers: " .. (new_state and "DISABLED" or "ENABLED"), vim.log.levels.INFO)
    end, {
        nargs = 0,
        desc = "Toggle automatic buffer addition to active group"
    })

    -- Manually force sync session and bufferline
    vim.api.nvim_create_user_command("BNForceSync", function()
        vim.notify("=== Force Sync Started ===", vim.log.levels.INFO)
        local bufferline_integration = require('buffer-nexus.bufferline-integration')
        local groups = require('buffer-nexus.groups')

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
        local vbl = require('buffer-nexus')
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
    vim.api.nvim_create_user_command("BNAddCurrentToGroup", function()
        local groups = require('buffer-nexus.groups')
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
            local vbl = require('buffer-nexus')
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
    vim.api.nvim_create_user_command("BNSmartClose", function()
        local bufferline_integration = require('buffer-nexus.bufferline-integration')
        bufferline_integration.smart_close_buffer()
    end, {
        nargs = 0,
        desc = "Smart close buffer: remove from group if exists elsewhere, delete globally otherwise"
    })

    -- Remove buffer from current group (soft delete)
    vim.api.nvim_create_user_command("BNRemoveFromGroup", function()
        local groups = require('buffer-nexus.groups')
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
            local vbl = require('buffer-nexus')
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

    -- Keep only current buffer in group (remove others from group)
    vim.api.nvim_create_user_command("BNKeepOnlyCurrentInGroup", function()
        require('buffer-nexus').keep_only_current_buffer_in_group()
    end, {
        nargs = 0,
        desc = "Keep only current buffer in active group (remove others from group)"
    })

    -- Manually refresh buffer list
    vim.api.nvim_create_user_command("BNRefreshBuffers", function()
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
            if require('buffer-nexus').refresh then
                require('buffer-nexus').refresh()
            end
        end)
    end, {
        nargs = 0,
        desc = "Manually refresh and add current buffers to active group"
    })

    -- Debug logging commands
    vim.api.nvim_create_user_command("BNDebugEnable", function(args)
        local args_str = args.args or ""
        local args_list = args_str ~= "" and vim.split(args_str, "%s+") or {}
        local log_file = args_list[1] or vim.fn.expand("~/bn-debug.log")
        local log_level = args_list[2] or "INFO"
        
        logger.enable(log_file, log_level)
        vim.notify(string.format("BN debug logging enabled: %s (level: %s)", log_file, log_level), vim.log.levels.INFO)
    end, {
        nargs = "*",
        desc = "Enable BN debug logging. Args: [log_file] [log_level]. Example: :BNDebugEnable ~/bn.log DEBUG"
    })

    vim.api.nvim_create_user_command("BNDebugDisable", function()
        logger.disable()
        vim.notify("BN debug logging disabled", vim.log.levels.INFO)
    end, {
        nargs = 0,
        desc = "Disable BN debug logging"
    })

    vim.api.nvim_create_user_command("BNDebugStatus", function()
        local status = logger.get_status()
        if status.enabled then
            vim.notify(string.format("BN debug logging: ENABLED\nFile: %s\nLevel: %s\nSession: %s\nBuffer lines: %d",
                status.log_file or "none", status.log_level, status.session_id or "none", status.buffer_lines),
                vim.log.levels.INFO)
        else
            vim.notify("BN debug logging: DISABLED", vim.log.levels.INFO)
        end
    end, {
        nargs = 0,
        desc = "Show BN debug logging status"
    })

    vim.api.nvim_create_user_command("BNDebugLogs", function(args)
        local args_str = args.args or ""
        local count = (args_str ~= "" and tonumber(args_str)) or 20
        local logs = logger.get_recent_logs(count)
        
        if #logs == 0 then
            vim.notify("No logs available", vim.log.levels.INFO)
            return
        end
        
        -- Create a new buffer to display logs
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(buf, "BN Debug Logs")

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
        desc = "Show recent BN debug logs. Args: [count] (default: 20)"
    })

    -- Clear history command
    vim.api.nvim_create_user_command("BNClearHistory", function(opts)
        local groups = require('buffer-nexus.groups')
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
            if require('buffer-nexus').refresh then
                require('buffer-nexus').refresh("clear_history")
            end
        end)
    end, {
        nargs = "?",
        desc = "Clear history for specific group or all groups (no args = all groups)"
    })

    -- Toggle cursor alignment
    vim.api.nvim_create_user_command("BNToggleCursorAlign", function()
        local config = require('buffer-nexus.config')
        config.settings.align_with_cursor = not config.settings.align_with_cursor
        local status = config.settings.align_with_cursor and "enabled" or "disabled"
        vim.notify(string.format("BN cursor alignment: %s", status), vim.log.levels.INFO)

        -- Refresh to apply the change
        require('buffer-nexus').refresh("cursor_align_toggle")
    end, {
        nargs = 0,
        desc = "Toggle cursor alignment for BN content"
    })

    -- Toggle adaptive width
    vim.api.nvim_create_user_command("BNToggleAdaptiveWidth", function()
        local config = require('buffer-nexus.config')
        config.settings.adaptive_width = not config.settings.adaptive_width
        local status = config.settings.adaptive_width and "enabled" or "disabled"
        vim.notify(string.format("BN adaptive width: %s", status), vim.log.levels.INFO)

        local state = require('buffer-nexus.state')
        local win_id = state.get_win_id()
        if win_id and vim.api.nvim_win_is_valid(win_id) then
            vim.api.nvim_win_set_option(win_id, 'winfixwidth', not config.settings.adaptive_width)
        end

        -- Refresh to apply the change
        require('buffer-nexus').refresh("adaptive_width_toggle")
    end, {
        nargs = 0,
        desc = "Toggle adaptive width for BN sidebar"
    })

    -- Set sidebar position
    vim.api.nvim_create_user_command("BNSetPosition", function(opts)
        local config = require('buffer-nexus.config')
        local position = opts.args
        if position == "" then
            vim.notify("Usage: BNSetPosition <left|right|top|bottom>", vim.log.levels.ERROR)
            return
        end

        if not config.validate_position(position) then
            vim.notify("Invalid position. Use: left, right, top, bottom", vim.log.levels.ERROR)
            return
        end

        local state = require('buffer-nexus.state')
        local was_open = state.is_sidebar_open()
        local previous_position = config.settings.position

        if was_open then
            local vbl = require('buffer-nexus')
            vbl.close_sidebar(previous_position)
        end

        if previous_position ~= position then
            local layout = require('buffer-nexus.layout')
            layout.clear_cached_size_on_axis_switch(previous_position, position, state)
        end

        config.settings.position = position
        vim.notify(string.format("BN position set to %s", position), vim.log.levels.INFO)

        if was_open then
            local vbl = require('buffer-nexus')
            vbl.toggle()
        end
    end, {
        nargs = 1,
        desc = "Set BN position (left/right/top/bottom)",
        complete = function()
            return { "left", "right", "top", "bottom" }
        end
    })

    -- Debug pick mode pick chars
    vim.api.nvim_create_user_command("BNDebugPickMode", function()
        logger.enable(vim.fn.expand("~/bn-pick-debug.log"), "DEBUG")
        vim.notify("BN pick mode debug logging enabled: ~/bn-pick-debug.log\nNow enter pick mode and check the log file", vim.log.levels.INFO)
    end, {
        nargs = 0,
        desc = "Enable debug logging for pick chars in pick mode"
    })

    -- Pick mode commands removed - using BNPick and BNPickClose defined earlier
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
