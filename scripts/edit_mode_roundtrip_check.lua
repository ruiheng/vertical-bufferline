-- Automated sanity check for edit-mode round trip
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
    group_scope = "global",
    auto_create_groups = true,
    auto_add_new_buffers = true,
})

local groups = require('vertical-bufferline.groups')
local edit_mode = require('vertical-bufferline.edit_mode')

local file1 = write_temp_file({ "one" })
local file2 = write_temp_file({ "two" })
vim.cmd("edit " .. vim.fn.fnameescape(file1))
local buf1 = vim.api.nvim_get_current_buf()
vim.cmd("edit " .. vim.fn.fnameescape(file2))
local buf2 = vim.api.nvim_get_current_buf()

local g1 = groups.create_group("Alpha")
local g2 = groups.create_group("Beta")
groups.add_buffer_to_group(buf1, g1)
groups.add_buffer_to_group(buf2, g2)

local before = groups.get_all_groups()
vbl.copy_groups_to_register()
local reg = vim.fn.getreg('"')
assert_ok(reg and reg ~= "", "register should contain edit-mode text")

local edit_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, vim.split(reg, "\n", { plain = true }))
edit_mode.apply(edit_buf)

local after = groups.get_all_groups()
assert_ok(#after == #before, "group count should match after round trip")

local function by_name(list)
    local map = {}
    for _, group in ipairs(list or {}) do
        map[group.name] = group
    end
    return map
end

local before_map = by_name(before)
local after_map = by_name(after)
assert_ok(after_map["Alpha"] and after_map["Beta"], "expected groups should exist after round trip")
assert_ok(#(after_map["Alpha"].buffers or {}) >= 1, "Alpha should keep buffers after round trip")
assert_ok(#(after_map["Beta"].buffers or {}) >= 1, "Beta should keep buffers after round trip")

print("OK: edit-mode round trip")
vim.cmd("qa")
