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

local vbl = require('buffer-nexus')
local groups = require('buffer-nexus.groups')
local state = require('buffer-nexus.state')

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

vbl.setup({ position = "left", floating = false })
groups.setup({ auto_add_new_buffers = false })

local path1 = tmpdir .. "/pin_a.lua"
local path2 = tmpdir .. "/other.lua"
vim.fn.writefile({ "a" }, path1)
vim.fn.writefile({ "b" }, path2)

vim.cmd("edit " .. vim.fn.fnameescape(path1))
local buf1 = vim.api.nvim_get_current_buf()
vim.cmd("edit " .. vim.fn.fnameescape(path2))
local buf2 = vim.api.nvim_get_current_buf()

groups.add_buffer_to_group(buf1, "default")
groups.add_buffer_to_group(buf2, "default")

state.set_buffer_pinned(buf1, true)
state.set_buffer_pin_char(buf1, "a")

vbl.toggle()

state.set_extended_picking_active(true)
state.set_extended_picking_mode("switch")
vbl.refresh("test_pick_char")

local hint_lines = state.get_extended_picking_state().hint_lines or {}
assert_eq(hint_lines["a"], buf1, "pinned pick char should map to pinned buffer")

vbl.close_sidebar()

print("pinned pick char test: ok")
vim.cmd("qa")
