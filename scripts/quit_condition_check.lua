-- Verify quit condition when only sidebar/placeholder remains
local function assert_ok(condition, message)
    if not condition then
        error(message, 2)
    end
end

local function add_rtp_root()
    local cwd = vim.fn.getcwd()
    local rtp_root = vim.fn.fnamemodify(cwd, ":h:h")
    vim.opt.rtp:append(rtp_root)
end

local function with_qall_capture(fn)
    local orig_cmd = vim.cmd
    local called = false
    vim.cmd = function(cmd)
        if cmd == "qall" then
            called = true
            return
        end
        return orig_cmd(cmd)
    end
    local ok, err = pcall(fn, function()
        return called
    end)
    vim.cmd = orig_cmd
    if not ok then
        error(err, 2)
    end
    return called
end

local function is_normal_window(win_id, sidebar_win_id, placeholder_win_id)
    if not win_id or not vim.api.nvim_win_is_valid(win_id) then
        return false
    end
    if win_id == sidebar_win_id or win_id == placeholder_win_id then
        return false
    end
    local config = vim.api.nvim_win_get_config(win_id)
    if config.relative ~= "" then
        return false
    end
    local buf = vim.api.nvim_win_get_buf(win_id)
    if vim.api.nvim_buf_get_option(buf, "buftype") ~= "" then
        return false
    end
    if vim.api.nvim_buf_get_option(buf, "filetype") == "vertical-bufferline-placeholder" then
        return false
    end
    return true
end

local function find_normal_window(state)
    local sidebar_win_id = state.get_win_id()
    local placeholder_win_id = state.get_placeholder_win_id()
    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
        if is_normal_window(win_id, sidebar_win_id, placeholder_win_id) then
            return win_id
        end
    end
    return nil
end

local function ensure_normal_window(state)
    local win_id = find_normal_window(state)
    if win_id then
        return win_id
    end
    vim.cmd("vsplit")
    vim.cmd("enew")
    return find_normal_window(state)
end

add_rtp_root()

local vbl = require('buffer-nexus')
local state = require('buffer-nexus.state')

local function setup_position(position)
    vbl.setup({
        auto_create_groups = true,
        auto_add_new_buffers = true,
        group_scope = "global",
        floating = false,
        position = position,
    })
end

local function open_sidebar()
    if not state.is_sidebar_open() then
        vbl.toggle()
    end
end

local function close_sidebar()
    if state.is_sidebar_open() then
        vbl.toggle()
        state.is_sidebar_open()
    end
end

-- Case 1: vertical sidebar with a normal window should NOT quit
setup_position("left")
ensure_normal_window(state)
open_sidebar()
assert_ok(state.get_win_id() and vim.api.nvim_win_is_valid(state.get_win_id()), "vertical sidebar should open")

local quit_called = with_qall_capture(function()
    vbl.check_quit_condition()
    vim.wait(200)
end)
assert_ok(not quit_called, "should not quit when normal window exists (vertical)")
close_sidebar()

-- Case 2: horizontal sidebar with placeholder and a normal window should NOT quit
setup_position("top")
ensure_normal_window(state)
open_sidebar()
local placeholder_win_id = state.get_placeholder_win_id()
assert_ok(placeholder_win_id and vim.api.nvim_win_is_valid(placeholder_win_id), "placeholder should exist in horizontal mode")

quit_called = with_qall_capture(function()
    vbl.check_quit_condition()
    vim.wait(200)
end)
assert_ok(not quit_called, "should not quit when normal window exists (horizontal)")
close_sidebar()

-- Case 3: vertical sidebar only should quit
setup_position("left")
local normal_win_id = ensure_normal_window(state)
open_sidebar()
assert_ok(normal_win_id and vim.api.nvim_win_is_valid(normal_win_id), "normal window should exist before close (vertical)")

quit_called = with_qall_capture(function()
    vim.api.nvim_win_close(normal_win_id, true)
    vbl.check_quit_condition()
    vim.wait(200)
end)
assert_ok(quit_called, "should quit when only vertical sidebar remains")

-- Recover a normal window to close sidebar cleanly
normal_win_id = ensure_normal_window(state)
assert_ok(normal_win_id and vim.api.nvim_win_is_valid(normal_win_id), "normal window should be recoverable after vertical close")
close_sidebar()

-- Case 4: horizontal sidebar + placeholder only should quit
setup_position("top")
normal_win_id = ensure_normal_window(state)
open_sidebar()
placeholder_win_id = state.get_placeholder_win_id()
assert_ok(placeholder_win_id and vim.api.nvim_win_is_valid(placeholder_win_id), "placeholder should exist before close (horizontal)")

quit_called = with_qall_capture(function()
    if normal_win_id and vim.api.nvim_win_is_valid(normal_win_id) then
        vim.api.nvim_win_close(normal_win_id, true)
    end
    vbl.check_quit_condition()
    vim.wait(200)
end)
assert_ok(quit_called, "should quit when only horizontal sidebar/placeholder remain")

print("OK: quit condition check")
vim.cmd("qa")
