-- Verify focus does not remain in horizontal placeholder window
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
    position = "top",
})

local state = require('buffer-nexus.state')

local file1 = write_temp_file({ "one" })
vim.cmd("edit " .. vim.fn.fnameescape(file1))

vbl.toggle()
local placeholder_win_id = state.get_placeholder_win_id()
assert_ok(placeholder_win_id and vim.api.nvim_win_is_valid(placeholder_win_id), "placeholder window should exist")

vim.api.nvim_set_current_win(placeholder_win_id)
vim.wait(700, function()
    return vim.api.nvim_get_current_win() ~= placeholder_win_id
end)

assert_ok(vim.api.nvim_get_current_win() ~= placeholder_win_id, "focus should redirect away from placeholder")

print("OK: horizontal focus redirect check")
vim.cmd("qa")
