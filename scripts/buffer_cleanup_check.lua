-- Automated sanity check for buffer cleanup behavior
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

local function contains(tbl, val)
    for _, item in ipairs(tbl or {}) do
        if item == val then
            return true
        end
    end
    return false
end

add_rtp_root()

local vbl = require('buffer-nexus')
vbl.setup({
    group_scope = "global",
    auto_create_groups = true,
    auto_add_new_buffers = true,
})

local groups = require('buffer-nexus.groups')

local file1 = write_temp_file({ "one" })
local file2 = write_temp_file({ "two" })

vim.cmd("edit " .. vim.fn.fnameescape(file1))
local buf1 = vim.api.nvim_get_current_buf()
vim.cmd("edit " .. vim.fn.fnameescape(file2))
local buf2 = vim.api.nvim_get_current_buf()

local active = groups.get_active_group()
assert_ok(active ~= nil, "active group should exist")

local history_before = groups.get_group_history(active.id)
assert_ok(contains(history_before, buf2), "history should include latest buffer")

vim.api.nvim_buf_delete(buf2, { force = true })

groups.cleanup_invalid_buffers()
groups.remove_buffer_from_history(buf2)

local active_after = groups.get_active_group()
assert_ok(active_after ~= nil, "active group should still exist")
assert_ok(not contains(active_after.buffers, buf2), "deleted buffer should be removed from group")

local history_after = groups.get_group_history(active_after.id)
assert_ok(not contains(history_after, buf2), "deleted buffer should be removed from history")

print("OK: buffer cleanup behavior")
vim.cmd("qa")
