local function assert_ok(condition, message)
    if not condition then
        error(message or "assertion failed")
    end
end

local function add_rtp_root()
    local cwd = vim.fn.getcwd()
    local rtp_root = vim.fn.fnamemodify(cwd, ":h:h")
    vim.opt.rtp:prepend(rtp_root)
end

add_rtp_root()
vim.o.shadafile = vim.fn.tempname()
vim.o.swapfile = false

local vbl = require('buffer-nexus')
local groups = require('buffer-nexus.groups')
local state = require('buffer-nexus.state')
local bufferline_integration = require('buffer-nexus.bufferline-integration')

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

vbl.setup({ position = "left", floating = false, pick_chars = "abc" })
groups.setup({ auto_add_new_buffers = false })
bufferline_integration.is_available = function()
    return false
end

for i = 1, 2 do
    local path = string.format("%s/%03d.txt", tmpdir, i)
    vim.fn.writefile({ "x" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local buf_id = vim.api.nvim_get_current_buf()
    groups.add_buffer_to_group(buf_id, "default")
end

vbl.toggle()

vim.schedule(function()
    vim.api.nvim_feedkeys("\003", "tn", false)
end)
vbl.pick_buffer()

vim.wait(50)
assert_ok(not state.get_extended_picking_state().is_active, "expected pick mode to exit on Ctrl-C")

vbl.close_sidebar()

print("pick ctrl-c exit test: ok")
vim.cmd("qa")
