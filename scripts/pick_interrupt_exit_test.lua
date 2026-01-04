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

local vbl = require('vertical-bufferline')
local groups = require('vertical-bufferline.groups')
local state = require('vertical-bufferline.state')
local bufferline_integration = require('vertical-bufferline.bufferline-integration')

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

vbl.setup({ position = "left", floating = false, pick_chars = "abc" })
groups.setup({ auto_add_new_buffers = false })
bufferline_integration.is_available = function()
    return false
end

local buffers = {}
for i = 1, 3 do
    local path = string.format("%s/%03d.txt", tmpdir, i)
    vim.fn.writefile({ "x" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local buf_id = vim.api.nvim_get_current_buf()
    buffers[i] = buf_id
    groups.add_buffer_to_group(buf_id, "default")
end

vbl.toggle()

local function with_feedkeys(keys, callback)
    vim.schedule(function()
        vim.api.nvim_feedkeys(keys, "tn", false)
    end)
    callback()
end

-- Test: Enter with no exact match should exit
with_feedkeys("a\r", function()
    vbl.pick_buffer()
end)

vim.wait(50)
assert_ok(not state.get_extended_picking_state().is_active, "expected pick mode to exit on Enter without exact match")

-- Test: invalid char after prefix should exit
with_feedkeys("a!", function()
    vbl.pick_buffer()
end)

vim.wait(50)
assert_ok(not state.get_extended_picking_state().is_active, "expected pick mode to exit on invalid char after prefix")

vbl.close_sidebar()

print("pick interrupt exit test: ok")
vim.cmd("qa")
