-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/init.lua

local M = {}

local api = vim.api

local ns_id = api.nvim_create_namespace("VerticalBufferline")
api.nvim_set_hl(0, "VBufferLineCurrent", { link = "Visual", default = true })

local config = {
    width = 40,
}

local state = {
    win_id = nil,
    buf_id = nil,
    line_map = {},
    is_sidebar_open = false,
}

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

function M.refresh()
    if not state.is_sidebar_open or not api.nvim_win_is_valid(state.win_id) then return end
    local buffer_info = get_buffers_from_bufferline()
    if not buffer_info then return end

    api.nvim_buf_set_lines(state.buf_id, 0, -1, false, buffer_info.buffers)
    state.line_map = buffer_info.line_map
    api.nvim_buf_clear_namespace(state.buf_id, ns_id, 0, -1)

    local current_idx = buffer_info.current_idx
    if current_idx and current_idx > 0 and current_idx <= #buffer_info.buffers then
        api.nvim_buf_add_highlight(state.buf_id, ns_id, "VBufferLineCurrent", current_idx - 1, 0, -1)
    end
end

local function close_sidebar()
    if not state.is_sidebar_open or not api.nvim_win_is_valid(state.win_id) then return end
    local current_win = api.nvim_get_current_win()
    api.nvim_set_current_win(state.win_id)
    vim.cmd("close")
    if api.nvim_win_is_valid(current_win) then
        api.nvim_set_current_win(current_win)
    end
    state.is_sidebar_open = false
    state.win_id = nil
end
M.close_sidebar = close_sidebar

function M.handle_selection()
    if not state.is_sidebar_open then return end
    local line_number = api.nvim_win_get_cursor(state.win_id)[1]
    local bufnr = state.line_map[line_number]

    if bufnr and api.nvim_buf_is_valid(bufnr) then
        local target_win_id = vim.fn.bufwinid(bufnr)
        if target_win_id ~= -1 then
            api.nvim_set_current_win(target_win_id)
        else
            -- Find the last accessed window that is not our sidebar
            local last_winnr = vim.fn.winnr('#')
            if api.nvim_win_get_buf(vim.fn.win_getid(last_winnr)) == state.buf_id then
                -- If last window was sidebar, just go to previous window
                vim.cmd("wincmd p")
            else
                api.nvim_set_current_win(vim.fn.win_getid(last_winnr))
            end
            api.nvim_set_current_buf(bufnr)
        end
    else
        vim.notify("Failed to switch buffer: invalid bufnr", vim.log.levels.ERROR)
    end
end

local function open_sidebar()
    if state.is_sidebar_open then return end

    local buf_id = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf_id, 'bufhidden', 'wipe')

    local current_win = api.nvim_get_current_win()
    vim.cmd("botright vsplit")
    local new_win_id = api.nvim_get_current_win()

    api.nvim_win_set_buf(new_win_id, buf_id)
    api.nvim_win_set_width(new_win_id, config.width)

    -- Disable line numbers for this specific window
    api.nvim_win_set_option(new_win_id, 'number', false)
    api.nvim_win_set_option(new_win_id, 'relativenumber', false)

    state.win_id = new_win_id
    state.buf_id = buf_id
    state.is_sidebar_open = true

    local keymap_opts = { noremap = true, silent = true }
    api.nvim_buf_set_keymap(buf_id, "n", "j", "j", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "k", "k", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "<CR>", ":lua require('vertical-bufferline').handle_selection()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "q", ":lua require('vertical-bufferline').close_sidebar()<CR>", keymap_opts)
    api.nvim_buf_set_keymap(buf_id, "n", "<Esc>", ":lua require('vertical-bufferline').close_sidebar()<CR>", keymap_opts)

    -- Return focus to the original window
    api.nvim_set_current_win(current_win)
end

function M.toggle()
    if state.is_sidebar_open then
        close_sidebar()
    else
        open_sidebar()
        M.refresh()
    end
end

api.nvim_create_autocmd("BufEnter", {
    pattern = "*",
    callback = function()
        if state.is_sidebar_open and api.nvim_get_current_buf() ~= state.buf_id then
             vim.defer_fn(M.refresh, 10)
        end
    end,
})

return M
