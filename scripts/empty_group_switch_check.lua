-- Verify switching to an empty group creates a new buffer (matching create_group behavior)
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

local file1 = write_temp_file({ "one" })
vim.cmd("edit " .. vim.fn.fnameescape(file1))
local initial_buf = vim.api.nvim_get_current_buf()

local new_group_id = groups.create_group("EmptyTarget")
local display_number = nil
for _, group in ipairs(groups.get_all_groups()) do
    if group.id == new_group_id then
        display_number = group.display_number
        break
    end
end

assert_ok(display_number, "display number should exist for new group")
assert_ok(groups.switch_to_group_by_display_number(display_number), "switch_to_group_by_display_number should succeed")

local active_group = groups.get_active_group()
assert_ok(active_group and active_group.id == new_group_id, "active group should be new group")

local current_buf = vim.api.nvim_get_current_buf()
assert_ok(current_buf ~= initial_buf, "switching to empty group should change current buffer")
assert_ok(vim.api.nvim_buf_is_valid(current_buf), "current buffer should be valid")
assert_ok(vim.tbl_contains(active_group.buffers, current_buf), "current buffer should be added to empty group")
assert_ok(#active_group.buffers == 1, "empty group should get a single new buffer")

print("OK: empty group switch check")
vim.cmd("qa")
