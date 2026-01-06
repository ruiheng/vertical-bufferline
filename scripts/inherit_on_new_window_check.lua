-- Automated sanity check for inherit_on_new_window behavior
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

local function find_group_by_name(groups_list, name)
    for _, group in ipairs(groups_list or {}) do
        if group.name == name then
            return group
        end
    end
    return nil
end

add_rtp_root()

local vbl = require('buffer-nexus')
vbl.setup({
    group_scope = "window",
    inherit_on_new_window = true,
    auto_create_groups = true,
    auto_add_new_buffers = true,
})

local groups = require('buffer-nexus.groups')
assert_ok(groups.is_window_scope_enabled(), "window scope should be enabled")

local file1 = write_temp_file({ "one" })
local file2 = write_temp_file({ "two" })

vim.cmd("edit " .. vim.fn.fnameescape(file1))
local win1 = vim.api.nvim_get_current_win()
local buf1 = vim.api.nvim_get_current_buf()
groups.activate_window_context(win1, { seed_buffer_id = buf1 })
local g1 = groups.create_group("Alpha")
groups.add_buffer_to_group(buf1, g1)
groups.set_active_group(g1)

vim.cmd("vsplit " .. vim.fn.fnameescape(file2))
local win2 = vim.api.nvim_get_current_win()
local buf2 = vim.api.nvim_get_current_buf()
groups.activate_window_context(win2, { seed_buffer_id = buf2 })

local data1 = groups.get_bn_groups_by_window(win1)
local data2 = groups.get_bn_groups_by_window(win2)
assert_ok(data1 ~= data2, "window scope should have separate contexts")

local groups_win2 = groups.get_all_groups()
assert_ok(find_group_by_name(groups_win2, "Alpha"), "new window should inherit Alpha group")

print("OK: inherit_on_new_window behavior")
vim.cmd("qa")
