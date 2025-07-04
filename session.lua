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

-- Save current groups configuration to session file
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
        
        -- Save buffer information
        for _, buffer_id in ipairs(group.buffers) do
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

-- Load groups configuration from session file
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
    
    -- Clear existing groups and load from session
    local groups = require('vertical-bufferline.groups')
    
    -- Get current groups data to reset
    local debug_info = groups.debug_info()
    local groups_data = debug_info.groups_data
    
    -- 调试：显示加载前的状态
    print("=== Before Session Load ===")
    for i, group in ipairs(groups_data.groups) do
        print(string.format("Existing Group %d: '%s' (%d buffers)", 
            i, group.name, #group.buffers))
    end
    print("===========================")
    
    -- Clear existing groups (except we'll recreate them)
    groups_data.groups = {}
    groups_data.active_group_id = nil
    
    -- Track buffers that need to be opened
    local buffers_to_open = {}
    local buffer_to_group_map = {}
    local unique_buffers = {} -- 防止重复添加相同的buffer路径
    
    -- Recreate groups from session data
    for _, group_data in ipairs(session_data.groups) do
        local new_group = {
            id = group_data.id,
            name = group_data.name or "",
            created_at = group_data.created_at or os.time(),
            color = group_data.color or "#98c379",
            buffers = {}
        }
        
        -- Process buffer paths and prepare to open them
        for _, buffer_info in ipairs(group_data.buffers or {}) do
            local buffer_path = expand_buffer_path(buffer_info.path)
            
            -- 只添加唯一的buffer路径到待打开列表
            if not unique_buffers[buffer_path] then
                unique_buffers[buffer_path] = true
                table.insert(buffers_to_open, buffer_path)
            end
            
            -- Map buffer path to group for later assignment
            if not buffer_to_group_map[buffer_path] then
                buffer_to_group_map[buffer_path] = {}
            end
            table.insert(buffer_to_group_map[buffer_path], group_data.id)
        end
        
        table.insert(groups_data.groups, new_group)
    end
    
    -- Restore active group
    groups_data.active_group_id = session_data.active_group_id
    
    -- Restore expand mode if available
    if session_data.expand_all_groups ~= nil then
        local vbl = require('vertical-bufferline')
        if vbl.state then
            vbl.state.expand_all_groups = session_data.expand_all_groups
        end
    end
    
    -- Set session loading flag to prevent interference
    local vbl = require('vertical-bufferline')
    if vbl.state then
        vbl.state.session_loading = true
    end
    
    -- Open buffers and assign them to groups with multiple stages
    vim.schedule(function()
        local buffers_opened = 0
        local total_buffers = #buffers_to_open
        
        -- 调试：显示即将加载的分组结构
        print("=== Session Loading Debug ===")
        for _, group_data in ipairs(session_data.groups) do
            print(string.format("Group '%s' (ID: %s) should have %d buffers:", 
                group_data.name, group_data.id, #(group_data.buffers or {})))
            for i, buffer_info in ipairs(group_data.buffers or {}) do
                print(string.format("  %d. %s", i, buffer_info.path))
            end
        end
        print("==========================")
        
        -- Stage 1: Open all buffers first
        for _, buffer_path in ipairs(buffers_to_open) do
            if vim.fn.filereadable(buffer_path) == 1 then
                -- Open buffer silently
                local buf_id = vim.fn.bufnr(buffer_path, true)
                
                -- Force buffer to be loaded
                if not vim.api.nvim_buf_is_loaded(buf_id) then
                    vim.fn.bufload(buf_id)
                end
                
                -- 确保buffer被列出（这对bufferline很重要）
                vim.bo[buf_id].buflisted = true
                
                -- 设置buffer类型为空（正常文件）
                if vim.bo[buf_id].buftype ~= "" then
                    vim.bo[buf_id].buftype = ""
                end
                
                -- 如果使用了 scope.nvim，确保buffer被添加到当前tab
                -- 通过短暂切换到buffer来让scope识别它属于当前tab
                local current_buf = vim.api.nvim_get_current_buf()
                vim.api.nvim_set_current_buf(buf_id)
                vim.api.nvim_set_current_buf(current_buf)
                
                print(string.format("Session: Loaded buffer [%d] %s (listed: %s)", 
                    buf_id, vim.fn.fnamemodify(buffer_path, ":t"), vim.bo[buf_id].buflisted))
                
                buffers_opened = buffers_opened + 1
            end
        end
        
        -- Stage 2: Wait a bit, then assign buffers to groups
        vim.defer_fn(function()
            local assigned_count = 0
            print("=== Stage 2: Buffer Assignment ===")
            
            for _, buffer_path in ipairs(buffers_to_open) do
                if vim.fn.filereadable(buffer_path) == 1 then
                    local buf_id = vim.fn.bufnr(buffer_path, false)
                    if buf_id > 0 and vim.api.nvim_buf_is_valid(buf_id) then
                        -- Add buffer to appropriate groups
                        local group_ids = buffer_to_group_map[buffer_path]
                        if group_ids then
                            print(string.format("Assigning buffer [%d] %s to groups: %s", 
                                buf_id, vim.fn.fnamemodify(buffer_path, ":t"), 
                                table.concat(group_ids, ", ")))
                            
                            -- 对于session加载，恢复buffer到所有原属分组（支持多分组）
                            for _, group_id in ipairs(group_ids) do
                                local success = groups.add_buffer_to_group(buf_id, group_id)
                                print(string.format("  -> Group %s: %s", group_id, success and "SUCCESS" or "FAILED"))
                                if success then
                                    assigned_count = assigned_count + 1
                                end
                            end
                            
                            if #group_ids > 1 then
                                print(string.format("  INFO: Buffer %s restored to %d groups (multi-group design)", 
                                    vim.fn.fnamemodify(buffer_path, ":t"), #group_ids))
                            end
                        else
                            print(string.format("WARNING: No group mapping for buffer %s", buffer_path))
                        end
                    else
                        print(string.format("WARNING: Invalid buffer for path %s (buf_id: %s)", buffer_path, buf_id))
                    end
                else
                    print(string.format("WARNING: File not readable: %s", buffer_path))
                end
            end
            
            print("=============================")
            
            -- Stage 3: Force bufferline refresh and sidebar update
            vim.defer_fn(function()
                -- 调试信息：检查buffer和分组状态
                local active_group = groups.get_active_group()
                local all_buffers = vim.api.nvim_list_bufs()
                local valid_buffers = {}
                for _, buf in ipairs(all_buffers) do
                    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
                        local name = vim.api.nvim_buf_get_name(buf)
                        if name ~= "" then
                            table.insert(valid_buffers, {id = buf, name = vim.fn.fnamemodify(name, ":t")})
                        end
                    end
                end
                
                print(string.format("Session Stage 3: Active group: %s, Valid buffers: %d", 
                    active_group and active_group.name or "none", #valid_buffers))
                
                if active_group then
                    print(string.format("  Group buffers: %d", #active_group.buffers))
                    for i, buf_id in ipairs(active_group.buffers) do
                        if i <= 3 then -- 只显示前3个
                            local name = vim.api.nvim_buf_get_name(buf_id)
                            print(string.format("    [%d] %s", buf_id, vim.fn.fnamemodify(name, ":t")))
                        end
                    end
                end
                
                -- Force bufferline integration refresh
                local bufferline_integration = require('vertical-bufferline.bufferline-integration')
                bufferline_integration.force_refresh()
                
                -- 确保当前缓冲区在活跃分组中，这对scope.nvim很重要
                if active_group and #active_group.buffers > 0 then
                    local current_buf = vim.api.nvim_get_current_buf()
                    local target_buf = nil
                    
                    -- 找到分组中第一个有效的缓冲区
                    for _, buf_id in ipairs(active_group.buffers) do
                        if vim.api.nvim_buf_is_valid(buf_id) and vim.api.nvim_buf_is_loaded(buf_id) then
                            target_buf = buf_id
                            break
                        end
                    end
                    
                    if target_buf then
                        -- 切换到目标缓冲区，确保scope和bufferline都能看到它
                        vim.api.nvim_set_current_buf(target_buf)
                        print(string.format("  Set current buffer to: [%d] %s", 
                            target_buf, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(target_buf), ":t")))
                        
                        -- 强制触发BufEnter事件，确保scope正确处理
                        vim.api.nvim_exec_autocmds('BufEnter', { buffer = target_buf })
                    end
                end
                
                -- 再次强制刷新
                bufferline_integration.force_refresh()
                
                -- Refresh the sidebar if it's open
                local vbl = require('vertical-bufferline')
                if vbl.state and vbl.state.is_sidebar_open then
                    vbl.refresh()
                end
                
                vim.notify(string.format("Session loaded: %s (%d buffers, %d assignments)", 
                    vim.fn.fnamemodify(filename, ":t"), buffers_opened, assigned_count), vim.log.levels.INFO)
                
                -- Clear session loading flag
                if vbl.state then
                    vbl.state.session_loading = false
                end
            end, 100)
        end, 150)
    end)
    
    return true
end

-- Check if session exists for current working directory
function M.has_session(filename)
    filename = filename or get_session_filename()
    return vim.fn.filereadable(filename) == 1
end

-- Delete session file
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

-- List available sessions
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

-- Setup auto-save and auto-load
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
    end
    
    if config.auto_load then
        -- Auto-load on startup with more delay to ensure bufferline is ready
        vim.defer_fn(function()
            if M.has_session() then
                -- 确保bufferline集成已启用
                local bufferline_integration = require('vertical-bufferline.bufferline-integration')
                if not bufferline_integration.status().is_hooked then
                    bufferline_integration.enable()
                end
                
                -- Add additional delay to ensure all plugins are ready
                vim.defer_fn(function()
                    print("Auto-loading session...")
                    M.load_session()
                    
                    -- 在session加载完成后额外等待，然后强制同步
                    vim.defer_fn(function()
                        print("Post-session sync...")
                        bufferline_integration.force_refresh()
                        
                        -- 再次确保当前缓冲区正确
                        local groups = require('vertical-bufferline.groups')
                        local active_group = groups.get_active_group()
                        if active_group and #active_group.buffers > 0 then
                            local current_buf = vim.api.nvim_get_current_buf()
                            if not vim.tbl_contains(active_group.buffers, current_buf) then
                                for _, buf_id in ipairs(active_group.buffers) do
                                    if vim.api.nvim_buf_is_valid(buf_id) and vim.api.nvim_buf_is_loaded(buf_id) then
                                        vim.api.nvim_set_current_buf(buf_id)
                                        print(string.format("Post-session: switched to buffer %d", buf_id))
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
