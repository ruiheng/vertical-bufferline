-- Automated sanity check for window-scoped groups
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

local vbl = require('vertical-bufferline')
vbl.setup({
    group_scope = "window",
    inherit_on_new_window = false,
    auto_create_groups = true,
    auto_add_new_buffers = true,
})

local groups = require('vertical-bufferline.groups')
assert_ok(groups.is_window_scope_enabled(), "window scope not enabled (bufferline may be active)")

local file1 = write_temp_file({ "one" })
local file2 = write_temp_file({ "two" })

vim.cmd("edit " .. vim.fn.fnameescape(file1))
local win1 = vim.api.nvim_get_current_win()
groups.activate_window_context(win1)
local buf1 = vim.api.nvim_get_current_buf()

vim.cmd("vsplit " .. vim.fn.fnameescape(file2))
local win2 = vim.api.nvim_get_current_win()
groups.activate_window_context(win2)
local buf2 = vim.api.nvim_get_current_buf()

local data1 = groups.get_vbl_groups_by_window(win1)
local data2 = groups.get_vbl_groups_by_window(win2)

assert_ok(data1 ~= data2, "expected separate groups data per window")

local function find_default_group(data)
    for _, group in ipairs(data.groups or {}) do
        if group.id == data.default_group_id then
            return group
        end
    end
    return nil
end

local function contains(tbl, val)
    for _, item in ipairs(tbl or {}) do
        if item == val then
            return true
        end
    end
    return false
end

local default1 = find_default_group(data1)
local default2 = find_default_group(data2)
assert_ok(default1 and default2, "missing default group in one or more contexts")

assert_ok(contains(default1.buffers, buf1), "win1 default group missing buf1")
assert_ok(not contains(default1.buffers, buf2), "win1 default group unexpectedly has buf2")
assert_ok(contains(default2.buffers, buf2), "win2 default group missing buf2")
assert_ok(not contains(default2.buffers, buf1), "win2 default group unexpectedly has buf1")

vbl.toggle()
local state = require('vertical-bufferline.state')
local sidebar_win = state.get_win_id()
assert_ok(sidebar_win and vim.api.nvim_win_is_valid(sidebar_win), "sidebar window not created")
local sidebar_data = groups.get_vbl_groups_by_window(sidebar_win)
local current_data = groups.get_vbl_groups_by_window(win2)
assert_ok(sidebar_data == current_data, "sidebar window should not create a separate context")

vim.api.nvim_set_current_win(win1)
vbl.refresh("window_scope_check_win1")
local active_after_win1 = groups.get_active_group()
assert_ok(active_after_win1 and contains(active_after_win1.buffers, buf1), "win1 active group missing buf1 after refresh")
assert_ok(not contains(active_after_win1.buffers, buf2), "win1 active group unexpectedly has buf2 after refresh")

vim.api.nvim_set_current_win(win2)
vbl.refresh("window_scope_check_win2")
local active_after_win2 = groups.get_active_group()
assert_ok(active_after_win2 and contains(active_after_win2.buffers, buf2), "win2 active group missing buf2 after refresh")
assert_ok(not contains(active_after_win2.buffers, buf1), "win2 active group unexpectedly has buf1 after refresh")

print("OK: window-scoped groups are isolated and sidebar refresh stays in main window context")
vim.cmd("qa")
