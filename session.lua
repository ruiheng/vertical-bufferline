-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/session.lua
-- Session persistence for vertical-bufferline groups

local M = {}

local api = vim.api
local config_module = require('vertical-bufferline.config')

-- Session configuration
local config = {
    -- Session file location - use a specific directory for our sessions
    session_dir = vim.fn.stdpath("data") .. "/vertical-bufferline-sessions",
    -- Auto-save on exit
    auto_save = true,
    -- Auto-load on startup (if session exists for current working directory)
    auto_load = true,
    -- Session file naming strategy
    session_name_strategy = "cwd_hash", -- "cwd_hash" or "cwd_path" or "manual"
}

-- Auto-save debounce timer
local auto_save_timer = nil
local saved_cmdheight = nil

local function apply_session_position(session_data)
    if not session_data or not session_data.position then
        return
    end

    if config_module.validate_position(session_data.position) then
        config_module.settings.position = session_data.position
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

local function reopen_sidebar_for_position(session_data)
    if not session_data then
        return
    end

    if not session_data.position then
        return
    end

    local state_module = require('vertical-bufferline.state')
    local win_id = nil
    local sidebar_open = state_module.is_sidebar_open()
    if sidebar_open then
        win_id = state_module.get_win_id()
    else
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_is_valid(win) then
                local buf = vim.api.nvim_win_get_buf(win)
                if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_option(buf, 'filetype') == 'vertical-bufferline' then
                    win_id = win
                    break
                end
            end
        end
    end

    if not win_id then
        return
    end

    local current_position = state_module.get_current_position()
    if current_position == session_data.position then
        return
    end

    local actual_position = detect_sidebar_position(win_id)
    if actual_position == session_data.position then
        state_module.set_current_position(actual_position)
        return
    end

    vim.defer_fn(function()
        local vbl = require('vertical-bufferline')
        if sidebar_open then
            vbl.close_sidebar()
            vim.schedule(function()
                vbl.toggle()
            end)
        else
            pcall(vim.api.nvim_win_close, win_id, false)
            vim.schedule(function()
                vbl.toggle()
            end)
        end
    end, 30)
end

-- Common session restore finalization
local function finalize_session_restore(session_data, opened_count, total_groups)
    local groups = require('vertical-bufferline.groups')
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    

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
        local vbl = require('vertical-bufferline')
        if vbl.state and vbl.state.is_sidebar_open then
            vbl.refresh()
        end

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
        end, 100) -- Delay a bit more to ensure VBL sidebar is fully opened
    end)

    reopen_sidebar_for_position(session_data)

    if saved_cmdheight ~= nil then
        vim.defer_fn(function()
            if vim.o.cmdheight ~= saved_cmdheight then
                vim.o.cmdheight = saved_cmdheight
            end
            saved_cmdheight = nil
        end, 150)
    end
end

-- Ensure session directory exists
local function ensure_session_dir()
    local session_dir = config.session_dir
    if vim.fn.isdirectory(session_dir) == 0 then
        vim.fn.mkdir(session_dir, "p")
    end
end

-- Generate session filename based on current working directory
local function get_session_filename()
    if config.session_name_strategy == "cwd_hash" then
        -- Use hash of current working directory for filename
        local cwd = vim.fn.getcwd()
        local hash = vim.fn.sha256(cwd)
        return config.session_dir .. "/" .. hash:sub(1, 16) .. ".json"
    elseif config.session_name_strategy == "cwd_path" then
        -- Use sanitized path as filename
        local cwd = vim.fn.getcwd()
        local sanitized = cwd:gsub("/", "_"):gsub("\\", "_"):gsub(":", "")
        return config.session_dir .. "/" .. sanitized .. ".json"
    else
        -- Manual naming - default fallback
        return config.session_dir .. "/default.json"
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

--- Save current groups configuration to session file
--- @param filename string Optional filename to save to
--- @return boolean success
function M.save_session(filename)
    filename = filename or get_session_filename()
    ensure_session_dir()

    local groups = require('vertical-bufferline.groups')
    local all_groups = groups.get_all_groups()
    local active_group_id = groups.get_active_group_id()

    -- Prepare session data
    local session_data = {
        version = "1.0",
        timestamp = os.time(),
        working_directory = vim.fn.getcwd(),
        active_group_id = active_group_id,
        position = config_module.settings.position,
        groups = {},
        pinned_buffers = {}
    }

    -- Convert groups data for persistence
    for _, group in ipairs(all_groups) do
        local group_data = {
            id = group.id,
            name = group.name,
            created_at = group.created_at,
            color = group.color,
            buffers = {},
            current_buffer_path = nil,  -- Will be set below if valid
            history = {}  -- Will be set below if valid
        }

        -- Save buffer information using the cleaned group buffers
        -- This ensures we save the current runtime state, not stale data
        local current_group_buffers = groups.get_group_buffers(group.id)
        for _, buffer_id in ipairs(current_group_buffers) do
            if api.nvim_buf_is_valid(buffer_id) then
                local buffer_path = api.nvim_buf_get_name(buffer_id)
                if buffer_path ~= "" then
                    -- Normalize paths to be relative when possible
                    local normalized_path = normalize_buffer_path(buffer_path)
                    table.insert(group_data.buffers, {
                        path = normalized_path
                    })
                end
            end
        end

        -- Save current buffer for this group
        -- If this is the active group, use the actual current buffer
        -- Otherwise, use the group's recorded current buffer
        local current_buf_for_group = nil
        if group.id == active_group_id then
            -- For active group, use the actual current buffer
            local actual_current_buf = api.nvim_get_current_buf()
            if vim.tbl_contains(current_group_buffers, actual_current_buf) then
                current_buf_for_group = actual_current_buf
            end
        else
            -- For other groups, use the recorded current buffer if valid
            if group.current_buffer and api.nvim_buf_is_valid(group.current_buffer) and 
               vim.tbl_contains(current_group_buffers, group.current_buffer) then
                current_buf_for_group = group.current_buffer
            end
        end
        
        if current_buf_for_group then
            local current_buffer_path = api.nvim_buf_get_name(current_buf_for_group)
            if current_buffer_path ~= "" then
                group_data.current_buffer_path = normalize_buffer_path(current_buffer_path)
            end
        end

        -- Save history for this group (always save history field, even if empty)
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
        -- Note: group_data.history is always initialized as {} above, so it will be saved even if empty

        table.insert(session_data.groups, group_data)
    end

    session_data.pinned_buffers = get_pinned_buffers()

    -- Write session file
    local success, err = pcall(function()
        local file = io.open(filename, "w")
        if not file then
            error("Cannot open session file for writing: " .. filename)
        end

        local json_str = vim.json.encode(session_data)
        file:write(json_str)
        file:close()
    end)

    if success then
        vim.notify("Session saved: " .. vim.fn.fnamemodify(filename, ":t"), vim.log.levels.INFO)
        return true
    else
        vim.notify("Failed to save session: " .. (err or "unknown error"), vim.log.levels.ERROR)
        return false
    end
end

-- Check if a buffer path is in session data
local function is_buffer_in_session(buffer_path, session_data)
    for _, group_data in ipairs(session_data.groups) do
        for _, buffer_info in ipairs(group_data.buffers or {}) do
            local session_path = expand_buffer_path(buffer_info.path)
            if session_path == buffer_path then
                return true
            end
        end
    end
    return false
end

-- Handle existing buffers before session loading
local function handle_existing_buffers(session_data)
    local groups = require('vertical-bufferline.groups')
    local existing_buffers = vim.api.nvim_list_bufs()
    local handled_buffers = {}

    for _, buf_id in ipairs(existing_buffers) do
        if vim.api.nvim_buf_is_valid(buf_id) and vim.api.nvim_buf_get_option(buf_id, 'buflisted') then
            local buf_name = vim.api.nvim_buf_get_name(buf_id)
            local buftype = vim.api.nvim_buf_get_option(buf_id, 'buftype')

            -- Only process normal file buffers (skip special buffers like plugin buffers, etc.)
            if buftype == '' then
                if buf_name == "" then
                    -- [No Name] buffer
                    if vim.api.nvim_buf_get_option(buf_id, 'modified') then
                        -- Has modifications, keep in Default group
                        groups.add_buffer_to_group(buf_id, "default")
                        table.insert(handled_buffers, buf_id)
                    else
                        -- Empty [No Name], close it
                        pcall(vim.api.nvim_buf_delete, buf_id, {})
                    end
                else
                    -- Named buffer
                    if is_buffer_in_session(buf_name, session_data) then
                        -- Buffer is in session, keep it and mark as handled
                        table.insert(handled_buffers, buf_id)
                    else
                        -- Buffer not in session
                        if vim.api.nvim_buf_get_option(buf_id, 'modified') then
                            -- Has modifications, keep in Default group
                            groups.add_buffer_to_group(buf_id, "default")
                            table.insert(handled_buffers, buf_id)
                        else
                            -- No modifications, close it
                            pcall(vim.api.nvim_buf_delete, buf_id, {})
                        end
                    end
                end
            end
        end
    end

    return handled_buffers
end

-- Collect all unique file paths from session data
local function collect_session_files(session_data)
    local all_files = {}
    local unique_files = {}

    for _, group_data in ipairs(session_data.groups) do
        for _, buffer_info in ipairs(group_data.buffers or {}) do
            local file_path = expand_buffer_path(buffer_info.path)
            if not unique_files[file_path] then
                unique_files[file_path] = true
                table.insert(all_files, file_path)
            end
        end
    end

    return all_files
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
    for _, group_data in ipairs(session_data.groups) do
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
    end

    -- If session data contains buffers not found in existing buffers,
    -- safely preload them (without complex async logic)
    local preloaded_count = 0
    for _, group_data in ipairs(session_data.groups) do
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
    end
    
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

-- Open all session files and return buffer mappings
local function open_session_files(session_files)
    local buffer_mappings = {} -- file_path -> buffer_id
    local opened_count = 0

    for _, file_path in ipairs(session_files) do
        if vim.fn.filereadable(file_path) == 1 then
            -- Check if buffer already exists
            local existing_buf = vim.fn.bufnr(file_path, false)
            if existing_buf > 0 and vim.api.nvim_buf_is_valid(existing_buf) then
                -- Buffer already exists, reuse it
                buffer_mappings[file_path] = existing_buf
            else
                -- Create new buffer
                local buf_id = vim.fn.bufnr(file_path, true)
                if not vim.api.nvim_buf_is_loaded(buf_id) then
                    vim.fn.bufload(buf_id)
                end

                -- Configure buffer
                vim.bo[buf_id].buflisted = true
                vim.bo[buf_id].buftype = ""

                buffer_mappings[file_path] = buf_id
                opened_count = opened_count + 1
            end
        else
            vim.notify("Cannot read file: " .. file_path, vim.log.levels.WARN)
        end
    end

    return buffer_mappings, opened_count
end

-- Rebuild group structure from session data using proper APIs
local function rebuild_groups(session_data, buffer_mappings)
    local groups = require('vertical-bufferline.groups')

    -- Step 1: Clear existing groups using proper API
    local existing_groups = groups.get_all_groups()
    for _, group in ipairs(existing_groups) do
        if group.id ~= "default" then  -- Don't delete default group
            groups.delete_group(group.id)
        end
    end

    -- Step 2: Clear default group buffers
    local default_group = groups.find_group_by_id("default")
    if default_group then
        -- Remove all buffers from default group
        for _, buf_id in ipairs(vim.deepcopy(default_group.buffers)) do
            groups.remove_buffer_from_group(buf_id, "default")
        end
    end

    -- Step 3: Recreate groups from session data using proper API
    local group_id_mapping = {} -- old_id -> new_id mapping for non-default groups

    for _, group_data in ipairs(session_data.groups) do
        local new_group_id

        if group_data.id == "default" then
            -- Use existing default group
            new_group_id = "default"
            -- Update default group name if needed
            if group_data.name and group_data.name ~= "" then
                groups.rename_group("default", group_data.name)
            end
        else
            -- Create new group
            new_group_id = groups.create_group(group_data.name, group_data.color)
            group_id_mapping[group_data.id] = new_group_id
        end

        -- Assign buffers to this group
        for _, buffer_info in ipairs(group_data.buffers or {}) do
            local file_path = expand_buffer_path(buffer_info.path)
            local buf_id = buffer_mappings[file_path]

            if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
                groups.add_buffer_to_group(buf_id, new_group_id)
            end
        end
        
        -- Restore current buffer for this group if available
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
        
        -- Restore history for this group if available
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
    local target_active_group_id = session_data.active_group_id
    if target_active_group_id ~= "default" and group_id_mapping[target_active_group_id] then
        target_active_group_id = group_id_mapping[target_active_group_id]
    end

    -- Verify the target group exists and set it active
    local target_group = groups.find_group_by_id(target_active_group_id)
    if target_group then
        groups.set_active_group(target_active_group_id)
        
        -- Ensure the correct current buffer is set after group switch
        if target_group.current_buffer and vim.api.nvim_buf_is_valid(target_group.current_buffer) 
           and vim.tbl_contains(target_group.buffers, target_group.current_buffer) then
            vim.schedule(function()
                vim.api.nvim_set_current_buf(target_group.current_buffer)
            end)
        end
    else
        -- Fallback to default group if target doesn't exist
        groups.set_active_group("default")
    end
    
    -- Step 5: Fallback for unmapped existing buffers - add them to default group
    local default_group = groups.find_group_by_id("default")
    if default_group then
        for file_path, buf_id in pairs(buffer_mappings) do
            if vim.api.nvim_buf_is_valid(buf_id) then
                -- Check if this buffer is already in any group
                local buffer_group = groups.find_buffer_group(buf_id)
                if not buffer_group then
                    -- Buffer exists but not in any group, add to default
                    groups.add_buffer_to_group(buf_id, "default")
                end
            end
        end
    end

    if session_data.pinned_buffers and type(session_data.pinned_buffers) == "table" then
        local pin_set = {}
        for _, pinned_path in ipairs(session_data.pinned_buffers) do
            local expanded = expand_buffer_path(pinned_path)
            local buf_id = buffer_mappings[expanded]
            if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
                pin_set[buf_id] = true
            end
        end

        local state_module = require('vertical-bufferline.state')
        for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(buf_id) then
                state_module.set_buffer_pinned(buf_id, pin_set[buf_id] == true)
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
end

--- Load groups configuration from session file
--- @param filename string Optional filename to load from
--- @return boolean success
function M.load_session(filename)
    filename = filename or get_session_filename()

    -- Check if session file exists
    if vim.fn.filereadable(filename) == 0 then
        return false
    end

    local success, session_data = pcall(function()
        local file = io.open(filename, "r")
        if not file then
            error("Cannot open session file for reading: " .. filename)
        end

        local content = file:read("*all")
        file:close()

        if content == "" then
            error("Session file is empty")
        end

        return vim.json.decode(content)
    end)

    if not success then
        vim.notify("Failed to load session: " .. (session_data or "unknown error"), vim.log.levels.ERROR)
        return false
    end

    -- Validate session data
    if not session_data.groups or type(session_data.groups) ~= "table" then
        vim.notify("Invalid session data format", vim.log.levels.ERROR)
        return false
    end

    apply_session_position(session_data)

    local state_module = require('vertical-bufferline.state')
    saved_cmdheight = vim.o.cmdheight
    state_module.set_session_loading(true)

    -- Temporarily disable bufferline sync during loading
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    local groups = require('vertical-bufferline.groups')

    -- Disable auto-add during session restore to prevent BufEnter from interfering
    groups.disable_auto_add()

    bufferline_integration.set_sync_target(nil)

    -- Wrap in pcall to ensure cleanup always happens
    local success, result = pcall(function()
        -- Step 1: Handle existing buffers
        local handled_buffers = handle_existing_buffers(session_data)

        -- Step 2: Collect all session files
        local session_files = collect_session_files(session_data)

        -- Step 3: Open all session files
        local buffer_mappings, opened_count = open_session_files(session_files)

        -- Step 4: Rebuild group structure
        rebuild_groups(session_data, buffer_mappings)

        -- Step 5: Common finalization
        finalize_session_restore(session_data, opened_count, #session_data.groups)

        return opened_count
    end)

    -- Always re-enable auto-add and reset state, even if there was an error
    groups.enable_auto_add()
    state_module.set_session_loading(false)

    if not success then
        vim.notify("Session load error: " .. tostring(result), vim.log.levels.ERROR)
        return false
    end

    local opened_count = result
    vim.notify(string.format("Session loaded: %s (%d buffers, %d groups)",
        vim.fn.fnamemodify(filename, ":t"), opened_count, #session_data.groups), vim.log.levels.INFO)

    return true
end

--- Check if session exists for current working directory
--- @param filename string Optional filename to check
--- @return boolean exists
function M.has_session(filename)
    filename = filename or get_session_filename()
    return vim.fn.filereadable(filename) == 1
end

--- Delete session file
--- @param filename string Optional filename to delete
--- @return boolean success
function M.delete_session(filename)
    filename = filename or get_session_filename()
    if vim.fn.filereadable(filename) == 1 then
        local success = pcall(os.remove, filename)
        if success then
            vim.notify("Session deleted: " .. vim.fn.fnamemodify(filename, ":t"), vim.log.levels.INFO)
            return true
        else
            vim.notify("Failed to delete session file", vim.log.levels.ERROR)
            return false
        end
    else
        vim.notify("No session file found", vim.log.levels.WARN)
        return false
    end
end

--- List available sessions
--- @return table List of session info objects
function M.list_sessions()
    ensure_session_dir()
    local sessions = {}

    local files = vim.fn.glob(config.session_dir .. "/*.json", false, true)
    for _, file in ipairs(files) do
        local session_info = {
            filename = file,
            name = vim.fn.fnamemodify(file, ":t:r"),
            modified = vim.fn.getftime(file)
        }

        -- Try to read basic info from session
        local success, data = pcall(function()
            local f = io.open(file, "r")
            if f then
                local content = f:read("*all")
                f:close()
                return vim.json.decode(content)
            end
        end)

        if success and data then
            session_info.working_directory = data.working_directory
            session_info.timestamp = data.timestamp
            session_info.group_count = #(data.groups or {})
        end

        table.insert(sessions, session_info)
    end

    -- Sort by modification time (newest first)
    table.sort(sessions, function(a, b)
        return a.modified > b.modified
    end)

    return sessions
end

--- Setup auto-save and auto-load
--- @param opts table Configuration options
function M.setup(opts)
    opts = opts or {}
    config = vim.tbl_deep_extend("force", config, opts)

    ensure_session_dir()

    if config.auto_save then
        -- Auto-save on exit
        api.nvim_create_autocmd("VimLeavePre", {
            pattern = "*",
            callback = function()
                M.save_session()
            end,
            desc = "Auto-save vertical-bufferline session on exit"
        })

        -- Auto-save when group structure changes (with debouncing)
        api.nvim_create_autocmd("User", {
            pattern = {
                "VBufferLineGroupChanged",
                "VBufferLineGroupCreated",
                "VBufferLineGroupDeleted",
                "VBufferLineBufferAddedToGroup",
                "VBufferLineBufferRemovedFromGroup"
            },
            callback = function()
                -- Debounce: cancel previous timer and restart counting
                if auto_save_timer then
                    auto_save_timer:stop()
                    auto_save_timer:close()
                end

                -- Delayed save to avoid frequent IO
                auto_save_timer = vim.loop.new_timer()
                auto_save_timer:start(2000, 0, vim.schedule_wrap(function()
                    M.save_session()
                    if auto_save_timer then
                        auto_save_timer:close()
                        auto_save_timer = nil
                    end
                end))
            end,
            desc = "Auto-save session when group structure changes"
        })
    end

    if config.auto_load then
        -- Auto-load on startup with more delay to ensure bufferline is ready
        vim.defer_fn(function()
            if M.has_session() then
                -- Ensure bufferline integration is enabled
                local bufferline_integration = require('vertical-bufferline.bufferline-integration')
                if not bufferline_integration.status().is_hooked then
                    bufferline_integration.enable()
                end

                -- Add additional delay to ensure all plugins are ready
                vim.defer_fn(function()
                    M.load_session()

                    -- Additional wait after session load completion, then force sync
                    vim.defer_fn(function()
                        bufferline_integration.force_refresh()

                        -- Ensure current buffer is correct again
                        local groups = require('vertical-bufferline.groups')
                        local active_group = groups.get_active_group()
                        if active_group and #active_group.buffers > 0 then
                            local current_buf = vim.api.nvim_get_current_buf()
                            if not vim.tbl_contains(active_group.buffers, current_buf) then
                                for _, buf_id in ipairs(active_group.buffers) do
                                    if vim.api.nvim_buf_is_valid(buf_id) and vim.api.nvim_buf_is_loaded(buf_id) then
                                        vim.api.nvim_set_current_buf(buf_id)
                                        break
                                    end
                                end
                            end
                        end

                        bufferline_integration.force_refresh()
                    end, 300)
                end, 200)
            end
        end, 500)
    end
end

-- ============================================================================
-- Global Variable Session Integration (for Neovim native sessions)
-- ============================================================================

-- State collection for global variable serialization
local function collect_current_state()
    local groups = require('vertical-bufferline.groups')
    local state_module = require('vertical-bufferline.state')
    local all_groups = groups.get_all_groups()
    local active_group_id = groups.get_active_group_id()
    
    -- Prepare session data (similar to save_session but simplified)
    local session_data = {
        version = "1.0",
        timestamp = os.time(),
        active_group_id = active_group_id,
        position = config_module.settings.position,
        groups = {},
        pinned_buffers = {}
    }
    
    -- Convert groups data for persistence
    for _, group in ipairs(all_groups) do
        local group_data = {
            id = group.id,
            name = group.name,
            created_at = group.created_at,
            color = group.color,
            buffers = {},
            current_buffer_path = nil,  -- Will be set below if valid
            history = {}  -- Will be set below if valid
        }
        
        -- Save buffer information using current group buffers
        local current_group_buffers = groups.get_group_buffers(group.id)
        for _, buffer_id in ipairs(current_group_buffers) do
            if api.nvim_buf_is_valid(buffer_id) then
                local buffer_path = api.nvim_buf_get_name(buffer_id)
                if buffer_path ~= "" then
                    -- Normalize paths to be relative when possible
                    local normalized_path = normalize_buffer_path(buffer_path)
                    table.insert(group_data.buffers, {
                        path = normalized_path
                    })
                end
            end
        end
        
        -- Save current buffer for this group
        -- If this is the active group, use the actual current buffer
        -- Otherwise, use the group's recorded current buffer
        local current_buf_for_group = nil
        if group.id == active_group_id then
            -- For active group, use the actual current buffer
            local actual_current_buf = api.nvim_get_current_buf()
            if vim.tbl_contains(current_group_buffers, actual_current_buf) then
                current_buf_for_group = actual_current_buf
            end
        else
            -- For other groups, use the recorded current buffer if valid
            if group.current_buffer and api.nvim_buf_is_valid(group.current_buffer) and 
               vim.tbl_contains(current_group_buffers, group.current_buffer) then
                current_buf_for_group = group.current_buffer
            end
        end
        
        if current_buf_for_group then
            local current_buffer_path = api.nvim_buf_get_name(current_buf_for_group)
            if current_buffer_path ~= "" then
                group_data.current_buffer_path = normalize_buffer_path(current_buffer_path)
            end
        end
        
        -- Save history for this group (always save history field, even if empty)
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
        -- Note: group_data.history is always initialized as {} above, so it will be saved even if empty
        
        table.insert(session_data.groups, group_data)
    end

    session_data.pinned_buffers = get_pinned_buffers()
    
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
    if not session_data.groups or type(session_data.groups) ~= "table" then
        vim.notify("Invalid VBL session data format", vim.log.levels.ERROR)
        return false
    end

    apply_session_position(session_data)
    
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
        rebuild_groups(session_data, buffer_mappings)

        -- Common finalization
        finalize_session_restore(session_data, vim.tbl_count(buffer_mappings), #session_data.groups)
    end)

    -- Always re-enable auto-add and reset state, even if there was an error
    groups.enable_auto_add()
    state_module.set_session_loading(false)
    _G._vbl_session_restore_in_progress = false

    if not success then
        vim.notify("VBL state restore error: " .. tostring(err), vim.log.levels.ERROR)
        return false
    end

    vim.notify(string.format("VBL state restored (%d groups)", #session_data.groups), vim.log.levels.INFO)
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
            if success and session_data.groups then
                local group_count = #session_data.groups
                local buffer_count = 0
                for _, group in ipairs(session_data.groups) do
                    buffer_count = buffer_count + #(group.buffers or {})
                end
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

-- Export configuration and functions
M.config = config
M.get_session_filename = get_session_filename

return M
