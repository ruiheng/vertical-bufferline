-- Verify group switching with target window doesn't steal focus
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
})

local groups = require('buffer-nexus.groups')
local state = require('buffer-nexus.state')

local file1 = write_temp_file({ "one" })
vim.cmd("edit " .. vim.fn.fnameescape(file1))
local main_win = vim.api.nvim_get_current_win()
local initial_buf = vim.api.nvim_get_current_buf()

local picker_buf = vim.api.nvim_create_buf(false, true)
local picker_win = vim.api.nvim_open_win(picker_buf, true, {
    relative = "editor",
    width = 30,
    height = 5,
    row = 1,
    col = 1,
    style = "minimal",
    border = "single",
})

assert_ok(picker_win == vim.api.nvim_get_current_win(), "picker window should be current")

local group_id = groups.create_group("NoFocusGroup")
local display_number = nil
for _, group in ipairs(groups.get_all_groups()) do
    if group.id == group_id then
        display_number = group.display_number
        break
    end
end
assert_ok(display_number, "display number should exist for new group")

assert_ok(groups.switch_to_group_by_display_number(display_number, {
    target_win_id = main_win,
    skip_restore = true,
}), "switch_to_group_by_display_number should succeed")

assert_ok(vim.api.nvim_get_current_win() == picker_win, "focus should remain in picker window")

local active_group = groups.get_active_group()
assert_ok(active_group and active_group.id == group_id, "active group should be new group")
assert_ok(not vim.tbl_contains(active_group.buffers, initial_buf), "initial buffer should not be added to new group")

print("OK: picker group switch no focus check")
vim.cmd("qa")
