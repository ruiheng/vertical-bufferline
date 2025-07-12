-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/components.lua
-- Buffer line components for vertical-bufferline

local M = {}

local renderer = require('vertical-bufferline.renderer')
local config_module = require('vertical-bufferline.config')

-- Create tree prefix component
---@param is_last boolean
---@param is_current boolean
---@return LinePart[]
function M.create_tree_prefix(is_last, is_current)
    local prefix_text
    local highlight_group
    
    if is_current then
        prefix_text = is_last and (" " .. config_module.UI.TREE_LAST_CURRENT) or (" " .. config_module.UI.TREE_BRANCH_CURRENT)
        highlight_group = config_module.HIGHLIGHTS.PREFIX_CURRENT
    else
        prefix_text = is_last and (" " .. config_module.UI.TREE_LAST) or (" " .. config_module.UI.TREE_BRANCH)
        highlight_group = config_module.HIGHLIGHTS.PREFIX
    end
    
    return {
        renderer.create_part(prefix_text, highlight_group)
    }
end

-- Create dual numbering component
---@param local_pos number|nil Local position in bufferline (nil if not visible)
---@param global_pos number Global position in buffer list
---@return LinePart[]
function M.create_dual_numbering(local_pos, global_pos)
    local local_num = local_pos and tostring(local_pos) or "-"
    local global_num = tostring(global_pos)
    
    return {
        renderer.create_part(local_num, 
            local_num == "-" and config_module.HIGHLIGHTS.NUMBER_HIDDEN or config_module.HIGHLIGHTS.NUMBER_LOCAL),
        renderer.create_part("|", config_module.HIGHLIGHTS.NUMBER_SEPARATOR),
        renderer.create_part(global_num, config_module.HIGHLIGHTS.NUMBER_GLOBAL)
    }
end

-- Create simple numbering component (fallback)
---@param position number
---@return LinePart[]
function M.create_simple_numbering(position)
    return {
        renderer.create_part(tostring(position), config_module.HIGHLIGHTS.NUMBER_LOCAL)
    }
end

-- Create modified indicator component
---@param is_modified boolean
---@return LinePart[]
function M.create_modified_indicator(is_modified)
    if is_modified then
        return {
            renderer.create_part("● ", config_module.HIGHLIGHTS.MODIFIED)
        }
    else
        return {}
    end
end

-- Create icon component
---@param icon string
---@return LinePart[]
function M.create_icon(icon)
    if icon and icon ~= "" then
        return {
            renderer.create_part(icon .. " ", nil)  -- Icons usually don't need special highlighting
        }
    else
        return {}
    end
end

-- Create filename component with optional prefix
---@param prefix_info table|nil {prefix: string, filename: string}
---@param full_name string Complete filename if no prefix
---@param is_current boolean
---@param is_visible boolean
---@return LinePart[]
function M.create_filename(prefix_info, full_name, is_current, is_visible)
    local parts = {}
    
    if prefix_info and prefix_info.prefix and prefix_info.prefix ~= "" then
        -- Has prefix: highlight prefix and filename separately
        local prefix_highlight = is_current and config_module.HIGHLIGHTS.PREFIX_CURRENT or 
                                (is_visible and config_module.HIGHLIGHTS.PREFIX_VISIBLE or config_module.HIGHLIGHTS.PREFIX)
        local filename_highlight = is_current and config_module.HIGHLIGHTS.FILENAME_CURRENT or 
                                  (is_visible and config_module.HIGHLIGHTS.FILENAME_VISIBLE or config_module.HIGHLIGHTS.FILENAME)
        
        table.insert(parts, renderer.create_part(prefix_info.prefix, prefix_highlight))
        table.insert(parts, renderer.create_part(prefix_info.filename, filename_highlight))
    else
        -- No prefix: highlight entire filename
        local filename_highlight = is_current and config_module.HIGHLIGHTS.FILENAME_CURRENT or 
                                  (is_visible and config_module.HIGHLIGHTS.FILENAME_VISIBLE or config_module.HIGHLIGHTS.FILENAME)
        
        table.insert(parts, renderer.create_part(full_name, filename_highlight))
    end
    
    return parts
end

-- Create pick mode letter component
---@param letter string
---@param is_current boolean
---@param is_visible boolean
---@return LinePart[]
function M.create_pick_letter(letter, is_current, is_visible)
    local highlight_group
    if is_current then
        highlight_group = config_module.HIGHLIGHTS.PICK_SELECTED
    elseif is_visible then
        highlight_group = config_module.HIGHLIGHTS.PICK_VISIBLE
    else
        highlight_group = config_module.HIGHLIGHTS.PICK
    end
    
    return {
        renderer.create_part(letter .. " ", highlight_group)
    }
end

-- Create space component
---@param count number Number of spaces
---@return LinePart[]
function M.create_space(count)
    if count > 0 then
        return {
            renderer.create_part(string.rep(" ", count), nil)
        }
    else
        return {}
    end
end

return M