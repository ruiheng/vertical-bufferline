-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/utils.lua
-- Shared utility functions

local M = {}

-- Get the config module
local config_module = require('buffer-nexus.config')

--- Check if buffer is special (based on buftype)
--- @param buf_id number Buffer ID
--- @return boolean true if buffer is special (should not be tracked)
function M.is_special_buffer(buf_id)
    if not vim.api.nvim_buf_is_valid(buf_id) then
        return true -- Invalid buffers are also considered special
    end
    local buftype = vim.api.nvim_buf_get_option(buf_id, 'buftype')
    return buftype ~= config_module.SYSTEM.EMPTY_BUFTYPE -- Non-empty means special buffer (nofile, quickfix, help, terminal, etc.)
end

return M