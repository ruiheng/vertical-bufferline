-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/logger.lua
-- Debug logging system for vertical-bufferline

local M = {}

-- Logger state
local logger_state = {
    enabled = false,
    log_file = nil,
    log_level = "INFO", -- DEBUG, INFO, WARN, ERROR
    buffer_size = 1000, -- max lines to keep in memory
    log_buffer = {},
    session_id = nil
}

-- Log levels
local LOG_LEVELS = {
    DEBUG = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3
}

-- Get timestamp string
local function get_timestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

-- Get session ID (unique per nvim session)
local function get_session_id()
    if not logger_state.session_id then
        logger_state.session_id = string.format("%d", os.time())
    end
    return logger_state.session_id
end

-- Check if log level should be written
local function should_log(level)
    if not logger_state.enabled then
        return false
    end
    
    local current_level = LOG_LEVELS[logger_state.log_level] or LOG_LEVELS.INFO
    local message_level = LOG_LEVELS[level] or LOG_LEVELS.INFO
    
    return message_level >= current_level
end

-- Format log message
local function format_message(level, module, message, context)
    local timestamp = get_timestamp()
    local session = get_session_id()
    
    local formatted = string.format("[%s] [%s] [%s] %s: %s", 
        timestamp, session, level, module, message)
    
    if context and type(context) == "table" then
        local context_str = vim.inspect(context, { indent = "  ", depth = 2 })
        formatted = formatted .. "\n  Context: " .. context_str
    elseif context then
        formatted = formatted .. " | " .. tostring(context)
    end
    
    return formatted
end

-- Write to log file
local function write_to_file(formatted_message)
    if not logger_state.log_file then
        return
    end
    
    local file = io.open(logger_state.log_file, "a")
    if file then
        file:write(formatted_message .. "\n")
        file:flush()
        file:close()
    end
end

-- Add to memory buffer
local function add_to_buffer(formatted_message)
    table.insert(logger_state.log_buffer, formatted_message)
    
    -- Limit buffer size
    if #logger_state.log_buffer > logger_state.buffer_size then
        table.remove(logger_state.log_buffer, 1)
    end
end

-- Core logging function
local function log(level, module, message, context)
    if not should_log(level) then
        return
    end
    
    local formatted = format_message(level, module, message, context)
    
    -- Write to file if enabled
    if logger_state.log_file then
        write_to_file(formatted)
    end
    
    -- Add to memory buffer
    add_to_buffer(formatted)
    
    -- Also output to nvim if DEBUG level
    if level == "DEBUG" and logger_state.log_level == "DEBUG" then
        print("[BN-DEBUG] " .. message)
    end
end

-- Public logging functions
function M.debug(module, message, context)
    log("DEBUG", module, message, context)
end

function M.info(module, message, context)
    log("INFO", module, message, context)
end

function M.warn(module, message, context)
    log("WARN", module, message, context)
end

function M.error(module, message, context)
    log("ERROR", module, message, context)
end

-- Buffer state logging helper
function M.log_buffer_state(module, current_buf, expected_buf, reason)
    local context = {
        current_buffer = current_buf,
        expected_buffer = expected_buf,
        current_valid = current_buf and vim.api.nvim_buf_is_valid(current_buf) or false,
        expected_valid = expected_buf and vim.api.nvim_buf_is_valid(expected_buf) or false,
        current_name = current_buf and vim.api.nvim_buf_get_name(current_buf) or "nil",
        expected_name = expected_buf and vim.api.nvim_buf_get_name(expected_buf) or "nil",
        reason = reason
    }
    
    local message = string.format("Buffer state mismatch - current=%s, expected=%s", 
        tostring(current_buf), tostring(expected_buf))
    
    if current_buf == expected_buf then
        M.debug(module, "Buffer state OK - " .. reason, context)
    else
        M.warn(module, message, context)
    end
end

-- Group state logging helper
function M.log_group_state(module, action, group_info)
    local context = {
        action = action,
        active_group = group_info and group_info.active_group and group_info.active_group.id or "none",
        group_name = group_info and group_info.active_group and group_info.active_group.name or "none",
        buffer_count = group_info and group_info.active_group and #group_info.active_group.buffers or 0,
        current_buffer = group_info and group_info.active_group and group_info.active_group.current_buffer or "nil"
    }
    
    M.info(module, "Group " .. action, context)
end

-- Timer sync logging helper
function M.log_sync_state(module, sync_reason, changes_detected, details)
    local context = vim.tbl_extend("force", details or {}, {
        sync_reason = sync_reason,
        changes_detected = changes_detected,
        timestamp = get_timestamp()
    })
    
    if changes_detected then
        M.info(module, "Sync triggered: " .. sync_reason, context)
    else
        M.debug(module, "Sync check (no changes): " .. sync_reason, context)
    end
end

-- Configuration functions
function M.enable(log_file_path, log_level)
    logger_state.enabled = true
    logger_state.log_file = log_file_path or vim.fn.expand("~/vbl-debug.log")
    logger_state.log_level = log_level or "INFO"
    logger_state.session_id = nil -- Reset session ID
    
    -- Create/clear log file
    if logger_state.log_file then
        local file = io.open(logger_state.log_file, "w")
        if file then
            file:write(string.format("=== BN Debug Log Started at %s ===\n", get_timestamp()))
            file:write(string.format("Session ID: %s\n", get_session_id()))
            file:write(string.format("Log Level: %s\n\n", logger_state.log_level))
            file:close()
        end
    end
    
    M.info("logger", "Debug logging enabled", {
        log_file = logger_state.log_file,
        log_level = logger_state.log_level
    })
end

function M.disable()
    if logger_state.enabled then
        M.info("logger", "Debug logging disabled")
        
        if logger_state.log_file then
            local file = io.open(logger_state.log_file, "a")
            if file then
                file:write(string.format("\n=== BN Debug Log Ended at %s ===\n", get_timestamp()))
                file:close()
            end
        end
    end
    
    logger_state.enabled = false
    logger_state.log_file = nil
end

function M.is_enabled()
    return logger_state.enabled
end

function M.set_level(level)
    if LOG_LEVELS[level] then
        logger_state.log_level = level
        M.info("logger", "Log level changed to " .. level)
    end
end

function M.get_status()
    return {
        enabled = logger_state.enabled,
        log_file = logger_state.log_file,
        log_level = logger_state.log_level,
        session_id = logger_state.session_id,
        buffer_lines = #logger_state.log_buffer
    }
end

function M.get_recent_logs(count)
    count = count or 50
    local start_idx = math.max(1, #logger_state.log_buffer - count + 1)
    local recent = {}
    
    for i = start_idx, #logger_state.log_buffer do
        table.insert(recent, logger_state.log_buffer[i])
    end
    
    return recent
end

function M.clear_buffer()
    logger_state.log_buffer = {}
    M.info("logger", "Memory buffer cleared")
end

return M