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

local vbl = require('vertical-bufferline')
local groups = require('vertical-bufferline.groups')

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

vbl.setup({ position = "left", floating = false, pick_chars = "ab1" })
groups.setup({ auto_add_new_buffers = false })

local buffers = {}
for i = 1, 9 do
    local path = string.format("%s/file_%02d.lua", tmpdir, i)
    vim.fn.writefile({ "x" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local buf_id = vim.api.nvim_get_current_buf()
    buffers[i] = buf_id
    groups.add_buffer_to_group(buf_id, "default")
end

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
assert_ok(type(generate_buffer_pick_chars) == "function", "generate_buffer_pick_chars should be accessible")

local active_group = groups.get_active_group()
local all_group_buffers = {}
for _, buf_id in ipairs(active_group.buffers) do
    table.insert(all_group_buffers, { buffer_id = buf_id, group_id = active_group.id })
end

local buffer_hints = generate_buffer_pick_chars(all_group_buffers, {}, active_group.id, true)
local hint_set = {}
local max_len = 0
for _, hint in pairs(buffer_hints) do
    assert_ok(type(hint) == "string" and hint ~= "", "hint should be string")
    assert_ok(not hint_set[hint], "hints should be unique")
    hint_set[hint] = true
    if #hint > max_len then
        max_len = #hint
    end
end

assert_ok(max_len >= 3, "expected hint length to exceed 2")

print("pick char variable length test: ok")
vim.cmd("qa")
