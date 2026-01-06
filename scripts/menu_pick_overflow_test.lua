local function assert_ok(condition, message)
    if not condition then
        error(message or "assertion failed")
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

local vbl = require('buffer-nexus')
local groups = require('buffer-nexus.groups')

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

vbl.setup({ position = "left", floating = false, pick_chars = "ab1" })
groups.setup({ auto_add_new_buffers = false })

local path1 = tmpdir .. "/one.lua"
local path2 = tmpdir .. "/two.lua"
local path3 = tmpdir .. "/three.lua"
vim.fn.writefile({ "a" }, path1)
vim.fn.writefile({ "b" }, path2)
vim.fn.writefile({ "c" }, path3)

vim.cmd("edit " .. vim.fn.fnameescape(path1))
local buf1 = vim.api.nvim_get_current_buf()
vim.cmd("edit " .. vim.fn.fnameescape(path2))
local buf2 = vim.api.nvim_get_current_buf()
vim.cmd("edit " .. vim.fn.fnameescape(path3))
local buf3 = vim.api.nvim_get_current_buf()

groups.add_buffer_to_group(buf1, "default")
groups.add_buffer_to_group(buf2, "default")
groups.add_buffer_to_group(buf3, "default")

local active_group = groups.get_active_group()
assert_ok(active_group and #active_group.buffers >= 3, "group should contain buffers")

local function get_upvalue(func, name)
    for i = 1, 50 do
        local up_name, value = debug.getupvalue(func, i)
        if not up_name then
            break
        end
        if up_name == name then
            return value
        end
    end
    return nil
end

local generate_buffer_pick_chars = get_upvalue(vbl.open_buffer_menu, "generate_buffer_pick_chars")
local assign_menu_pick_chars = get_upvalue(vbl.open_buffer_menu, "assign_menu_pick_chars")
assert_ok(type(generate_buffer_pick_chars) == "function", "generate_buffer_pick_chars should be accessible")
assert_ok(type(assign_menu_pick_chars) == "function", "assign_menu_pick_chars should be accessible")

local all_group_buffers = {}
for _, buf_id in ipairs(active_group.buffers) do
    table.insert(all_group_buffers, { buffer_id = buf_id, group_id = active_group.id })
end

local buffer_hints = generate_buffer_pick_chars(all_group_buffers, {}, active_group.id, true)
local has_multi = false
for _, hint in pairs(buffer_hints) do
    if type(hint) == "string" and #hint > 1 then
        has_multi = true
        local first_char = hint:sub(1, 1)
        assert_ok(not first_char:match("%d"), "multi-char hint should not start with digit")
    end
end

assert_ok(has_multi, "expected at least one multi-char hint")

local items = {}
local hint_set = {}
local unique_count = 0
for _, buf_id in ipairs(active_group.buffers) do
    local buf_name = vim.api.nvim_buf_get_name(buf_id)
    local filename = buf_name == "" and "[No Name]" or vim.fn.fnamemodify(buf_name, ":t")
    table.insert(items, { id = buf_id, name = filename })
end

assign_menu_pick_chars(items, buffer_hints)
local menu_has_multi = false
for _, item in ipairs(items) do
    assert_ok(item.hint and item.hint ~= "", "menu item should have hint")
    if not hint_set[item.hint] then
        hint_set[item.hint] = true
        unique_count = unique_count + 1
    end
    if #item.hint > 1 then
        menu_has_multi = true
        local first_char = item.hint:sub(1, 1)
        assert_ok(not first_char:match("%d"), "menu hint should not start with digit")
    end
end

assert_ok(unique_count == #items, "menu hints should be unique")
assert_ok(menu_has_multi, "menu should include multi-char hints")

print("menu pick overflow test: ok")
vim.cmd("qa")
