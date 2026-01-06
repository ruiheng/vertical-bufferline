local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
    end
end

local function add_rtp_root()
    local cwd = vim.fn.getcwd()
    local rtp_root = vim.fn.fnamemodify(cwd, ":h:h")
    vim.opt.rtp:append(rtp_root)
end

add_rtp_root()
vim.o.shadafile = vim.fn.tempname()
vim.o.swapfile = false

local vbl = require('vertical-bufferline')
local groups = require('vertical-bufferline.groups')
local state = require('vertical-bufferline.state')

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

vbl.setup({ position = "left", floating = false })
groups.setup({ auto_add_new_buffers = false })

local path1 = tmpdir .. "/pin_a.lua"
local path2 = tmpdir .. "/b.lua"
local path3 = tmpdir .. "/c.lua"
vim.fn.writefile({ "a" }, path1)
vim.fn.writefile({ "b" }, path2)
vim.fn.writefile({ "c" }, path3)

vim.cmd("edit " .. vim.fn.fnameescape(path1))
local buf1 = vim.api.nvim_get_current_buf()
vim.cmd("edit " .. vim.fn.fnameescape(path2))
local buf2 = vim.api.nvim_get_current_buf()
vim.cmd("edit " .. vim.fn.fnameescape(path3))
local buf3 = vim.api.nvim_get_current_buf()

groups.add_buffer_to_group(buf1, "default")
groups.add_buffer_to_group(buf2, "default")
groups.add_buffer_to_group(buf3, "default")

state.set_buffer_pinned(buf1, true)

vim.api.nvim_set_current_buf(buf2)
assert_eq(vbl.statusline_label(), "[Default] 1/2", "statusline label should skip pinned buffer")

vim.api.nvim_set_current_buf(buf1)
assert_eq(vbl.statusline_label(), "[Default]", "pinned current buffer should omit position")

print("statusline label pinned test: ok")
vim.cmd("qa")
