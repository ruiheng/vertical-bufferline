-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/layout.lua
-- Layout helpers for position-specific sizing

local M = {}

local api = vim.api

function M.is_horizontal(position)
    return position == "top" or position == "bottom"
end

local function clamp(value, min_value, max_value)
    return math.max(min_value, math.min(value, max_value))
end

function M.initial_size(position, state_module, settings)
    local width = state_module.get_last_width() or settings.min_width
    if M.is_horizontal(position) then
        return width, 1
    end
    local height = state_module.get_last_height() or settings.min_height
    return width, height
end

function M.save_size(win_id, position, state_module)
    if M.is_horizontal(position) then
        local current_height = api.nvim_win_get_height(win_id)
        state_module.set_last_height(current_height)
    else
        local current_width = api.nvim_win_get_width(win_id)
        state_module.set_last_width(current_width)
    end
end

function M.clear_cached_size_on_axis_switch(previous_position, next_position, state_module)
    if not previous_position or not next_position then
        return
    end

    local was_horizontal = M.is_horizontal(previous_position)
    local is_horizontal = M.is_horizontal(next_position)
    if was_horizontal == is_horizontal then
        return
    end

    if is_horizontal then
        state_module.set_last_width(nil)
    else
        state_module.set_last_height(nil)
    end
end

function M.statusline_height(laststatus, normal_window_count)
    if laststatus == 3 or laststatus == 0 then
        return 0
    end
    if laststatus == 1 then
        return normal_window_count > 1 and 1 or 0
    end
    return 1
end

function M.placeholder_height(content_height, statusline_height)
    return math.max(1, content_height - statusline_height)
end

return M
