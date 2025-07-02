-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/init.lua

local M = {}

local api = vim.api

-- A dedicated namespace for our highlights, makes them easy to clear
local ns_id = api.nvim_create_namespace("VerticalBufferline")

-- Define a custom highlight group for the current buffer line
api.nvim_set_hl(0, "VBufferLineCurrent", { link = "Visual", default = true })

-- Configuration
local config = {
    width = 40,
    border = "rounded",
}

-- Runtime state
local state = {
    win_id = nil,
    buf_id = nil,
    line_map = {},
}

-- Get visible buffers and the index of the current one
local function get_buffers_from_bufferline()
    local ok_state, bufferline_state = pcall(require, "bufferline.state")
    local ok_cmds, bufferline_commands = pcall(require, "bufferline.commands")

    if not ok_state or not ok_cmds then return nil end

    local visible_buffers = bufferline_state.visible_components
    if visible_buffers == nil or type(visible_buffers) ~= "table" then return nil end

    local current_idx = bufferline_commands.get_current_element_index(bufferline_state)

    local formatted_buffers = {}
    local line_map = {}
    for i, buf in ipairs(visible_buffers) do
        if buf.id and buf.name then
            local icon = buf.icon or " "
            table.insert(formatted_buffers, string.format(" %s %d: %s", icon, i, buf.name))
            line_map[i] = buf.id
        end
    end

    return { buffers = formatted_buffers, current_idx = current_idx, line_map = line_map }
end

-- The core refresh function
function M.refresh()
    if not state.win_id or not api.nvim_win_is_valid(state.win_id) then return end

    local buffer_info = get_buffers_from_bufferline()
    if not buffer_info then return end

    -- Update the buffer content and line map
    api.nvim_buf_set_lines(state.buf_id, 0, -1, false, buffer_info.buffers)
    state.line_map = buffer_info.line_map

    -- Clear old highlights
    api.nvim_buf_clear_namespace(state.buf_id, ns_id, 0, -1)

    -- Set new highlight
    local current_idx = buffer_info.current_idx
    if current_idx and current_idx > 0 and current_idx <= #buffer_info.buffers then
        api.nvim_buf_add_highlight(state.buf_id, ns_id, "VBufferLineCurrent", current_idx - 1, 0, -1)
    end
end

-- Close the floating window
local function close_win()
    if state.win_id and api.nvim_win_is_valid(state.win_id) then
        api.nvim_win_close(state.win_id, true)
        state.win_id = nil
        state.buf_id = nil
        state.line_map = {}
    end
end
M.close_win = close_win

-- Handle buffer selection
function M.handle_selection()
    if not state.win_id then return end

    local line_number = api.nvim_win_get_cursor(state.win_id)[1]
    local bufnr = state.line_map[line_number]

    if bufnr and api.nvim_buf_is_valid(bufnr) then
        -- Find the window for the target buffer and focus it
        local target_win_id = vim.fn.bufwinid(bufnr)
        if target_win_id ~= -1 then
            api.nvim_set_current_win(target_win_id)
        else
            -- Fallback if window not found (e.g. buffer is hidden)
            api.nvim_set_current_buf(bufnr)
        end
        -- The BufEnter autocmd will trigger the refresh
    else
        vim.notify("Failed to switch buffer: invalid bufnr", vim.log.levels.ERROR)
    end
end

-- Create and open the floating window
local function open_float_win()
    local buf_id = api.nvim_create_buf(false, true)
    local width = config.width
    local total_width = api.nvim_get_option("columns")
    local total_height = api.nvim_get_option("lines")

    local opts = {
        relative = "editor",
        width = width,
        height = total_height - 2, -- Almost full height
        col = total_width - width,
        row = 1,
        anchor = "NE",
        style = "minimal",
        border = config.border,
        noautocmd = true,
    }

    local win_id = api.nvim_open_win(buf_id, false, opts) -- Open without focus

    local keymap_opts = { noremap = true, silent = true }
    api.nvim_buf_set_keymap(buf_id, "n", "j", "j", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "k", "k", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "<CR>", ":lua require('vertical-bufferline').handle_selection()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "q", ":lua require('vertical-bufferline').close_win()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "<Esc>", ":lua require('vertical-bufferline').close_win()<CR>", keymap_opts)

    state.win_id = win_id
    state.buf_id = buf_id
end

function M.toggle()
    if state.win_id and api.nvim_win_is_valid(state.win_id) then
        close_win()
    else
        open_float_win()
        M.refresh() -- Initial population and highlight
    end
end

-- Autocommand to refresh on buffer changes
api.nvim_create_autocmd("BufEnter", {
    pattern = "*",
    callback = function()
        -- Defer to avoid issues with nested autocmds
        vim.defer_fn(M.refresh, 10)
    end,
})

return M