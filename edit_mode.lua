-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/edit_mode.lua
-- Editable group layout buffer

local M = {}

local api = vim.api

local groups = require('vertical-bufferline.groups')
local bufferline_integration = require('vertical-bufferline.bufferline-integration')
local state_module = require('vertical-bufferline.state')

local edit_state = {
    buf_id = nil,
    prev_buf_id = nil,
    prev_win_id = nil,
    win_id = nil,
    backdrop_win_id = nil,
    applying = false,
}

function M.apply_and_close(buf_id)
    if edit_state.applying then
        return
    end
    M.apply(buf_id)
    vim.schedule(function()
        if api.nvim_buf_is_valid(buf_id) then
            vim.cmd("bdelete")
        end
    end)
end

local function in_edit_buffer()
    return vim.bo.filetype == "vertical-bufferline-edit"
end

local function close_modal_windows()
    if edit_state.win_id and api.nvim_win_is_valid(edit_state.win_id) then
        api.nvim_win_close(edit_state.win_id, true)
    end
    if edit_state.backdrop_win_id and api.nvim_win_is_valid(edit_state.backdrop_win_id) then
        api.nvim_win_close(edit_state.backdrop_win_id, true)
    end
    edit_state.win_id = nil
    edit_state.backdrop_win_id = nil
end

local function is_modified_buffer(buf_id)
    if not api.nvim_buf_is_valid(buf_id) then
        return false
    end
    return api.nvim_get_option_value("modified", { buf = buf_id })
end

local function is_pinned_buffer(buf_id)
    if bufferline_integration.is_available() then
        local ok_groups, bufferline_groups = pcall(require, "bufferline.groups")
        if ok_groups and bufferline_groups and bufferline_groups._is_pinned then
            return bufferline_groups._is_pinned({ id = buf_id }) and true or false
        end
    end
    return state_module.is_buffer_pinned(buf_id)
end

local function format_buffer_line(buf_id)
    if not api.nvim_buf_is_valid(buf_id) then
        return nil
    end

    local name = api.nvim_buf_get_name(buf_id)
    local pin_suffix = is_pinned_buffer(buf_id) and " [pin]" or ""
    if name == "" then
        local buftype = api.nvim_get_option_value("buftype", { buf = buf_id })
        local filetype = api.nvim_get_option_value("filetype", { buf = buf_id })
        local label = buftype ~= "" and buftype or (filetype ~= "" and filetype or "nofile")
        return string.format("buf:%d%s  # %s", buf_id, pin_suffix, label)
    end

    return vim.fn.fnamemodify(name, ":p") .. pin_suffix
end

local function add_missing_modified_buffers(group_list)
    if #group_list == 0 then
        table.insert(group_list, { name = "Default", buffers = {} })
    end

    local present = {}
    for _, group in ipairs(group_list) do
        for _, buf_id in ipairs(group.buffers or {}) do
            present[buf_id] = true
        end
    end

    for _, buf_id in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_valid(buf_id) and is_modified_buffer(buf_id) and not present[buf_id] then
            table.insert(group_list[1].buffers, buf_id)
            present[buf_id] = true
        end
    end
end

--- Build edit lines and return them with initial cursor position
--- @return table lines, number initial_cursor_line
local function build_edit_lines()
    local lines = {
        "# Vertical Bufferline edit mode",
        "# CWD: " .. vim.fn.getcwd(),
        "# :w or :wq to apply, :q! to discard",
        "# Lines starting with # are comments",
        "",
    }

    local group_list = groups.get_all_groups()
    add_missing_modified_buffers(group_list)

    local initial_cursor_line = nil

    for i, group in ipairs(group_list) do
        local header = "[Group]"
        if group.name and group.name ~= "" then
            header = header .. " " .. group.name
        end
        table.insert(lines, header)

        for _, buf_id in ipairs(group.buffers or {}) do
            local line = format_buffer_line(buf_id)
            if line then
                table.insert(lines, line)
                -- Record first buffer line as initial cursor position
                if not initial_cursor_line then
                    initial_cursor_line = #lines
                end
            end
        end

        -- Only add empty line between groups, not after the last one
        if i < #group_list then
            table.insert(lines, "")
        end
    end

    -- Fallback: if no buffers found, place cursor after header comments
    if not initial_cursor_line then
        initial_cursor_line = #lines
    end

    return lines, initial_cursor_line
end

local function strip_comment(line)
    if line:match("^%s*#") then
        return "", true
    end
    local hash_pos = line:find("%s#")
    if hash_pos then
        line = line:sub(1, hash_pos - 1)
    end
    return vim.trim(line), false
end

local function normalize_path(path, cwd)
    if path == "" then
        return nil, nil
    end

    local expanded = vim.fn.expand(path)
    local abs = expanded
    if not expanded:match("^/") and not expanded:match("^%a:[/\\]") then
        abs = vim.fn.fnamemodify(cwd .. "/" .. expanded, ":p")
    else
        abs = vim.fn.fnamemodify(expanded, ":p")
    end

    local real = vim.loop.fs_realpath(abs)
    return real, abs
end

local function build_buffer_maps()
    local maps = {
        real = {},
        abs = {},
        raw = {},
    }

    for _, buf_id in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_valid(buf_id) then
            local name = api.nvim_buf_get_name(buf_id)
            if name ~= "" then
                local abs = vim.fn.fnamemodify(name, ":p")
                local real = vim.loop.fs_realpath(abs) or abs
                maps.real[real] = maps.real[real] or buf_id
                maps.abs[abs] = maps.abs[abs] or buf_id
                maps.raw[name] = maps.raw[name] or buf_id
            end
        end
    end

    return maps
end

local function parse_flags(raw, warnings, line_number)
    local path = raw
    local flags = {}
    local base, flag_str = raw:match("^(.*)%s%[(.-)%]%s*$")
    if base then
        path = vim.trim(base)
        for flag in flag_str:gmatch("%S+") do
            flags[flag] = true
        end
    end

    for flag, _ in pairs(flags) do
        if flag ~= "pin" then
            table.insert(warnings, string.format("Line %d: unknown flag '%s' ignored", line_number, flag))
        end
    end

    return path, flags
end

local function parse_lines(lines)
    local group_specs = {}
    local warnings = {}
    local current = nil

    for i, line in ipairs(lines) do
        local trimmed, is_comment = strip_comment(line)
        if is_comment or trimmed == "" then
            goto continue
        end

        local group_name = trimmed:match("^%[Group%]%s*(.*)$")
        if group_name ~= nil then
            local name = vim.trim(group_name)
            if group_name ~= "" and group_name ~= name then
                table.insert(warnings, string.format("Line %d: group name trimmed to '%s'", i, name))
            end
            current = { name = name, entries = {}, line = i }
            table.insert(group_specs, current)
        else
            if not current then
                table.insert(warnings, string.format("Line %d: buffer entry outside any group", i))
                goto continue
            end
            table.insert(current.entries, { raw = trimmed, line = i })
        end

        ::continue::
    end

    return group_specs, warnings
end

local function resolve_entry(path, buffer_maps, cwd, warnings, line_number)
    local buf_id = path:match("^buf:(%d+)$")
    if buf_id then
        local id = tonumber(buf_id)
        if id and api.nvim_buf_is_valid(id) then
            return id
        end
        table.insert(warnings, string.format("Line %d: invalid buffer id '%s'", line_number, path))
        return nil
    end

    local real, abs = normalize_path(path, cwd)
    local candidate = nil
    if real then
        candidate = buffer_maps.real[real]
    end
    candidate = candidate or (abs and buffer_maps.abs[abs]) or buffer_maps.raw[path]

    if not candidate then
        table.insert(warnings, string.format("Line %d: buffer path not found: %s", line_number, path))
    end

    return candidate
end

local function build_group_buffers(group_specs)
    local warnings = {}
    local buffer_maps = build_buffer_maps()
    local cwd = vim.fn.getcwd()
    local results = {}
    local pin_set = {}

    for _, spec in ipairs(group_specs) do
        local buffers = {}
        local seen = {}

        for _, entry in ipairs(spec.entries or {}) do
            local path, flags = parse_flags(entry.raw, warnings, entry.line)
            if path == "" then
                table.insert(warnings, string.format("Line %d: empty buffer entry", entry.line))
                goto continue
            end

            local buf_id = resolve_entry(path, buffer_maps, cwd, warnings, entry.line)
            if buf_id then
                if seen[buf_id] then
                    table.insert(warnings, string.format("Line %d: duplicate buffer in group '%s'", entry.line, spec.name))
                else
                    table.insert(buffers, buf_id)
                    seen[buf_id] = true
                end
                if flags.pin then
                    pin_set[buf_id] = true
                end
            end

            ::continue::
        end

        table.insert(results, { name = spec.name, buffers = buffers })
    end

    return results, warnings, pin_set
end

local function enforce_modified_buffers(group_specs, warnings)
    if #group_specs == 0 then
        table.insert(group_specs, { name = "Default", buffers = {} })
    end

    local present = {}
    for _, spec in ipairs(group_specs) do
        for _, buf_id in ipairs(spec.buffers or {}) do
            present[buf_id] = true
        end
    end

    for _, buf_id in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_valid(buf_id) and is_modified_buffer(buf_id) and not present[buf_id] then
            if buf_id == edit_state.buf_id then
                goto continue
            end
            local ft = api.nvim_get_option_value("filetype", { buf = buf_id })
            if ft == "vertical-bufferline-edit" then
                goto continue
            end
            table.insert(group_specs[1].buffers, buf_id)
            present[buf_id] = true
            table.insert(warnings, string.format("Buffer %d is modified and was not listed; added to first group", buf_id))
        end
        ::continue::
    end
end

local function notify_warnings(warnings)
    for _, message in ipairs(warnings) do
        vim.notify(message, vim.log.levels.WARN)
    end
end

local function apply_edit_buffer(buf_id)
    if edit_state.applying then
        return
    end
    edit_state.applying = true

    local lines = api.nvim_buf_get_lines(buf_id, 0, -1, false)
    local group_specs, warnings = parse_lines(lines)

    if #group_specs == 0 then
        table.insert(warnings, "No groups found; created a Default group")
        group_specs = { { name = "Default", entries = {} } }
    end

    local group_buffers, parse_warnings, pin_set = build_group_buffers(group_specs)
    for _, message in ipairs(parse_warnings) do
        table.insert(warnings, message)
    end

    enforce_modified_buffers(group_buffers, warnings)

    bufferline_integration.set_sync_target(nil)
    groups.replace_groups_from_edit(group_buffers)
    if pin_set then
        for _, buf_id in ipairs(api.nvim_list_bufs()) do
            if api.nvim_buf_is_valid(buf_id) then
                state_module.set_buffer_pinned(buf_id, pin_set[buf_id] == true)
            end
        end

        if bufferline_integration.is_available() then
            local ok_groups, bufferline_groups = pcall(require, "bufferline.groups")
            if ok_groups then
                for _, buf_id in ipairs(api.nvim_list_bufs()) do
                    if api.nvim_buf_is_valid(buf_id) then
                        local element = { id = buf_id }
                        if pin_set[buf_id] then
                            bufferline_groups.add_element("pinned", element)
                        else
                            bufferline_groups.remove_element("pinned", element)
                        end
                    end
                end
                local ok_ui, bufferline_ui = pcall(require, "bufferline.ui")
                if ok_ui and bufferline_ui.refresh then
                    bufferline_ui.refresh()
                end
            end
        end
    end

    local ok_prev_buf, prev_buf = pcall(api.nvim_buf_get_var, buf_id, "vbl_edit_prev_buf")
    local ok_prev_win, prev_win = pcall(api.nvim_buf_get_var, buf_id, "vbl_edit_prev_win")
    if not ok_prev_buf then
        prev_buf = nil
    end
    if not ok_prev_win then
        prev_win = nil
    end

    local target_group_id = nil
    local prev_buf_valid = prev_buf and api.nvim_buf_is_valid(prev_buf)
    if prev_buf_valid then
        local group = groups.find_buffer_group(prev_buf)
        if group then
            target_group_id = group.id
        end
    end

    if not target_group_id then
        local all_groups = groups.get_all_groups()
        if #all_groups > 0 then
            target_group_id = all_groups[1].id
        end
    end

    vim.schedule(function()
        if prev_win and api.nvim_win_is_valid(prev_win) then
            api.nvim_set_current_win(prev_win)
        end

        if target_group_id then
            local prev_hidden = vim.o.hidden
            vim.o.hidden = true
            pcall(groups.set_active_group, target_group_id, prev_buf_valid and prev_buf or nil)
            vim.o.hidden = prev_hidden
        end

        if prev_buf_valid then
            pcall(api.nvim_set_current_buf, prev_buf)
        end
    end)

    api.nvim_buf_set_option(buf_id, "modified", false)
    notify_warnings(warnings)

    edit_state.applying = false
end

local function setup_edit_buffer(buf_id)
    pcall(api.nvim_buf_set_name, buf_id, "vertical-bufferline://edit")
    vim.bo[buf_id].buftype = "acwrite"
    vim.bo[buf_id].bufhidden = "wipe"
    vim.bo[buf_id].swapfile = false
    vim.bo[buf_id].undofile = false
    vim.bo[buf_id].modifiable = true
    vim.bo[buf_id].filetype = "vertical-bufferline-edit"
    vim.bo[buf_id].buflisted = false

    local group = vim.api.nvim_create_augroup("VBufferLineEditModal", { clear = true })
    api.nvim_create_autocmd("WinLeave", {
        group = group,
        callback = function()
            local win = edit_state.win_id
            if win and api.nvim_win_is_valid(win) then
                vim.schedule(function()
                    if api.nvim_win_is_valid(win) then
                        api.nvim_set_current_win(win)
                    end
                end)
            end
        end,
    })

    api.nvim_create_autocmd("WinClosed", {
        group = group,
        pattern = "*",
        callback = function(ev)
            if edit_state.win_id and tostring(edit_state.win_id) == ev.match then
                close_modal_windows()
            end
        end,
    })

    api.nvim_create_autocmd("BufWriteCmd", {
        buffer = buf_id,
        callback = function()
            apply_edit_buffer(buf_id)
        end,
    })

    api.nvim_create_autocmd("BufWipeout", {
        buffer = buf_id,
        callback = function()
            if edit_state.buf_id == buf_id then
                edit_state.buf_id = nil
            end
            local prev_buf = edit_state.prev_buf_id
            local prev_win = edit_state.prev_win_id
            if prev_buf and api.nvim_buf_is_valid(prev_buf) then
                vim.schedule(function()
                    if prev_win and api.nvim_win_is_valid(prev_win) then
                        api.nvim_set_current_win(prev_win)
                    end
                    pcall(api.nvim_set_current_buf, prev_buf)
                end)
            end
        end,
    })
end

function M.open()
    if edit_state.buf_id and api.nvim_buf_is_valid(edit_state.buf_id) then
        if edit_state.win_id and api.nvim_win_is_valid(edit_state.win_id) then
            api.nvim_set_current_win(edit_state.win_id)
        else
            api.nvim_set_current_buf(edit_state.buf_id)
        end
        return
    end

    edit_state.prev_buf_id = api.nvim_get_current_buf()
    edit_state.prev_win_id = api.nvim_get_current_win()

    local buf_id = api.nvim_create_buf(false, true)
    edit_state.buf_id = buf_id

    setup_edit_buffer(buf_id)

    api.nvim_buf_set_var(buf_id, "vbl_edit_prev_buf", edit_state.prev_buf_id)
    api.nvim_buf_set_var(buf_id, "vbl_edit_prev_win", edit_state.prev_win_id)

    local lines, initial_cursor_line = build_edit_lines()
    api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

    local width = math.max(60, vim.o.columns - 4)
    local height = math.max(15, vim.o.lines - 4)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local backdrop_buf = api.nvim_create_buf(false, true)
    vim.bo[backdrop_buf].bufhidden = "wipe"
    edit_state.backdrop_win_id = api.nvim_open_win(backdrop_buf, false, {
        relative = "editor",
        row = 0,
        col = 0,
        width = vim.o.columns,
        height = vim.o.lines,
        style = "minimal",
        focusable = false,
        zindex = 40,
    })
    api.nvim_win_set_option(edit_state.backdrop_win_id, "winblend", 20)
    api.nvim_win_set_option(edit_state.backdrop_win_id, "winhl", "Normal:NormalFloat")

    edit_state.win_id = api.nvim_open_win(buf_id, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Vertical Bufferline Edit ",
        zindex = 50,
    })
    api.nvim_win_set_option(edit_state.win_id, "wrap", false)

    -- Move cursor to first buffer line
    api.nvim_win_set_cursor(edit_state.win_id, {initial_cursor_line, 0})
end

M.apply = apply_edit_buffer

return M
