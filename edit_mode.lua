-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/edit_mode.lua
-- Editable group layout buffer

local M = {}

local api = vim.api

local groups = require('vertical-bufferline.groups')
local bufferline_integration = require('vertical-bufferline.bufferline-integration')
local config_module = require('vertical-bufferline.config')
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
    local pin_suffix = ""
    if is_pinned_buffer(buf_id) then
        local pin_char = state_module.get_buffer_pin_char(buf_id)
        if pin_char and pin_char ~= "" then
            pin_suffix = " [pin=" .. pin_char .. "]"
        else
            pin_suffix = " [pin]"
        end
    end
    if name == "" then
        local buftype = api.nvim_get_option_value("buftype", { buf = buf_id })
        local filetype = api.nvim_get_option_value("filetype", { buf = buf_id })
        local label = buftype ~= "" and buftype or (filetype ~= "" and filetype or "nofile")
        return string.format("buf:%d%s  # %s", buf_id, pin_suffix, label)
    end

    -- Use relative path (to current directory) for better readability
    return vim.fn.fnamemodify(name, ":.") .. pin_suffix
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
        "# Lines starting with # are comments",
        "",
        "# Example:",
        "# [Group] Notes  # Group header, name optional",
        "# README.md  # Relative path",
        "# docs/guide.md [pin]  # Pin buffer",
        "# /home/user/projects/app/src/main.lua [pin=a]  # Absolute path with stable pick char",
        "",
        "# :w or :wq to apply, :q! to discard",
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

function M.foldexpr(lnum)
    local line = vim.fn.getline(lnum)
    if line:match("^%[Group%]") then
        return ">" .. lnum
    end

    if lnum == 1 then
        return 0
    end

    return "="
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

local function is_telescope_filetype(filetype)
    return type(filetype) == "string" and filetype:match("^Telescope") ~= nil
end

local function has_telescope_window()
    for _, win_id in ipairs(api.nvim_list_wins()) do
        if api.nvim_win_is_valid(win_id) then
            local buf_id = api.nvim_win_get_buf(win_id)
            local ft = api.nvim_get_option_value("filetype", { buf = buf_id })
            if is_telescope_filetype(ft) then
                return true
            end
        end
    end
    return false
end

local function is_under_dir(path, dir)
    if not path or not dir then
        return false
    end
    if path == dir then
        return true
    end
    local dir_with_sep = dir:match("[/\\]$") and dir or (dir .. "/")
    return path:sub(1, #dir_with_sep) == dir_with_sep
end

local function format_insert_path(path, cwd)
    local abs = vim.fn.fnamemodify(path, ":p")
    local abs_real = vim.loop.fs_realpath(abs) or abs
    local cwd_real = vim.loop.fs_realpath(cwd) or cwd
    if is_under_dir(abs_real, cwd_real) then
        return vim.fn.fnamemodify(abs, ":.")
    end
    return abs
end

local function list_files_under_cwd(cwd)
    local paths = vim.fn.globpath(cwd, "**/*", false, true)
    local files = {}
    for _, path in ipairs(paths) do
        local stat = vim.loop.fs_stat(path)
        if stat and stat.type == "file" then
            table.insert(files, path)
        end
    end
    table.sort(files)
    return files
end

local function insert_paths_into_buffer(paths, buf_id)
    if not paths or #paths == 0 then
        return
    end
    local cursor = api.nvim_win_get_cursor(0)
    local row = cursor[1]
    local line = api.nvim_buf_get_lines(buf_id, row - 1, row, false)[1] or ""
    if line == "" or line:match("^%s*#") then
        api.nvim_buf_set_lines(buf_id, row - 1, row, false, { paths[1] })
        if #paths > 1 then
            local rest = {}
            for i = 2, #paths do
                table.insert(rest, paths[i])
            end
            api.nvim_buf_set_lines(buf_id, row, row, false, rest)
        end
    else
        api.nvim_buf_set_lines(buf_id, row, row, false, paths)
    end
    api.nvim_win_set_cursor(0, { row + #paths - 1, 0 })
end

local function insert_paths_in_edit_buffer(paths, target_buf)
    if not paths or #paths == 0 then
        return
    end
    vim.schedule(function()
        local win = edit_state.win_id
        if win and api.nvim_win_is_valid(win) then
            api.nvim_set_current_win(win)
        end
        local buf = target_buf
        if not (buf and api.nvim_buf_is_valid(buf)) then
            buf = api.nvim_get_current_buf()
        end
        insert_paths_into_buffer(paths, buf)
    end)
end

function M.telescope_insert_paths()
    if not in_edit_buffer() then
        vim.notify("VBL edit mode is not active", vim.log.levels.WARN)
        return
    end

    local target_buf = api.nvim_get_current_buf()
    local ok_builtin, builtin = pcall(require, "telescope.builtin")
    if not ok_builtin then
        local ok_pick, pick = pcall(require, "mini.pick")
        if ok_pick and pick and pick.start then
            local cwd = vim.fn.getcwd()
            local items = list_files_under_cwd(cwd)
            if #items == 0 then
                vim.notify("No files found under current directory", vim.log.levels.WARN)
                return
            end
            local prev_ignorecase = vim.o.ignorecase
            local prev_smartcase = vim.o.smartcase
            vim.o.ignorecase = true
            vim.o.smartcase = false
            local restore_group = api.nvim_create_augroup("VBufferLineEditMiniPick", { clear = true })
            api.nvim_create_autocmd("User", {
                group = restore_group,
                pattern = "MiniPickStop",
                once = true,
                callback = function()
                    vim.o.ignorecase = prev_ignorecase
                    vim.o.smartcase = prev_smartcase
                end,
            })
            local function build_paths(entries)
                local paths = {}
                for _, entry in ipairs(entries or {}) do
                    if type(entry) == "string" then
                        table.insert(paths, format_insert_path(entry, cwd))
                    end
                end
                return paths
            end
            pick.start({
                source = {
                    name = "VBL edit: insert file (Tab to mark, Enter to insert)",
                    items = items,
                    choose = function(item)
                        insert_paths_in_edit_buffer(build_paths({ item }), target_buf)
                    end,
                    choose_marked = function(entries)
                        insert_paths_in_edit_buffer(build_paths(entries), target_buf)
                    end,
                },
            })
            return
        end
        vim.notify("Telescope or mini.pick not available", vim.log.levels.WARN)
        return
    end

    local ok_actions, actions = pcall(require, "telescope.actions")
    local ok_state, action_state = pcall(require, "telescope.actions.state")
    if not (ok_actions and ok_state) then
        vim.notify("Telescope actions not available", vim.log.levels.WARN)
        return
    end

    local cwd = vim.fn.getcwd()
    builtin.find_files({
        prompt_title = "VBL edit: insert file (Tab to multi-select, Enter to insert)",
        attach_mappings = function(prompt_bufnr, _)
            local function build_paths(entries)
                local paths = {}
                for _, entry in ipairs(entries) do
                    local entry_path = entry.path or entry.filename or entry.value or entry[1]
                    if entry_path and entry_path ~= "" then
                        table.insert(paths, format_insert_path(entry_path, cwd))
                    end
                end
                return paths
            end

            local function insert_selection()
                local picker = action_state.get_current_picker(prompt_bufnr)
                local multi = picker:get_multi_selection()
                local entries = {}
                if multi and #multi > 0 then
                    entries = multi
                else
                    local entry = action_state.get_selected_entry()
                    if entry then
                        entries = { entry }
                    end
                end

                actions.close(prompt_bufnr)
                local paths = build_paths(entries)
                if #paths > 0 then
                    insert_paths_in_edit_buffer(paths, target_buf)
                end
            end

            actions.select_default:replace(insert_selection)
            return true
        end,
    })
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
            if flag == "pin" then
                flags.pin = true
            else
                local pin_char = flag:match("^pin=(.+)$")
                if pin_char ~= nil then
                    flags.pin = true
                    if pin_char == "" then
                        table.insert(warnings, string.format("Line %d: pin flag requires a character", line_number))
                    elseif #pin_char ~= 1 then
                        table.insert(warnings, string.format("Line %d: pin flag must be a single character", line_number))
                    else
                        flags.pin_char = pin_char
                    end
                else
                    flags[flag] = true
                end
            end
        end
    end

    for flag, _ in pairs(flags) do
        if flag ~= "pin" and flag ~= "pin_char" then
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

    if not candidate and abs then
        local stat = vim.loop.fs_stat(abs)
        local buf_id = vim.fn.bufadd(abs)
        if buf_id and buf_id > 0 then
            local real_path = vim.loop.fs_realpath(abs) or abs
            buffer_maps.real[real_path] = buffer_maps.real[real_path] or buf_id
            buffer_maps.abs[abs] = buffer_maps.abs[abs] or buf_id
            buffer_maps.raw[path] = buffer_maps.raw[path] or buf_id
            if not stat then
                table.insert(warnings, string.format(
                    "Line %d: file not found on disk; created buffer for %s",
                    line_number,
                    path
                ))
            end
            return buf_id
        end
    end

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
    local pin_chars = {}
    local used_pin_chars = {}

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
                    if flags.pin_char then
                        if used_pin_chars[flags.pin_char] and used_pin_chars[flags.pin_char] ~= buf_id then
                            table.insert(warnings, string.format(
                                "Line %d: pin character '%s' already used; ignored",
                                entry.line,
                                flags.pin_char
                            ))
                        else
                            pin_chars[buf_id] = flags.pin_char
                            used_pin_chars[flags.pin_char] = buf_id
                        end
                    end
                end
            end

            ::continue::
        end

        table.insert(results, { name = spec.name, buffers = buffers })
    end

    return results, warnings, pin_set, pin_chars
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

    local group_buffers, parse_warnings, pin_set, pin_chars = build_group_buffers(group_specs)
    for _, message in ipairs(parse_warnings) do
        table.insert(warnings, message)
    end

    enforce_modified_buffers(group_buffers, warnings)

    bufferline_integration.set_sync_target(nil)
    groups.replace_groups_from_edit(group_buffers)
    if pin_set then
        for _, buf_id in ipairs(api.nvim_list_bufs()) do
            if api.nvim_buf_is_valid(buf_id) then
                local is_pinned = pin_set[buf_id] == true
                state_module.set_buffer_pinned(buf_id, is_pinned)
                if is_pinned then
                    state_module.set_buffer_pin_char(buf_id, pin_chars and pin_chars[buf_id] or nil)
                else
                    state_module.set_buffer_pin_char(buf_id, nil)
                end
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
    local prev_buf_in_group = false
    if prev_buf_valid then
        local group = groups.find_buffer_group(prev_buf)
        if group then
            target_group_id = group.id
            prev_buf_in_group = true
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

        if prev_buf_valid and prev_buf_in_group then
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
    local insert_path_key = config_module.settings.edit_mode
        and config_module.settings.edit_mode.insert_path_key
    if insert_path_key and insert_path_key ~= "" then
        vim.keymap.set({ "n", "i" }, insert_path_key, function()
            require('vertical-bufferline.edit_mode').telescope_insert_paths()
        end, { buffer = buf_id, silent = true, desc = "Insert file path (VBL edit)" })
    end

    local group = vim.api.nvim_create_augroup("VBufferLineEditModal", { clear = true })
    api.nvim_create_autocmd("WinLeave", {
        group = group,
        callback = function()
            local win = edit_state.win_id
            if win and api.nvim_win_is_valid(win) then
                vim.schedule(function()
                    if has_telescope_window() then
                        return
                    end
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
    api.nvim_buf_set_option(buf_id, "modified", false)

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
    api.nvim_win_set_option(edit_state.win_id, "foldmethod", "expr")
    api.nvim_win_set_option(edit_state.win_id, "foldexpr",
        "v:lua.require('vertical-bufferline.edit_mode').foldexpr(v:lnum)")
    api.nvim_win_set_option(edit_state.win_id, "foldlevel", 99)
    api.nvim_win_set_option(edit_state.win_id, "foldenable", true)

    -- Move cursor to first buffer line
    api.nvim_win_set_cursor(edit_state.win_id, {initial_cursor_line, 0})
end

function M.copy_to_register(register)
    local target_register = register and register ~= "" and register or '"'
    local lines = build_edit_lines()
    local filtered = {}
    for _, line in ipairs(lines) do
        if not line:match("^%s*#") then
            table.insert(filtered, line)
        end
    end
    vim.fn.setreg(target_register, table.concat(filtered, "\n"))
end

M.apply = apply_edit_buffer

return M
