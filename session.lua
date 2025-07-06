-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/session.lua
-- Session persistence for vertical-bufferline groups

local M = {}

local api = vim.api

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
        expand_all_groups = require('vertical-bufferline').state and
                           require('vertical-bufferline').state.expand_all_groups or true,
        groups = {}
    }

    -- Convert groups data for persistence
    for _, group in ipairs(all_groups) do
        local group_data = {
            id = group.id,
            name = group.name,
            created_at = group.created_at,
            color = group.color,
            buffers = {}
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
                        path = normalized_path,
                        -- Save additional buffer metadata if needed
                        modified = api.nvim_buf_get_option(buffer_id, "modified")
                    })
                end
            end
        end

        table.insert(session_data.groups, group_data)
    end

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
    end

    -- Step 4: Set active group using proper API
    local target_active_group_id = session_data.active_group_id
    if target_active_group_id ~= "default" and group_id_mapping[target_active_group_id] then
        target_active_group_id = group_id_mapping[target_active_group_id]
    end

    -- Verify the target group exists before setting it active
    local target_group = groups.find_group_by_id(target_active_group_id)
    if target_group then
        groups.set_active_group(target_active_group_id)
    else
        -- Fallback to default group if target doesn't exist
        groups.set_active_group("default")
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

    -- Temporarily disable bufferline sync during loading
    local bufferline_integration = require('vertical-bufferline.bufferline-integration')
    bufferline_integration.set_sync_target(nil)

    -- Step 1: Handle existing buffers
    local handled_buffers = handle_existing_buffers(session_data)

    -- Step 2: Collect all session files
    local session_files = collect_session_files(session_data)

    -- Step 3: Open all session files
    local buffer_mappings, opened_count = open_session_files(session_files)

    -- Step 4: Rebuild group structure
    rebuild_groups(session_data, buffer_mappings)

    -- Step 5: Restore expand mode if available
    if session_data.expand_all_groups ~= nil then
        local vbl = require('vertical-bufferline')
        if vbl.state then
            vbl.state.expand_all_groups = session_data.expand_all_groups
        end
    end

    -- Step 6: Final sync to bufferline (rebuild_groups already set active group)
    local groups = require('vertical-bufferline.groups')
    local active_group = groups.get_active_group()

    if active_group then
        -- Ensure bufferline is synced with the restored active group
        bufferline_integration.set_bufferline_buffers(active_group.buffers)
        bufferline_integration.set_sync_target(active_group.id)

        -- Switch to first buffer in active group if available
        if #active_group.buffers > 0 then
            for _, buf_id in ipairs(active_group.buffers) do
                if vim.api.nvim_buf_is_valid(buf_id) and vim.api.nvim_buf_is_loaded(buf_id) then
                    vim.api.nvim_set_current_buf(buf_id)
                    break
                end
            end
        end
    else
        -- Fallback: ensure sync is enabled even if no active group
        bufferline_integration.set_sync_target("default")
    end

    -- Step 7: Refresh UI
    vim.schedule(function()
        local vbl = require('vertical-bufferline')
        if vbl.state and vbl.state.is_sidebar_open then
            vbl.refresh()
        end
    end)

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

-- Export configuration and functions
M.config = config
M.get_session_filename = get_session_filename

return M
