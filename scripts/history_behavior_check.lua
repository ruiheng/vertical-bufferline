-- Automated sanity check for history behavior
local function assert_ok(condition, message)
    if not condition then
        error(message, 2)
    end
end

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)), 2)
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
    position = "left",
    show_history = "auto",
    history_size = 2,
    history_auto_threshold = 2,
})

local config = require('buffer-nexus.config')
local groups = require('buffer-nexus.groups')

local file1 = write_temp_file({ "one" })
local file2 = write_temp_file({ "two" })
local file3 = write_temp_file({ "three" })

vim.cmd("edit " .. vim.fn.fnameescape(file1))
local buf1 = vim.api.nvim_get_current_buf()
vim.cmd("edit " .. vim.fn.fnameescape(file2))
local buf2 = vim.api.nvim_get_current_buf()
vim.cmd("edit " .. vim.fn.fnameescape(file3))
local buf3 = vim.api.nvim_get_current_buf()

local active = groups.get_active_group()
assert_ok(active ~= nil, "active group should exist")

local history = groups.get_group_history(active.id)
assert_ok(#history <= 2, "history should respect history_size")
assert_eq(history[1], buf3, "most recent buffer should be first in history")
assert_eq(history[2], buf2, "second most recent buffer should be second in history")

config.settings.show_history = "yes"
assert_ok(groups.should_show_history(active.id), "show_history=yes should always show history")

config.settings.show_history = "no"
assert_ok(not groups.should_show_history(active.id), "show_history=no should never show history")

config.settings.show_history = "auto"
assert_ok(groups.should_show_history(active.id), "show_history=auto should show when threshold met")

print("OK: history behavior check")
vim.cmd("qa")
