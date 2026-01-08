-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/group_picker.lua
-- Cross-picker current group buffer picker (telescope/snacks/fzf-lua/mini.pick)

local M = {}

local function get_valid_buffers(buffers)
    local valid_buffers = {}
    for _, buf_id in ipairs(buffers or {}) do
        if vim.api.nvim_buf_is_valid(buf_id) and vim.fn.buflisted(buf_id) == 1 then
            table.insert(valid_buffers, buf_id)
        end
    end
    return valid_buffers
end

local function format_group_label(group)
    local number = group and (group.display_number or group.id)
    local name = group and group.name or ""

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

local function switch_to_buffer_in_main_window(buffer_id)
    local state_module = require('buffer-nexus.state')
    local groups = require('buffer-nexus.groups')
    local sidebar_win = state_module.get_win_id()
    local placeholder_win = state_module.get_placeholder_win_id()
    local target_win = nil

    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
        if win_id ~= sidebar_win and win_id ~= placeholder_win and vim.api.nvim_win_is_valid(win_id) then
            local win_config = vim.api.nvim_win_get_config(win_id)
            if win_config.relative == "" then
                local win_buf = vim.api.nvim_win_get_buf(win_id)
                local buf_type = vim.api.nvim_buf_get_option(win_buf, 'buftype')
                local filetype = vim.api.nvim_buf_get_option(win_buf, 'filetype')
                if buf_type == '' and filetype ~= 'vertical-bufferline-placeholder' then
                    target_win = win_id
                    break
                end
            end
        end
    end

    if not target_win then
        vim.notify("No main window found", vim.log.levels.ERROR)
        return
    end

    groups.save_current_buffer_state()

    local ok, err = pcall(function()
        vim.api.nvim_set_current_win(target_win)
        vim.api.nvim_set_current_buf(buffer_id)
    end)

    if not ok then
        vim.notify("Error switching to buffer: " .. err, vim.log.levels.ERROR)
        return
    end

    local active_group = groups.get_active_group()
    if active_group then
        groups.sync_group_history_with_current(active_group.id, buffer_id)
        groups.restore_buffer_state_for_current_group(buffer_id)
    end
end

local function find_main_window_id()
    local state_module = require('buffer-nexus.state')
    local sidebar_win = state_module.get_win_id()
    local placeholder_win = state_module.get_placeholder_win_id()

    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
        if win_id ~= sidebar_win and win_id ~= placeholder_win and vim.api.nvim_win_is_valid(win_id) then
            local win_config = vim.api.nvim_win_get_config(win_id)
            if win_config.relative == "" then
                local win_buf = vim.api.nvim_win_get_buf(win_id)
                local buf_type = vim.api.nvim_buf_get_option(win_buf, 'buftype')
                local filetype = vim.api.nvim_buf_get_option(win_buf, 'filetype')
                if buf_type == '' and filetype ~= 'vertical-bufferline-placeholder' then
                    return win_id
                end
            end
        end
    end

    return nil
end

local function get_group_snapshot_by_id(groups, group_id)
    for _, group in ipairs(groups.get_all_groups()) do
        if group.id == group_id then
            return group
        end
    end
    return nil
end

local function get_group_snapshot_by_display_number(groups, display_number)
    local all = groups.get_all_groups()
    return all[display_number]
end

local function normalize_picker_preference(picker)
    if picker == nil or picker == "" then
        picker = "auto"
    end
    if type(picker) == "table" then
        local ordered = {}
        for _, name in ipairs(picker) do
            if type(name) == "string" and name ~= "" then
                table.insert(ordered, name)
            end
        end
        return ordered
    end
    if type(picker) == "string" then
        if picker == "auto" then
            return { "telescope", "snacks", "fzf-lua", "mini.pick" }
        end
        return { picker }
    end
    return { "telescope", "snacks", "fzf-lua", "mini.pick" }
end

local function build_group_buffers(groups, group_id)
    local group = nil
    if group_id then
        group = get_group_snapshot_by_id(groups, group_id)
    else
        local active_group = groups.get_active_group()
        group = active_group and get_group_snapshot_by_id(groups, active_group.id)
    end

    if not group then
        return nil, nil, "No active group found"
    end

    local buffers = get_valid_buffers(groups.get_group_buffers(group.id))
    if #buffers == 0 then
        return nil, group, "No buffers in current group"
    end

    return buffers, group, nil
end

local function apply_selection(groups, group_id, buffer_id)
    local active_group = groups.get_active_group()
    local target_win_id = find_main_window_id()

    if active_group and active_group.id == group_id then
        switch_to_buffer_in_main_window(buffer_id)
        return
    end

    local ok = groups.set_active_group(group_id, buffer_id, { target_win_id = target_win_id })
    if not ok then
        switch_to_buffer_in_main_window(buffer_id)
    end
end

local function open_telescope_picker(opts)
    local ok_telescope = pcall(require, "telescope")
    if not ok_telescope then
        return false
    end
    require('buffer-nexus.telescope_extension').current_group(opts)
    return true
end

local function open_snacks_picker(opts)
    local ok_snacks, snacks = pcall(require, "snacks")
    if not ok_snacks or not (snacks and snacks.picker) then
        return false
    end

    local groups = require('buffer-nexus.groups')
    local picker_util = snacks.picker.util
    local buffers, active_group, err = build_group_buffers(groups)
    if not buffers then
        if err then
            vim.notify(err, vim.log.levels.WARN)
        end
        return true
    end

    local selected_group_id = active_group.id

    local function build_items()
        local items = {}
        local current_buf = vim.api.nvim_get_current_buf()
        local alternate_buf = vim.fn.bufnr("#")

        for _, buf in ipairs(buffers) do
            local info = vim.fn.getbufinfo(buf)[1]
            local mark = vim.api.nvim_buf_get_mark(buf, '"')
            local name = vim.api.nvim_buf_get_name(buf)
            if name == "" then
                name = "[No Name]"
            end

            local flags = {
                buf == current_buf and "%" or (buf == alternate_buf and "#" or ""),
                info.hidden == 1 and "h" or (#(info.windows or {}) > 0) and "a" or "",
                vim.bo[buf].readonly and "=" or "",
                info.changed == 1 and "+" or "",
            }

            local item = {
                flags = table.concat(flags),
                buf = buf,
                name = name,
                buftype = vim.bo[buf].buftype,
                filetype = vim.bo[buf].filetype,
                file = name,
                info = info,
                pos = mark[1] ~= 0 and mark or { info.lnum, 0 },
            }
            if picker_util and picker_util.text then
                item.text = picker_util.text(item, { "buf", "name", "filetype", "buftype" })
            end
            table.insert(items, item)
        end
        return items
    end

    local function refresh_items(picker)
        local new_buffers, new_group, refresh_err = build_group_buffers(groups, selected_group_id)
        if not new_buffers then
            if refresh_err then
                vim.notify(refresh_err, vim.log.levels.WARN)
            end
            return false
        end
        buffers = new_buffers
        active_group = new_group
        picker.opts.items = build_items()
        picker.opts.title = "BN: " .. format_group_label(active_group) .. " (Alt-1..9)"
        picker:refresh()
        if picker.update_titles then
            picker:update_titles()
        end
        return true
    end

    local actions = {}
    for i = 1, 9 do
        local action_name = "bn_switch_group_" .. i
        actions[action_name] = function(picker)
            local target_group = get_group_snapshot_by_display_number(groups, i)
            if target_group then
                selected_group_id = target_group.id
                refresh_items(picker)
            end
        end
    end

    local function build_keymaps()
        local keys = {}
        for i = 1, 9 do
            keys[string.format("<M-%d>", i)] = { "bn_switch_group_" .. i, mode = { "n", "i" } }
        end
        return keys
    end

    local items = build_items()
    snacks.picker({
        title = "BN: " .. format_group_label(active_group) .. " (Alt-1..9)",
        items = items,
        format = "buffer",
        preview = "file",
        actions = actions,
        confirm = function(picker, item)
            picker:close()
            if item and item.buf then
                apply_selection(groups, selected_group_id, item.buf)
            end
        end,
        win = {
            input = { keys = build_keymaps() },
            list = { keys = build_keymaps() },
        },
    })
    return true
end

local function open_fzf_lua_picker(opts)
    local ok_fzf, fzf_lua = pcall(require, "fzf-lua")
    if not ok_fzf or not fzf_lua then
        return false
    end

    local groups = require('buffer-nexus.groups')
    local buffers, active_group, err = build_group_buffers(groups)
    if not buffers then
        if err then
            vim.notify(err, vim.log.levels.WARN)
        end
        return true
    end

    local function build_items()
        local items = {}
        for _, buf_id in ipairs(buffers) do
            local name = vim.api.nvim_buf_get_name(buf_id)
            if name == "" then
                name = "[No Name]"
            else
                name = vim.fn.fnamemodify(name, ":.")
            end
            table.insert(items, string.format("%d\t%s", buf_id, name))
        end
        return items
    end

    local selected_group_id = active_group.id

    local function open_with_items()
        local current_group = get_group_snapshot_by_id(groups, selected_group_id)
        local prompt = "BN " .. format_group_label(current_group or active_group) .. "> "
        local ok_actions, fzf_actions = pcall(require, "fzf-lua.actions")
        local function close_fzf(selected, opts)
            if ok_actions and fzf_actions and fzf_actions.close then
                pcall(fzf_actions.close, selected, opts)
            end
        end

        local function switch_group(display_number, selected, opts)
            close_fzf(selected, opts)
            local target_group = get_group_snapshot_by_display_number(groups, display_number)
            if not target_group then
                return
            end
            selected_group_id = target_group.id
            local new_buffers, new_group, refresh_err = build_group_buffers(groups, selected_group_id)
            if not new_buffers then
                if refresh_err then
                    vim.notify(refresh_err, vim.log.levels.WARN)
                end
                return
            end
            buffers = new_buffers
            active_group = new_group
            vim.schedule(open_with_items)
        end

        local actions = {
            ["default"] = function(selected)
                local line = selected and selected[1]
                if not line then
                    return
                end
                local bufnr = tonumber(line:match("^(%d+)"))
                if bufnr then
                    apply_selection(groups, selected_group_id, bufnr)
                end
            end,
        }

        for i = 1, 9 do
            actions["alt-" .. i] = function(selected, opts_inner)
                switch_group(i, selected, opts_inner)
            end
        end

        fzf_lua.fzf_exec(build_items(), {
            prompt = prompt,
            actions = actions,
        })
    end

    open_with_items()
    return true
end

local function open_mini_pick(opts)
    local ok_pick, pick = pcall(require, "mini.pick")
    if not ok_pick or not pick or not pick.start then
        return false
    end

    local groups = require('buffer-nexus.groups')
    local buffers, active_group, err = build_group_buffers(groups)
    if not buffers then
        if err then
            vim.notify(err, vim.log.levels.WARN)
        end
        return true
    end

    local function build_items()
        local items = {}
        for _, buf_id in ipairs(buffers) do
            local name = vim.api.nvim_buf_get_name(buf_id)
            if name == "" then
                name = "[No Name]"
            else
                name = vim.fn.fnamemodify(name, ":.")
            end
            table.insert(items, {
                text = string.format("%d %s", buf_id, name),
                bufnr = buf_id,
            })
        end
        return items
    end

    local selected_group_id = active_group.id

    local function refresh_items()
        local new_buffers, new_group, refresh_err = build_group_buffers(groups, selected_group_id)
        if not new_buffers then
            if refresh_err then
                vim.notify(refresh_err, vim.log.levels.WARN)
            end
            return
        end
        buffers = new_buffers
        active_group = new_group
        if pick.set_picker_items then
            pick.set_picker_items(build_items())
        end
        if pick.set_picker_opts then
            pick.set_picker_opts({
                source = { name = "BN: " .. format_group_label(active_group) .. " (Alt-1..9)" },
            })
        end
    end

    local mappings = {}
    for i = 1, 9 do
        mappings["bn_group_" .. i] = {
            char = string.format("<M-%d>", i),
            func = function()
                local target_group = get_group_snapshot_by_display_number(groups, i)
                if target_group then
                    selected_group_id = target_group.id
                    refresh_items()
                end
            end,
        }
    end

    pick.start({
        source = {
            name = "BN: " .. format_group_label(active_group) .. " (Alt-1..9)",
            items = build_items(),
            choose = function(item)
                if item and item.bufnr then
                    apply_selection(groups, selected_group_id, item.bufnr)
                end
            end,
        },
        mappings = mappings,
    })
    return true
end

function M.pick_current_group(opts)
    opts = opts or {}

    local config_module = require('buffer-nexus.config')
    local picker_setting = opts.picker
        or (config_module.settings.edit_mode and config_module.settings.edit_mode.picker)
        or "auto"
    local preferences = normalize_picker_preference(picker_setting)

    for _, name in ipairs(preferences) do
        if name == "none" then
            return false
        elseif name == "telescope" then
            if open_telescope_picker(opts) then
                return true
            end
        elseif name == "snacks" then
            if open_snacks_picker(opts) then
                return true
            end
        elseif name == "fzf-lua" then
            if open_fzf_lua_picker(opts) then
                return true
            end
        elseif name == "mini.pick" then
            if open_mini_pick(opts) then
                return true
            end
        end
    end

    vim.notify("No supported picker available", vim.log.levels.WARN)
    return false
end

return M
