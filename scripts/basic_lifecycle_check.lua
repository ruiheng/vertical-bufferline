-- Automated sanity check for basic lifecycle (setup/toggle/refresh)
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

local function write_temp_file(lines)
    local name = vim.fn.tempname()
    vim.fn.writefile(lines, name)
    return name
end

add_rtp_root()

local vbl = require('buffer-nexus')
vbl.setup({
    auto_create_groups = true,
    auto_add_new_buffers = true,
    group_scope = "global",
    floating = false,
})

local state = require('buffer-nexus.state')
local groups = require('buffer-nexus.groups')

local file1 = write_temp_file({ "one" })
vim.cmd("edit " .. vim.fn.fnameescape(file1))

assert_ok(groups.get_active_group() ~= nil, "active group should exist after setup")

vbl.toggle()
local win_id = state.get_win_id()
assert_ok(win_id and vim.api.nvim_win_is_valid(win_id), "sidebar should open after toggle")

vbl.refresh("basic_lifecycle_refresh_1")
assert_ok(state.get_win_id() == win_id, "sidebar win should remain after refresh")

vbl.toggle()
assert_ok(state.get_win_id() == nil, "sidebar should close after toggle")

vbl.toggle()
local win_id2 = state.get_win_id()
assert_ok(win_id2 and vim.api.nvim_win_is_valid(win_id2), "sidebar should reopen after toggle")

vbl.close_sidebar()
assert_ok(state.get_win_id() == nil, "sidebar should close after close_sidebar")

print("OK: basic lifecycle check")
vim.cmd("qa")
