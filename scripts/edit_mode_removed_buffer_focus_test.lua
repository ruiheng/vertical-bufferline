-- Automated check for edit-mode buffer focus after removing current buffer
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

local edit_mode = require('buffer-nexus.edit_mode')

local file1 = write_temp_file({ "one" })
local file2 = write_temp_file({ "two" })
vim.cmd("edit " .. vim.fn.fnameescape(file1))
local buf1 = vim.api.nvim_get_current_buf()
vim.cmd("edit " .. vim.fn.fnameescape(file2))
local buf2 = vim.api.nvim_get_current_buf()
vim.api.nvim_set_current_buf(buf1)

local edit_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, {
    "[Group] Alpha",
    vim.fn.fnamemodify(file2, ":p"),
})
vim.api.nvim_buf_set_var(edit_buf, "vbl_edit_prev_buf", buf1)
vim.api.nvim_buf_set_var(edit_buf, "vbl_edit_prev_win", vim.api.nvim_get_current_win())

edit_mode.apply(edit_buf)

vim.wait(300, function()
    return vim.api.nvim_get_current_buf() ~= buf1
end, 20)

assert_ok(vim.api.nvim_get_current_buf() == buf2, "expected focus to switch to remaining buffer")

print("OK: edit-mode focus after removal")
vim.cmd("qa")
