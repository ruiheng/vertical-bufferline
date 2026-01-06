-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/renderer.lua
-- Component-based line rendering system

local M = {}

local api = vim.api
local config_module = require('buffer-nexus.config')

---@class LinePart
---@field text string The text content
---@field highlight string|nil Highlight group name
---@field start_col number|nil Calculated start column (filled during rendering)
---@field end_col number|nil Calculated end column (filled during rendering)

---@class RenderedLine
---@field text string Complete line text
---@field parts LinePart[] Array of parts with calculated positions
---@field highlights table[] Array of highlight info for nvim_buf_add_highlight

-- Create a new line part
---@param text string
---@param highlight string|nil
---@return LinePart
function M.create_part(text, highlight)
    return {
        text = text,
        highlight = highlight,
        start_col = nil,
        end_col = nil
    }
end

-- Build a complete line from parts
---@param parts LinePart[]
---@return RenderedLine
function M.render_line(parts)
    local line_text = ""
    local current_col = 0
    local highlights = {}
    
    -- Calculate positions and build text
    for _, part in ipairs(parts) do
        part.start_col = current_col
        part.end_col = current_col + #part.text
        
        line_text = line_text .. part.text
        
        -- Add highlight info if specified
        if part.highlight and #part.text > 0 then
            table.insert(highlights, {
                group = part.highlight,
                start_col = part.start_col,
                end_col = part.end_col
            })
        end
        
        current_col = part.end_col
    end
    
    return {
        text = line_text,
        parts = parts,
        highlights = highlights
    }
end

-- Apply highlights to a buffer line
---@param buf_id number
---@param ns_id number
---@param line_number number 0-based line number
---@param rendered_line RenderedLine
function M.apply_highlights(buf_id, ns_id, line_number, rendered_line)
    for _, hl_info in ipairs(rendered_line.highlights) do
        api.nvim_buf_add_highlight(
            buf_id, 
            ns_id, 
            hl_info.group, 
            line_number, 
            hl_info.start_col, 
            hl_info.end_col
        )
    end
end

return M