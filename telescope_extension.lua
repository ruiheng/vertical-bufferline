-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/telescope_extension.lua
-- Telescope extension for picking buffers in the current group

local M = {}

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

local function get_valid_buffers(buffers)
    local valid_buffers = {}
    for _, buf_id in ipairs(buffers or {}) do
        if vim.api.nvim_buf_is_valid(buf_id) and vim.fn.buflisted(buf_id) == 1 then
            table.insert(valid_buffers, buf_id)
        end
    end
    return valid_buffers
end

local function build_entries(valid_buffers)
    local entries = {}
    for _, buf_id in ipairs(valid_buffers) do
        table.insert(entries, {
            bufnr = buf_id,
            info = vim.fn.getbufinfo(buf_id)[1],
            flag = buf_id == vim.fn.bufnr("") and "%" or (buf_id == vim.fn.bufnr("#") and "#" or " "),
        })
    end
    return entries
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

local function set_picker_statusline(picker, group)
    if not picker or not picker.results_win or not vim.api.nvim_win_is_valid(picker.results_win) then
        return
    end
    local statusline = "BN: " .. format_group_label(group) .. "  Alt-1..9 switch group"
    pcall(vim.api.nvim_win_set_option, picker.results_win, "statusline", statusline)
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

function M.current_group(opts)
    opts = opts or {}

    local groups = require('buffer-nexus.groups')
    local active_group = groups.get_active_group()
    if not active_group then
        vim.notify("No active group found", vim.log.levels.WARN)
        return
    end

    local buffers = groups.get_group_buffers(active_group.id)
    if not buffers or #buffers == 0 then
        vim.notify("No buffers in current group", vim.log.levels.WARN)
        return
    end

    local valid_buffers = get_valid_buffers(buffers)

    if #valid_buffers == 0 then
        vim.notify("No valid buffers in current group", vim.log.levels.WARN)
        return
    end

    local ok_pickers, pickers = pcall(require, "telescope.pickers")
    if not ok_pickers then
        vim.notify("telescope.nvim is not available", vim.log.levels.ERROR)
        return
    end

    local finders = require("telescope.finders")
    local make_entry = require("telescope.make_entry")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local function build_entry_maker()
        return opts.entry_maker or make_entry.gen_from_buffer(opts)
    end

    local max_bufnr = math.max(unpack(valid_buffers))
    opts.bufnr_width = opts.bufnr_width or #tostring(max_bufnr)
    local entries = build_entries(valid_buffers)

    local selected_group_id = active_group.id
    local selected_group_snapshot = get_group_snapshot_by_id(groups, selected_group_id) or active_group

    pickers.new(opts, {
        prompt_title = "BN: Current Group",
        finder = finders.new_table({
            results = entries,
            entry_maker = build_entry_maker(),
        }),
        previewer = conf.grep_previewer(opts),
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr)
            local picker = action_state.get_current_picker(prompt_bufnr)
            set_picker_statusline(picker, selected_group_snapshot)

            local function refresh_picker_for_selected_group()
                local current_group = get_group_snapshot_by_id(groups, selected_group_id)
                if not current_group then
                    return false
                end

                local current_buffers = groups.get_group_buffers(current_group.id) or {}
                local current_valid = get_valid_buffers(current_buffers)
                local max_current_bufnr = 0
                if #current_valid > 0 then
                    max_current_bufnr = math.max(unpack(current_valid))
                end
                opts.bufnr_width = math.max(#tostring(max_current_bufnr), 1)

                local new_finder = finders.new_table({
                    results = build_entries(current_valid),
                    entry_maker = build_entry_maker(),
                })

                if picker and picker.refresh then
                    local ok = pcall(picker.refresh, picker, new_finder, { reset_prompt = false })
                    if ok then
                        set_picker_statusline(picker, current_group)
                        return true
                    end
                end

                return false
            end

            local function switch_group(display_number)
                local target_group = get_group_snapshot_by_display_number(groups, display_number)
                if not target_group then
                    return
                end
                selected_group_id = target_group.id
                selected_group_snapshot = target_group
                local refreshed = refresh_picker_for_selected_group()
                if not refreshed then
                    actions.close(prompt_bufnr)
                    M.current_group(opts)
                end
            end

            for i = 1, 9 do
                local key = string.format("<M-%d>", i)
                vim.keymap.set("i", key, function() switch_group(i) end, { buffer = prompt_bufnr, nowait = true })
                vim.keymap.set("n", key, function() switch_group(i) end, { buffer = prompt_bufnr, nowait = true })
            end

            actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if selection and selection.bufnr then
                    apply_selection(groups, selected_group_id, selection.bufnr)
                end
            end)
            return true
        end,
    }):find()
end

local ok_telescope, telescope = pcall(require, "telescope")
if not ok_telescope then
    return M
end

return telescope.register_extension({
    exports = {
        current_group = M.current_group,
    },
})
