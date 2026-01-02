-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/session.lua
-- Session persistence for vertical-bufferline groups

local M = {}

local api = vim.api
local config_module = require('vertical-bufferline.config')
local list_normal_windows
local saved_cmdheight = nil

local function apply_session_position(session_data)
    if not session_data or not session_data.position then
        return
    end

    if config_module.validate_position(session_data.position) then
        config_module.settings.position = session_data.position
    end
end

local function apply_session_sidebar_state(session_data)
    if not session_data then
        return
    end

    local state_module = require('vertical-bufferline.state')
    if session_data.last_width then
        state_module.set_last_width(session_data.last_width)
    end
    if session_data.last_height then
        state_module.set_last_height(session_data.last_height)
    end
end

local function detect_sidebar_position(win_id)
    if not win_id or not vim.api.nvim_win_is_valid(win_id) then
        return nil
    end

    local row, col = unpack(vim.api.nvim_win_get_position(win_id))
    local win_w = vim.api.nvim_win_get_width(win_id)
    local win_h = vim.api.nvim_win_get_height(win_id)
    local screen_w = vim.o.columns
    local screen_h = vim.o.lines

    local is_horizontal = win_h < win_w and win_h < (screen_h - 2)
    if is_horizontal then
        return row == 0 and "top" or "bottom"
    end

    return col == 0 and "left" or "right"
end

local function get_sidebar_windows()
    local windows = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
            local buf = vim.api.nvim_win_get_buf(win)
            if vim.api.nvim_buf_is_valid(buf)
                and vim.api.nvim_buf_get_option(buf, 'filetype') == 'vertical-bufferline' then
                table.insert(windows, {
                    win_id = win,
                    buf_id = buf,
                    position = detect_sidebar_position(win)
                })
            end
        end
    end
    return windows
end

local function pre_reconcile_sidebar_layout(session_data)
    if not session_data then
        return
    end

    local desired_position = session_data.position or config_module.settings.position
    local desired_open = session_data.sidebar_open ~= false

    local existing = get_sidebar_windows()
    if #existing == 0 then
        return
    end

    if not desired_open then
        for _, info in ipairs(existing) do
            pcall(vim.api.nvim_win_close, info.win_id, false)
        end
        return
    end

    local keep_win = nil
    for _, info in ipairs(existing) do
        if info.position == desired_position then
            keep_win = info.win_id
            break
        end
    end

    if not keep_win then
        local target = existing[1].win_id
        local current_win = vim.api.nvim_get_current_win()
        local ok = pcall(vim.api.nvim_set_current_win, target)
        if ok then
            local cmd = nil
            if desired_position == "top" then
                cmd = "wincmd K"
            elseif desired_position == "bottom" then
                cmd = "wincmd J"
            elseif desired_position == "left" then
                cmd = "wincmd H"
            elseif desired_position == "right" then
                cmd = "wincmd L"
            end
            if cmd then
                pcall(vim.cmd, cmd)
            end
        end
        if vim.api.nvim_win_is_valid(current_win) then
            pcall(vim.api.nvim_set_current_win, current_win)
        end
        keep_win = target
    end

    for _, info in ipairs(existing) do
        if info.win_id ~= keep_win then
            pcall(vim.api.nvim_win_close, info.win_id, false)
        end
    end
end

local function reconcile_sidebar_layout(session_data)
    if not session_data then
        return
    end

    local desired_position = session_data.position or config_module.settings.position
    local desired_open = session_data.sidebar_open ~= false

    local state_module = require('vertical-bufferline.state')
    local vbl = require('vertical-bufferline')
    local existing = get_sidebar_windows()
    local state_win = state_module.is_sidebar_open() and state_module.get_win_id() or nil
    local state_win_valid = state_win and vim.api.nvim_win_is_valid(state_win)

    if not desired_open then
        if state_win_valid then
            vbl.close_sidebar()
        end
        for _, info in ipairs(existing) do
            if not state_win_valid or info.win_id ~= state_win then
                pcall(vim.api.nvim_win_close, info.win_id, false)
            end
        end
        state_module.set_current_position(nil)
        return
    end

    local keep_win = nil
    if state_win_valid then
        local state_pos = detect_sidebar_position(state_win)
        if state_pos == desired_position then
            keep_win = state_win
        end
    end

    if not keep_win then
        for _, info in ipairs(existing) do
            if info.position == desired_position then
                keep_win = info.win_id
                break
            end
        end
    end

    if keep_win then
        for _, info in ipairs(existing) do
            if info.win_id ~= keep_win then
                pcall(vim.api.nvim_win_close, info.win_id, false)
            end
        end

        local buf_id = vim.api.nvim_win_get_buf(keep_win)
        local buf_ft = vim.api.nvim_buf_get_option(buf_id, 'filetype')
        if buf_ft == 'vertical-bufferline' then
            state_module.set_win_id(keep_win)
            state_module.set_buf_id(buf_id)
            state_module.set_sidebar_open(true)
            state_module.set_current_position(desired_position)
            return
        end

        pcall(vim.api.nvim_win_close, keep_win, false)
    else
        for _, info in ipairs(existing) do
            pcall(vim.api.nvim_win_close, info.win_id, false)
        end
    end

    vim.schedule(function()
        vbl.toggle()
    end)
end

-- Common session restore finalization
local function finalize_session_restore(session_data, opened_count, total_groups)
    local groups = require('vertical-bufferline.groups')
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    
    if groups.is_window_scope_enabled() then
        local windows = list_normal_windows()
        local current_win = api.nvim_get_current_win()

        for _, win_id in ipairs(windows) do
            if api.nvim_win_is_valid(win_id) then
                api.nvim_set_current_win(win_id)
                groups.activate_window_context(win_id, { seed_buffer_id = api.nvim_win_get_buf(win_id) })
                local all_groups = groups.get_all_groups()
                for _, group in ipairs(all_groups) do
                    groups.update_group_position_info(group.id, {})
                    if not group.history then
                        group.history = {}
                    end
                    if group.last_current_buffer == nil then
                        group.last_current_buffer = nil
                    end
                end
            end
        end

        if api.nvim_win_is_valid(current_win) then
            api.nvim_set_current_win(current_win)
            groups.activate_window_context(current_win, { seed_buffer_id = api.nvim_win_get_buf(current_win) })
        end

        return
    end

    -- Clear all position info from all groups after session restore
    local all_groups = groups.get_all_groups()
    for _, group in ipairs(all_groups) do
        groups.update_group_position_info(group.id, {})
        
        -- Initialize history fields for backward compatibility with old sessions
        if not group.history then
            group.history = {}
        end
        if group.last_current_buffer == nil then
            group.last_current_buffer = nil
        end
    end
    
    -- Final sync to bufferline
    local logger = require('vertical-bufferline.logger')
    local active_group = groups.get_active_group()
    
    logger.info("session", "finalizing session restore", {
        active_group_id = active_group and active_group.id or "none",
        active_group_current_buffer = active_group and active_group.current_buffer or "none",
        current_vim_buffer = vim.api.nvim_get_current_buf()
    })
    
    if active_group then
        bufferline_integration.set_bufferline_buffers(active_group.buffers)
        bufferline_integration.set_sync_target(active_group.id)

        -- Switch to the group's current buffer if available, otherwise first buffer
        local target_buf = nil
        if active_group.current_buffer and vim.api.nvim_buf_is_valid(active_group.current_buffer) and vim.api.nvim_buf_is_loaded(active_group.current_buffer) then
            target_buf = active_group.current_buffer
            logger.info("session", "using group's saved current buffer", {
                buf_id = target_buf,
                buf_name = vim.api.nvim_buf_get_name(target_buf)
            })
        elseif #active_group.buffers > 0 then
            for _, buf_id in ipairs(active_group.buffers) do
                if vim.api.nvim_buf_is_valid(buf_id) and vim.api.nvim_buf_is_loaded(buf_id) then
                    target_buf = buf_id
                    logger.info("session", "using first available buffer from group", {
                        buf_id = target_buf,
                        buf_name = vim.api.nvim_buf_get_name(target_buf)
                    })
                    break
                end
            end
        end
        
        if target_buf then
            local old_buf = vim.api.nvim_get_current_buf()
            logger.info("session", "switching to target buffer", {
                from_buf = old_buf,
                to_buf = target_buf,
                to_buf_name = vim.api.nvim_buf_get_name(target_buf)
            })
            vim.api.nvim_set_current_buf(target_buf)

            -- Clean up initial empty buffer and its windows (created by nvim -S Session.vim)
            vim.schedule(function()
                if vim.api.nvim_buf_is_valid(old_buf) and old_buf ~= target_buf then
                    local old_buf_name = vim.api.nvim_buf_get_name(old_buf)
                    local old_buf_modified = vim.api.nvim_buf_get_option(old_buf, 'modified')
                    -- Only delete if it's unnamed, unmodified, and not in any group
                    if old_buf_name == "" and not old_buf_modified then
                        local is_in_group = false
                        for _, group in ipairs(groups.get_all_groups()) do
                            if vim.tbl_contains(group.buffers, old_buf) then
                                is_in_group = true
                                break
                            end
                        end
                        if not is_in_group then
                            logger.info("session", "cleaning up initial empty buffer and windows", { buf_id = old_buf })

                            -- First, close all windows showing this buffer (except sidebar)
                            local vbl = require('vertical-bufferline')
                            local sidebar_win = vbl.state and vbl.state.is_sidebar_open() and vbl.state.get_win_id() or nil
                            local current_win = vim.api.nvim_get_current_win()

                            for _, win in ipairs(vim.api.nvim_list_wins()) do
                                if vim.api.nvim_win_is_valid(win) and win ~= sidebar_win then
                                    local win_buf = vim.api.nvim_win_get_buf(win)
                                    if win_buf == old_buf then
                                        -- This window is showing the empty buffer
                                        if win == current_win then
                                            -- Don't close current window, just switch its buffer
                                            if vim.api.nvim_buf_is_valid(target_buf) then
                                                pcall(vim.api.nvim_win_set_buf, win, target_buf)
                                            end
                                        else
                                            -- Close this extra window
                                            logger.info("session", "closing window with empty buffer", {
                                                win_id = win,
                                                buf_id = old_buf
                                            })
                                            pcall(vim.api.nvim_win_close, win, false)
                                        end
                                    end
                                end
                            end

                            -- Then delete the buffer
                            pcall(vim.api.nvim_buf_delete, old_buf, { force = false })
                        end
                    end
                end
            end)
        else
            logger.warn("session", "no valid target buffer found", {
                group_buffers = active_group.buffers,
                group_current_buffer = active_group.current_buffer
            })
        end
    else
        -- Fallback: ensure sync is enabled even if no active group
        bufferline_integration.set_sync_target("default")
    end

    -- Refresh UI
    vim.schedule(function()
        -- Clean up extra windows that vim session may have created
        -- Native vim session saves all windows including VBL sidebar,
        -- so we might end up with duplicate windows after restoration
        vim.defer_fn(function()
            local state_module = require('vertical-bufferline.state')
            local all_wins = vim.api.nvim_list_wins()
            local sidebar_win = state_module.is_sidebar_open() and state_module.get_win_id() or nil
            local main_wins = {}

            -- Find all non-sidebar windows with their buffer info
            for _, win in ipairs(all_wins) do
                if vim.api.nvim_win_is_valid(win) and win ~= sidebar_win then
                    local win_config = vim.api.nvim_win_get_config(win)
                    -- Only consider normal windows (not floating)
                    if win_config.relative == "" then
                        local buf = vim.api.nvim_win_get_buf(win)
                        local buf_name = vim.api.nvim_buf_get_name(buf)
                        table.insert(main_wins, {
                            win_id = win,
                            buf_id = buf,
                            buf_name = buf_name,
                            is_empty = (buf_name == "")
                        })
                    end
                end
            end

            logger.info("session", "cleanup extra windows", {
                total_windows = #all_wins,
                sidebar_win = sidebar_win,
                main_windows_count = #main_wins
            })

            -- If we have more than 1 main window, keep the best one
            if #main_wins > 1 then
                logger.warn("session", "found extra windows from vim session", {
                    extra_count = #main_wins - 1,
                    windows = main_wins
                })

                -- Find the best window to keep (prefer non-empty buffer)
                local keep_win = nil
                local keep_idx = nil

                -- First priority: window with active group's current buffer
                if active_group and active_group.current_buffer then
                    for i, win_info in ipairs(main_wins) do
                        if win_info.buf_id == active_group.current_buffer then
                            keep_win = win_info.win_id
                            keep_idx = i
                            break
                        end
                    end
                end

                -- Second priority: any window with non-empty buffer
                if not keep_win then
                    for i, win_info in ipairs(main_wins) do
                        if not win_info.is_empty then
                            keep_win = win_info.win_id
                            keep_idx = i
                            break
                        end
                    end
                end

                -- Fallback: keep first window
                if not keep_win then
                    keep_win = main_wins[1].win_id
                    keep_idx = 1
                end

                logger.info("session", "keeping window", {
                    win_id = keep_win,
                    buf_name = main_wins[keep_idx].buf_name
                })

                -- Close all other windows
                for i, win_info in ipairs(main_wins) do
                    if i ~= keep_idx then
                        logger.info("session", "closing extra window", {
                            win_id = win_info.win_id,
                            buf_name = win_info.buf_name
                        })
                        pcall(vim.api.nvim_win_close, win_info.win_id, false)
                    end
                end
            end

            reconcile_sidebar_layout(session_data)

            local vbl = require('vertical-bufferline')
            if vbl.state and vbl.state.is_sidebar_open then
                vbl.refresh()
            end
        end, 100) -- Delay to allow session windows to settle
    end)

    if saved_cmdheight ~= nil then
        vim.defer_fn(function()
            if vim.o.cmdheight ~= saved_cmdheight then
                vim.o.cmdheight = saved_cmdheight
            end
            saved_cmdheight = nil
        end, 150)
    end
end

-- Convert buffer path to relative path if it's under current working directory
local function normalize_buffer_path(buffer_path)
    local cwd = vim.fn.getcwd()
    if buffer_path:sub(1, #cwd) == cwd then
        local relative = buffer_path:sub(#cwd + 2) -- +2 to skip the trailing slash
        return relative ~= "" and relative or buffer_path
    end
    return buffer_path
end

list_normal_windows = function()
    local state_module = require('vertical-bufferline.state')
    local sidebar_win = state_module.get_win_id()
    local windows = {}

    for _, win_id in ipairs(api.nvim_list_wins()) do
        if api.nvim_win_is_valid(win_id) and win_id ~= sidebar_win then
            local win_config = api.nvim_win_get_config(win_id)
            if win_config.relative == "" then
                table.insert(windows, win_id)
            end
        end
    end

    return windows
end

local function each_session_group(session_data, fn)
    if session_data.window_groups and type(session_data.window_groups) == "table" then
        for _, window_group in ipairs(session_data.window_groups) do
            for _, group_data in ipairs(window_group.groups or {}) do
                fn(group_data, window_group)
            end
        end
    else
        for _, group_data in ipairs(session_data.groups or {}) do
            fn(group_data, nil)
        end
    end
end

local function count_session_groups(session_data)
    local count = 0
    each_session_group(session_data, function()
        count = count + 1
    end)
    return count
end

local function build_group_data_list(groups_module, active_group_id, current_window_buf)
    local all_groups = groups_module.get_all_groups()
    local results = {}

    for _, group in ipairs(all_groups) do
        local group_data = {
            id = group.id,
            name = group.name,
            created_at = group.created_at,
            color = group.color,
            buffers = {},
            current_buffer_path = nil,
            history = {}
        }

        local current_group_buffers = groups_module.get_group_buffers(group.id)
        for _, buffer_id in ipairs(current_group_buffers) do
            if api.nvim_buf_is_valid(buffer_id) then
                local buffer_path = api.nvim_buf_get_name(buffer_id)
                if buffer_path ~= "" then
                    local normalized_path = normalize_buffer_path(buffer_path)
                    table.insert(group_data.buffers, {
                        path = normalized_path
                    })
                end
            end
        end

        local current_buf_for_group = nil
        if group.id == active_group_id then
            if current_window_buf and vim.tbl_contains(current_group_buffers, current_window_buf) then
                current_buf_for_group = current_window_buf
            end
        end

        if not current_buf_for_group then
            if group.current_buffer and api.nvim_buf_is_valid(group.current_buffer)
               and vim.tbl_contains(current_group_buffers, group.current_buffer) then
                current_buf_for_group = group.current_buffer
            end
        end

        if current_buf_for_group then
            local current_buffer_path = api.nvim_buf_get_name(current_buf_for_group)
            if current_buffer_path ~= "" then
                group_data.current_buffer_path = normalize_buffer_path(current_buffer_path)
            end
        end

        if group.history then
            for _, buffer_id in ipairs(group.history) do
                if api.nvim_buf_is_valid(buffer_id) then
                    local buffer_path = api.nvim_buf_get_name(buffer_id)
                    if buffer_path ~= "" then
                        table.insert(group_data.history, normalize_buffer_path(buffer_path))
                    end
                end
            end
        end

        table.insert(results, group_data)
    end

    return results
end

-- Convert relative path back to absolute path
local function expand_buffer_path(buffer_path)
    if buffer_path:sub(1, 1) == "/" then
        return buffer_path -- Already absolute
    else
        return vim.fn.getcwd() .. "/" .. buffer_path
    end
end

local function get_pinned_buffers()
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    if bufferline_integration.is_available() then
        local pinned = vim.g.BufferlinePinnedBuffers
        if not pinned or pinned == "" then
            return {}
        end

        local result = {}
        for _, path in ipairs(vim.split(pinned, ",", { plain = true, trimempty = true })) do
            local normalized = normalize_buffer_path(path)
            if normalized ~= "" then
                table.insert(result, normalized)
            end
        end

        return result
    end

    local state_module = require('vertical-bufferline.state')
    local result = {}
    for _, buf_id in ipairs(state_module.get_pinned_buffers()) do
        if api.nvim_buf_is_valid(buf_id) then
            local buffer_path = api.nvim_buf_get_name(buf_id)
            if buffer_path ~= "" then
                local normalized = normalize_buffer_path(buffer_path)
                if normalized ~= "" then
                    table.insert(result, normalized)
                end
            end
        end
    end

    return result
end

-- Find existing buffers without creating new ones (safe for session restore)
-- Helper function to find buffer by matching filename patterns
local function find_buffer_by_path_patterns(target_path)
    local logger = require('vertical-bufferline.logger')
    local all_bufs = vim.api.nvim_list_bufs()
    local target_filename = vim.fn.fnamemodify(target_path, ":t")  -- Get filename only
    
    logger.debug("session", "searching for buffer with pattern matching", {
        target_path = target_path,
        target_filename = target_filename
    })
    
    for _, buf_id in ipairs(all_bufs) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            local buf_name = vim.api.nvim_buf_get_name(buf_id)
            if buf_name ~= "" then
                -- Try exact match first
                if buf_name == target_path then
                    logger.debug("session", "found exact path match", {
                        buf_id = buf_id,
                        buf_name = buf_name
                    })
                    return buf_id
                end
                
                -- Try filename match for cases where paths don't match exactly
                local buf_filename = vim.fn.fnamemodify(buf_name, ":t")
                if buf_filename == target_filename then
                    -- Additional check: ensure the relative path suffix matches
                    local target_suffix = target_path:match(".*/(.+)") or target_path
                    local buf_suffix = buf_name:match(".*/(.+)") or buf_name
                    
                    logger.debug("session", "checking filename match", {
                        buf_id = buf_id,
                        buf_name = buf_name,
                        target_suffix = target_suffix,
                        buf_suffix = buf_suffix
                    })
                    
                    if target_suffix == buf_suffix then
                        logger.info("session", "found suffix match", {
                            buf_id = buf_id,
                            buf_name = buf_name,
                            matched_suffix = target_suffix
                        })
                        return buf_id
                    elseif buf_name:find(target_suffix:gsub("([%.%-%+%*%?%[%]%^%$%(%)%%])", "%%%1") .. "$") then
                        logger.info("session", "found pattern match", {
                            buf_id = buf_id,
                            buf_name = buf_name,
                            pattern = target_suffix
                        })
                        return buf_id
                    end
                end
            end
        end
    end
    
    logger.warn("session", "no buffer found for path", {
        target_path = target_path,
        target_filename = target_filename
    })
    return nil
end

local function find_existing_buffers(session_data)
    local buffer_mappings = {} -- file_path -> buffer_id
    local found_count = 0

    -- Get all existing buffers
    local all_bufs = vim.api.nvim_list_bufs()
    local existing_buf_names = {}
    for _, buf_id in ipairs(all_bufs) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            local buf_name = vim.api.nvim_buf_get_name(buf_id)
            if buf_name ~= "" then
                table.insert(existing_buf_names, buf_name)
            end
        end
    end

    -- Try to match session data buffers with existing buffers
    each_session_group(session_data, function(group_data)
        for _, buffer_info in ipairs(group_data.buffers or {}) do
            local file_path = expand_buffer_path(buffer_info.path)
            
            -- Try exact path match first
            local existing_buf = vim.fn.bufnr(file_path, false)
            if existing_buf > 0 and vim.api.nvim_buf_is_valid(existing_buf) then
                buffer_mappings[file_path] = existing_buf
                found_count = found_count + 1
            else
                -- If exact match fails, try pattern matching
                existing_buf = find_buffer_by_path_patterns(file_path)
                if existing_buf then
                    buffer_mappings[file_path] = existing_buf
                    found_count = found_count + 1
                end
            end
        end
        
        -- Also look for history files
        for _, history_path in ipairs(group_data.history or {}) do
            local file_path = expand_buffer_path(history_path)
            
            -- Try exact path match first
            local existing_buf = vim.fn.bufnr(file_path, false)
            if existing_buf > 0 and vim.api.nvim_buf_is_valid(existing_buf) then
                buffer_mappings[file_path] = existing_buf
                found_count = found_count + 1
            else
                -- If exact match fails, try pattern matching
                existing_buf = find_buffer_by_path_patterns(file_path)
                if existing_buf then
                    buffer_mappings[file_path] = existing_buf
                    found_count = found_count + 1
                end
            end
        end
    end)

    -- If session data contains buffers not found in existing buffers,
    -- safely preload them (without complex async logic)
    local preloaded_count = 0
    each_session_group(session_data, function(group_data)
        for _, buffer_info in ipairs(group_data.buffers or {}) do
            local file_path = expand_buffer_path(buffer_info.path)
            
            -- If not found in existing buffers, try to preload safely
            if not buffer_mappings[file_path] and vim.fn.filereadable(file_path) == 1 then
                -- Use safe buffer creation without triggering swap file dialogs
                local buf_id = vim.fn.bufnr(file_path, true)  -- Create if not exists
                
                if vim.api.nvim_buf_is_valid(buf_id) then
                    -- Set buffer properties safely
                    pcall(vim.api.nvim_buf_set_option, buf_id, 'buflisted', true)
                    pcall(vim.api.nvim_buf_set_option, buf_id, 'buftype', '')
                    
                    -- Load buffer content if not already loaded
                    if not vim.api.nvim_buf_is_loaded(buf_id) then
                        pcall(vim.fn.bufload, buf_id)
                    end
                    
                    buffer_mappings[file_path] = buf_id
                    found_count = found_count + 1
                    preloaded_count = preloaded_count + 1
                end
            end
        end
        
        -- Also preload history files if not found
        for _, history_path in ipairs(group_data.history or {}) do
            local file_path = expand_buffer_path(history_path)
            
            -- If not found in existing buffers, try to preload safely
            if not buffer_mappings[file_path] and vim.fn.filereadable(file_path) == 1 then
                -- Use safe buffer creation without triggering swap file dialogs
                local buf_id = vim.fn.bufnr(file_path, true)  -- Create if not exists
                
                if vim.api.nvim_buf_is_valid(buf_id) then
                    -- Set buffer properties safely
                    pcall(vim.api.nvim_buf_set_option, buf_id, 'buflisted', true)
                    pcall(vim.api.nvim_buf_set_option, buf_id, 'buftype', '')
                    
                    -- Load buffer content if not already loaded
                    if not vim.api.nvim_buf_is_loaded(buf_id) then
                        pcall(vim.fn.bufload, buf_id)
                    end
                    
                    buffer_mappings[file_path] = buf_id
                    found_count = found_count + 1
                    preloaded_count = preloaded_count + 1
                end
            end
        end
    end)
    
    -- Fallback: if no session buffers but existing buffers, add them to mapping
    if found_count == 0 and #existing_buf_names > 0 then
        for _, buf_name in ipairs(existing_buf_names) do
            local buf_id = vim.fn.bufnr(buf_name, false)
            if buf_id > 0 and vim.api.nvim_buf_is_valid(buf_id) then
                buffer_mappings[buf_name] = buf_id
                found_count = found_count + 1
            end
        end
    end
    
    
    return buffer_mappings
end

local function rebuild_groups_from_data(group_block, buffer_mappings)
    local groups = require('vertical-bufferline.groups')
    local group_list = group_block.groups or {}
    local active_group_id = group_block.active_group_id

    -- Step 1: Clear existing groups using proper API
    local existing_groups = groups.get_all_groups()
    for _, group in ipairs(existing_groups) do
        if group.id ~= "default" then
            groups.delete_group(group.id)
        end
    end

    -- Step 2: Clear default group buffers
    local default_group = groups.find_group_by_id("default")
    if default_group then
        for _, buf_id in ipairs(vim.deepcopy(default_group.buffers)) do
            groups.remove_buffer_from_group(buf_id, "default")
        end
    end

    -- Step 3: Recreate groups from session data using proper API
    local group_id_mapping = {}

    for _, group_data in ipairs(group_list) do
        local new_group_id

        if group_data.id == "default" then
            new_group_id = "default"
            if group_data.name and group_data.name ~= "" then
                groups.rename_group("default", group_data.name)
            end
        else
            new_group_id = groups.create_group(group_data.name, group_data.color)
            group_id_mapping[group_data.id] = new_group_id
        end

        for _, buffer_info in ipairs(group_data.buffers or {}) do
            local file_path = expand_buffer_path(buffer_info.path)
            local buf_id = buffer_mappings[file_path]

            if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
                groups.add_buffer_to_group(buf_id, new_group_id)
            end
        end
        
        if group_data.current_buffer_path then
            local current_buffer_file_path = expand_buffer_path(group_data.current_buffer_path)
            local current_buf_id = buffer_mappings[current_buffer_file_path]

            if current_buf_id and vim.api.nvim_buf_is_valid(current_buf_id) then
                local restored_group = groups.find_group_by_id(new_group_id)
                if restored_group then
                    restored_group.current_buffer = current_buf_id
                end
            end
        end
        
        local restored_group = groups.find_group_by_id(new_group_id)
        if restored_group and group_data.history then
            restored_group.history = {}
            for _, history_path in ipairs(group_data.history) do
                local history_file_path = expand_buffer_path(history_path)
                local history_buf_id = buffer_mappings[history_file_path]
                if history_buf_id and vim.api.nvim_buf_is_valid(history_buf_id) then
                    table.insert(restored_group.history, history_buf_id)
                end
            end
        end
    end

    -- Step 4: Set active group using proper API
    local target_active_group_id = active_group_id or "default"
    if target_active_group_id ~= "default" and group_id_mapping[target_active_group_id] then
        target_active_group_id = group_id_mapping[target_active_group_id]
    end

    local target_group = groups.find_group_by_id(target_active_group_id)
    if target_group then
        groups.set_active_group(target_active_group_id)
        
        if target_group.current_buffer and vim.api.nvim_buf_is_valid(target_group.current_buffer)
           and vim.tbl_contains(target_group.buffers, target_group.current_buffer) then
            vim.schedule(function()
                vim.api.nvim_set_current_buf(target_group.current_buffer)
            end)
        end
    else
        groups.set_active_group("default")
    end
    
    -- Step 5: Fallback for unmapped existing buffers - add them to default group
    local fallback_group = groups.find_group_by_id("default")
    if fallback_group then
        for file_path, buf_id in pairs(buffer_mappings) do
            if vim.api.nvim_buf_is_valid(buf_id) then
                local buffer_group = groups.find_buffer_group(buf_id)
                if not buffer_group then
                    groups.add_buffer_to_group(buf_id, "default")
                end
            end
        end
    end
end

local function apply_pinned_buffers(session_data, buffer_mappings)
    if not session_data.pinned_buffers or type(session_data.pinned_buffers) ~= "table" then
        return
    end

    local pin_set = {}
    for _, pinned_path in ipairs(session_data.pinned_buffers) do
        local expanded = expand_buffer_path(pinned_path)
        local buf_id = buffer_mappings[expanded]
        if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
            pin_set[buf_id] = true
        end
    end

    if session_data.pinned_pick_chars and type(session_data.pinned_pick_chars) == "table" then
        for pinned_path, pick_char in pairs(session_data.pinned_pick_chars) do
            if type(pick_char) == "string" and pick_char ~= "" then
                local expanded = expand_buffer_path(pinned_path)
                local buf_id = buffer_mappings[expanded]
                if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
                    pin_set[buf_id] = true
                end
            end
        end
    end

    local state_module = require('vertical-bufferline.state')
    for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            state_module.set_buffer_pinned(buf_id, pin_set[buf_id] == true)
        end
    end

    if session_data.pinned_pick_chars and type(session_data.pinned_pick_chars) == "table" then
        local pin_char_by_buf = {}
        for pinned_path, pick_char in pairs(session_data.pinned_pick_chars) do
            if type(pick_char) == "string" and pick_char ~= "" then
                local expanded = expand_buffer_path(pinned_path)
                local buf_id = buffer_mappings[expanded]
                if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
                    pin_char_by_buf[buf_id] = pick_char
                end
            end
        end

        for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(buf_id) then
                if pin_set[buf_id] and pin_char_by_buf[buf_id] then
                    state_module.set_buffer_pin_char(buf_id, pin_char_by_buf[buf_id])
                else
                    state_module.set_buffer_pin_char(buf_id, nil)
                end
            end
        end
    end

    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    if bufferline_integration.is_available() then
        local ok_groups, bufferline_groups = pcall(require, "bufferline.groups")
        if ok_groups then
            for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_valid(buf_id) then
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

local function map_window_groups_to_windows(session_data, windows)
    local mapping = {}
    local used = {}
    local by_path = {}

    for _, win_id in ipairs(windows) do
        local buf_id = api.nvim_win_get_buf(win_id)
        if api.nvim_buf_is_valid(buf_id) then
            local buf_name = api.nvim_buf_get_name(buf_id)
            if buf_name ~= "" then
                by_path[normalize_buffer_path(buf_name)] = win_id
            end
        end
    end

    for idx, window_group in ipairs(session_data.window_groups or {}) do
        local match = nil
        if window_group.window_buffer_path then
            match = by_path[window_group.window_buffer_path]
        end
        if match and not used[match] then
            mapping[idx] = match
            used[match] = true
        end
    end

    local remaining = {}
    for _, win_id in ipairs(windows) do
        if not used[win_id] then
            table.insert(remaining, win_id)
        end
    end

    local rem_index = 1
    for idx, _ in ipairs(session_data.window_groups or {}) do
        if not mapping[idx] then
            mapping[idx] = remaining[rem_index]
            rem_index = rem_index + 1
        end
    end

    return mapping
end

local function restore_groups_from_session(session_data, buffer_mappings)
    local groups = require('vertical-bufferline.groups')

    if groups.is_window_scope_enabled() and session_data.window_groups then
        groups.reset_window_contexts()
        local windows = list_normal_windows()
        local mapping = map_window_groups_to_windows(session_data, windows)
        local current_win = api.nvim_get_current_win()

        for idx, window_group in ipairs(session_data.window_groups) do
            local win_id = mapping[idx]
            if win_id and api.nvim_win_is_valid(win_id) then
                api.nvim_set_current_win(win_id)
                groups.activate_window_context(win_id, { seed_buffer_id = api.nvim_win_get_buf(win_id) })
                rebuild_groups_from_data(window_group, buffer_mappings)
            end
        end

        if api.nvim_win_is_valid(current_win) then
            api.nvim_set_current_win(current_win)
            groups.activate_window_context(current_win, { seed_buffer_id = api.nvim_win_get_buf(current_win) })
        end
    else
        rebuild_groups_from_data({
            groups = session_data.groups or {},
            active_group_id = session_data.active_group_id,
        }, buffer_mappings)
    end

    apply_pinned_buffers(session_data, buffer_mappings)
end

-- ============================================================================
-- Global Variable Session Integration (for Neovim native sessions)
-- ============================================================================

-- State collection for global variable serialization
local function collect_current_state()
    local groups = require('vertical-bufferline.groups')
    local state_module = require('vertical-bufferline.state')
    local active_group_id = groups.get_active_group_id()
    local current_buf = api.nvim_get_current_buf()
    local window_groups = nil

    if groups.is_window_scope_enabled() then
        window_groups = {}
        local windows = list_normal_windows()
        local current_win = api.nvim_get_current_win()

        for _, win_id in ipairs(windows) do
            groups.activate_window_context(win_id, { seed_buffer_id = api.nvim_win_get_buf(win_id) })
            local win_active_group = groups.get_active_group_id()
            local win_buf = api.nvim_win_get_buf(win_id)
            local win_buf_path = ""
            if api.nvim_buf_is_valid(win_buf) then
                win_buf_path = api.nvim_buf_get_name(win_buf)
            end

            table.insert(window_groups, {
                window_buffer_path = win_buf_path ~= "" and normalize_buffer_path(win_buf_path) or nil,
                active_group_id = win_active_group,
                groups = build_group_data_list(groups, win_active_group, win_buf),
            })
        end

        if api.nvim_win_is_valid(current_win) then
            groups.activate_window_context(current_win, { seed_buffer_id = api.nvim_win_get_buf(current_win) })
        end

        active_group_id = groups.get_active_group_id()
        current_buf = api.nvim_get_current_buf()
    end
    
    -- Prepare session data for global-variable serialization
    local session_data = {
        version = "1.0",
        timestamp = os.time(),
        active_group_id = active_group_id,
        position = config_module.settings.position,
        sidebar_open = state_module.is_sidebar_open(),
        last_width = state_module.get_last_width(),
        last_height = state_module.get_last_height(),
        groups = {},
        window_groups = window_groups,
        pinned_buffers = {},
        pinned_pick_chars = {}
    }
    
    session_data.groups = build_group_data_list(groups, active_group_id, current_buf)

    session_data.pinned_buffers = get_pinned_buffers()
    local pinned_pick_chars = state_module.get_pinned_pick_chars()
    for buf_id, pick_char in pairs(pinned_pick_chars or {}) do
        if api.nvim_buf_is_valid(buf_id) and type(pick_char) == "string" and pick_char ~= "" then
            local buffer_path = api.nvim_buf_get_name(buf_id)
            if buffer_path ~= "" then
                local normalized = normalize_buffer_path(buffer_path)
                if normalized ~= "" then
                    session_data.pinned_pick_chars[normalized] = pick_char
                end
            end
        end
    end
    
    return session_data
end

-- State restoration from global variable (simplified synchronous version)
local function restore_state_from_global()
    if not vim.g.VerticalBufferlineSession then
        return false
    end

    local success, session_data = pcall(vim.json.decode, vim.g.VerticalBufferlineSession)
    if not success then
        vim.notify("Failed to decode VBL session data", vim.log.levels.ERROR)
        return false
    end
    
    
    -- Validate session data
    local has_groups = session_data.groups and type(session_data.groups) == "table"
    local has_window_groups = session_data.window_groups and type(session_data.window_groups) == "table"
    if not has_groups and not has_window_groups then
        vim.notify("Invalid VBL session data format", vim.log.levels.ERROR)
        return false
    end

    session_data.groups = session_data.groups or {}

    apply_session_position(session_data)
    apply_session_sidebar_state(session_data)
    
    -- Prevent duplicate execution
    if _G._vbl_session_restore_in_progress then
        return false
    end
    _G._vbl_session_restore_in_progress = true

    -- Synchronous execution - remove vim.schedule() wrapper
    local state_module = require('vertical-bufferline.state')
    local groups = require('vertical-bufferline.groups')
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    saved_cmdheight = vim.o.cmdheight

    -- CRITICAL: Disable auto-add during session restore to prevent BufEnter from interfering
    state_module.set_session_loading(true)
    groups.disable_auto_add()

    -- Show progress notification
    vim.notify("Restoring VBL state...", vim.log.levels.INFO)

    -- Temporarily disable bufferline sync during loading
    bufferline_integration.set_sync_target(nil)

    -- Wrap in pcall to ensure cleanup always happens
    local success, err = pcall(function()
        -- Find existing buffers that were already loaded by Vim session
        local buffer_mappings = find_existing_buffers(session_data)

        -- Basic group restoration with existing buffers
        restore_groups_from_session(session_data, buffer_mappings)

        -- Common finalization
        finalize_session_restore(session_data, vim.tbl_count(buffer_mappings), count_session_groups(session_data))
    end)

    -- Always re-enable auto-add and reset state, even if there was an error
    groups.enable_auto_add()
    state_module.set_session_loading(false)
    _G._vbl_session_restore_in_progress = false

    if not success then
        vim.notify("VBL state restore error: " .. tostring(err), vim.log.levels.ERROR)
        return false
    end

    vim.notify(string.format("VBL state restored (%d groups)", count_session_groups(session_data)), vim.log.levels.INFO)
    return true
end

-- Auto-serialization timer
local auto_serialize_timer = nil
local last_state_hash = nil

-- Buffer visibility state management for session save/restore
local saved_buflisted_states = {}

-- Setup complete buffer visibility for session save
local function setup_complete_buffer_visibility_for_session()
    local groups = require('vertical-bufferline.groups')
    local all_groups = groups.get_all_groups()
    
    -- Clear previous state
    saved_buflisted_states = {}
    
    local total_buffers = 0
    local made_visible = 0
    
    -- Save current buflisted state for all buffers and make all group buffers visible
    for _, group in ipairs(all_groups) do
        local group_buffers = groups.get_group_buffers(group.id)
        for _, buf_id in ipairs(group_buffers) do
            if vim.api.nvim_buf_is_valid(buf_id) then
                total_buffers = total_buffers + 1
                -- Save current state
                local was_listed = vim.api.nvim_buf_get_option(buf_id, 'buflisted')
                saved_buflisted_states[buf_id] = was_listed
                
                -- Make buffer visible for session save
                if not was_listed then
                    pcall(vim.api.nvim_buf_set_option, buf_id, 'buflisted', true)
                    made_visible = made_visible + 1
                end
            end
        end
    end
    
end

-- Restore original buffer visibility after session save
local function restore_original_buffer_visibility()
    -- Restore original buflisted states
    for buf_id, was_listed in pairs(saved_buflisted_states) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            pcall(vim.api.nvim_buf_set_option, buf_id, 'buflisted', was_listed)
        end
    end
    
    -- Clear saved states
    saved_buflisted_states = {}
    
    -- Restore current active group's visibility through bufferline integration
    local groups = require('vertical-bufferline.groups')
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    local active_group = groups.get_active_group()
    
    if active_group then
        -- Restore bufferline display for current active group
        bufferline_integration.set_bufferline_buffers(active_group.buffers)
    end
end

local function serialize_if_changed()
    local current_state = collect_current_state()
    local state_json = vim.json.encode(current_state)
    local current_hash = vim.fn.sha256(state_json)
    
    -- Only update global variable if state actually changed
    if current_hash ~= last_state_hash then
        vim.g.VerticalBufferlineSession = state_json
        last_state_hash = current_hash
    end
end

local function start_auto_serialize()
    if auto_serialize_timer then
        auto_serialize_timer:stop()
        auto_serialize_timer:close()
    end
    
    auto_serialize_timer = vim.loop.new_timer()
    auto_serialize_timer:start(0, 3000, vim.schedule_wrap(serialize_if_changed)) -- Every 3 seconds
end

local function stop_auto_serialize()
    if auto_serialize_timer then
        auto_serialize_timer:stop()
        auto_serialize_timer:close()
        auto_serialize_timer = nil
    end
end

-- Setup session integration
local function setup_session_integration()
    local config_module = require('vertical-bufferline.config')
    
    -- Get session config with fallback defaults
    local session_config = config_module.settings.session or {
        mini_sessions_integration = true,
        auto_serialize = true,     -- Re-enable now that race condition is fixed
        auto_restore_prompt = false -- Keep this disabled for now
    }
    
    -- Event-based integration for mini.sessions
    if session_config.mini_sessions_integration then
        -- Save state before session write
        vim.api.nvim_create_autocmd("User", {
            pattern = "SessionSavePre",
            callback = function()
                -- Stop auto-serialization during session save
                stop_auto_serialize()

                -- CRITICAL: Remove 'blank' from sessionoptions to prevent saving empty buffers
                -- (like the VBL sidebar which becomes empty when special buffers can't be saved)
                vim.g._vbl_saved_sessionoptions = vim.o.sessionoptions
                vim.opt.sessionoptions:remove('blank')

                -- Save all buffer visibility states and temporarily make all group buffers visible
                setup_complete_buffer_visibility_for_session()

                -- Save VBL state
                vim.g.VerticalBufferlineSession = vim.json.encode(collect_current_state())
            end,
            desc = "Auto-save VBL state and setup complete buffer visibility for mini.sessions"
        })
        
        -- Restore state after session write
        vim.api.nvim_create_autocmd("User", {
            pattern = "SessionSavePost",
            callback = function()
                -- Restore original buffer visibility states
                restore_original_buffer_visibility()

                -- Restore original sessionoptions
                if vim.g._vbl_saved_sessionoptions then
                    vim.o.sessionoptions = vim.g._vbl_saved_sessionoptions
                    vim.g._vbl_saved_sessionoptions = nil
                end

                -- Restart auto-serialization if enabled
                if session_config.auto_serialize then
                    start_auto_serialize()
                end
            end,
            desc = "Restore buffer visibility after session save"
        })
        
        -- Restore state after session load with delay to ensure buffers are loaded
        vim.api.nvim_create_autocmd("SessionLoadPost", {
            callback = function()
                -- Only respond to real session loads, not loadview commands
                -- v:this_session is only set during actual session loading
                if not vim.v.this_session or vim.v.this_session == "" then
                    return -- This is from loadview or similar, ignore
                end

                -- CRITICAL: Save original session data IMMEDIATELY before anything can overwrite it
                local original_session_data = vim.g.VerticalBufferlineSession

                -- IMPORTANT: Stop any running auto-serialization timer IMMEDIATELY
                stop_auto_serialize()

                if original_session_data then
                    local ok, decoded = pcall(vim.json.decode, original_session_data)
                    if ok and decoded then
                        pre_reconcile_sidebar_layout(decoded)
                    end
                end

                vim.defer_fn(function()
                    -- Restore the original data in case it was overwritten
                    vim.g.VerticalBufferlineSession = original_session_data

                    if vim.g.VerticalBufferlineSession and not _G._vbl_session_restore_completed then
                        restore_state_from_global()
                        _G._vbl_session_restore_completed = true

                        -- NOW safe to start auto-serialize after restore is complete
                        if session_config.auto_serialize then
                            start_auto_serialize()
                        end
                    end
                end, 50)
            end,
            desc = "Auto-restore VBL state for mini.sessions"
        })
    end
    
    -- Auto-serialization for native mksession
    if session_config.auto_serialize then
        -- CRITICAL: Delay auto-serialize start to give SessionLoadPost a chance to run first
        -- If there's a session being restored, SessionLoadPost will start auto-serialize after restoration
        -- If there's no session, we start it after a delay to avoid race conditions
        vim.defer_fn(function()
            -- Only start if not already started by SessionLoadPost
            if not auto_serialize_timer then
                start_auto_serialize()
            end
        end, 200)  -- 200ms delay: SessionLoadPost has 50ms delay, so this gives it 150ms buffer

        -- NOTE: Removed immediate serialization on every state change
        -- The 3-second auto-serialize timer is sufficient and avoids lag when creating groups
    end
    
    -- Manual restore command
    vim.api.nvim_create_user_command("VBufferLineRestoreSession", function()
        if vim.g.VerticalBufferlineSession then
            -- Decode session data to show preview
            local success, session_data = pcall(vim.json.decode, vim.g.VerticalBufferlineSession)
            local preview = ""
            if success and (session_data.groups or session_data.window_groups) then
                local group_count = count_session_groups(session_data)
                local buffer_count = 0
                each_session_group(session_data, function(group_data)
                    buffer_count = buffer_count + #(group_data.buffers or {})
                end)
                preview = string.format(" (%d groups, %d buffers)", group_count, buffer_count)
            end
            
            local choice = vim.fn.confirm(
                "Restore VBL state from session?" .. preview,
                "&Yes\n&No", 1
            )
            if choice == 1 then
                restore_state_from_global()
            end
        else
            vim.notify("No VBL session data found", vim.log.levels.WARN)
        end
    end, { desc = "Restore VBL state from session" })
    
    -- Commands to control auto-restore prompt
    vim.api.nvim_create_user_command("VBufferLineEnableAutoPrompt", function()
        M.enable_auto_restore_prompt()
    end, { desc = "Enable auto-restore prompt after sourcing session files" })
    
    vim.api.nvim_create_user_command("VBufferLineDisableAutoPrompt", function()
        M.disable_auto_restore_prompt()
    end, { desc = "Disable auto-restore prompt after sourcing session files" })

end

-- Enable/disable auto restore prompt
function M.enable_auto_restore_prompt()
    local config_module = require('vertical-bufferline.config')
    if config_module.settings.session then
        config_module.settings.session.auto_restore_prompt = true
        vim.notify("VBL auto-restore prompt enabled", vim.log.levels.INFO)
    end
end

function M.disable_auto_restore_prompt()
    local config_module = require('vertical-bufferline.config')
    if config_module.settings.session then
        config_module.settings.session.auto_restore_prompt = false
        vim.notify("VBL auto-restore prompt disabled", vim.log.levels.INFO)
    end
end

-- Public API for global variable session integration
M.collect_current_state = collect_current_state
M.restore_state_from_global = restore_state_from_global
M.start_auto_serialize = start_auto_serialize
M.stop_auto_serialize = stop_auto_serialize
M.setup_session_integration = setup_session_integration

return M
