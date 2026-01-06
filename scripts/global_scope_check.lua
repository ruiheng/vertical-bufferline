-- Automated sanity check for global scope behavior
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
    group_scope = "global",
    auto_create_groups = true,
    auto_add_new_buffers = true,
})

local groups = require('buffer-nexus.groups')
assert_ok(not groups.is_window_scope_enabled(), "window scope should be disabled in global mode")

local file1 = write_temp_file({ "one" })
local file2 = write_temp_file({ "two" })

vim.cmd("edit " .. vim.fn.fnameescape(file1))
local win1 = vim.api.nvim_get_current_win()
vim.cmd("vsplit " .. vim.fn.fnameescape(file2))
local win2 = vim.api.nvim_get_current_win()

local data1 = groups.get_bn_groups_by_window(win1)
local data2 = groups.get_bn_groups_by_window(win2)
assert_ok(data1 == data2, "global scope should share group data across windows")

local active = groups.get_active_group()
assert_ok(active ~= nil, "active group should exist")
assert_ok(#active.buffers >= 2, "global group should include buffers from both windows")

print("OK: global scope behavior")
vim.cmd("qa")
