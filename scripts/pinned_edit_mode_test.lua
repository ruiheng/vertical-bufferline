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

local groups = require('vertical-bufferline.groups')
local edit_mode = require('vertical-bufferline.edit_mode')
local state = require('vertical-bufferline.state')

groups.setup({ auto_add_new_buffers = false })

local function create_named_buffer(name)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.bo[buf].swapfile = false
    vim.api.nvim_buf_set_name(buf, name)
    return buf
end

local buf1 = create_named_buffer(vim.fn.tempname() .. "_pin_a.lua")
local buf2 = create_named_buffer(vim.fn.tempname() .. "_pin.lua")
local buf3 = create_named_buffer(vim.fn.tempname() .. "_nopin.lua")

local edit_buf = vim.api.nvim_create_buf(false, true)
vim.bo[edit_buf].swapfile = false
local lines = {
    "[Group] Default",
    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf1), ":.") .. " [pin=a]",
    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf2), ":.") .. " [pin]",
    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf3), ":."),
}
vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, lines)

edit_mode.apply(edit_buf)

assert_eq(state.is_buffer_pinned(buf1), true, "buf1 should be pinned")
assert_eq(state.get_buffer_pin_char(buf1), "a", "buf1 pin char should be 'a'")
assert_eq(state.is_buffer_pinned(buf2), true, "buf2 should be pinned")
assert_eq(state.get_buffer_pin_char(buf2), nil, "buf2 pin char should be nil")
assert_eq(state.is_buffer_pinned(buf3), false, "buf3 should not be pinned")
assert_eq(state.get_buffer_pin_char(buf3), nil, "buf3 pin char should be nil")

print("pinned edit-mode test: ok")
vim.cmd("qa")
