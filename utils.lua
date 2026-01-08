-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/utils.lua
-- Shared utility functions

local M = {}

-- Get the config module
local config_module = require('buffer-nexus.config')

--- Decide whether a buffer should be tracked by Buffer Nexus.
--- @param buf_id number Buffer ID
--- @return boolean true if buffer should be tracked
function M.should_track_buffer(buf_id)
    if not vim.api.nvim_buf_is_valid(buf_id) then
        return false
    end

    local info = {
        buftype = vim.api.nvim_buf_get_option(buf_id, 'buftype'),
        filetype = vim.api.nvim_buf_get_option(buf_id, 'filetype'),
        name = vim.api.nvim_buf_get_name(buf_id),
    }

    local filter = config_module.settings.buffer_filter
    if type(filter) == "function" then
        local ok, result = pcall(filter, buf_id, info)
        if ok and type(result) == "boolean" then
            return result
        end
    elseif type(filter) == "table" then
        if filter.filetypes and vim.tbl_contains(filter.filetypes, info.filetype) then
            return false
        end
        if filter.buftypes and vim.tbl_contains(filter.buftypes, info.buftype) then
            return false
        end
    end

    return info.buftype == config_module.SYSTEM.EMPTY_BUFTYPE
end

--- Check if buffer is special (filtered out from tracking)
--- @param buf_id number Buffer ID
--- @return boolean true if buffer is special (should not be tracked)
function M.is_special_buffer(buf_id)
    return not M.should_track_buffer(buf_id)
end

return M
