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

vbl.setup({ position = "left", floating = false, pick_chars = "ab1" })
groups.setup({ auto_add_new_buffers = false })

local function find_upvalue(func, name, seen)
    if type(func) ~= "function" then
        return nil
    end
    seen = seen or {}
    if seen[func] then
        return nil
    end
    seen[func] = true
    for i = 1, 50 do
        local up_name, value = debug.getupvalue(func, i)
        if not up_name then
            break
        end
        if up_name == name then
            return value
        end
        if type(value) == "function" then
            local nested = find_upvalue(value, name, seen)
            if nested then
                return nested
            end
        end
    end
    return nil
end

local generate_extended_pick_chars = find_upvalue(vbl.refresh, "generate_extended_pick_chars")
assert_ok(type(generate_extended_pick_chars) == "function", "generate_extended_pick_chars should be accessible")

local line_to_buffer = {}
local line_group_context = {}
local line_count = 10
for i = 1, line_count do
    line_to_buffer[i] = i
    line_group_context[i] = "default"
end

local line_hints, hint_lines = generate_extended_pick_chars({}, line_to_buffer, line_group_context, "default", true)
local hint_set = {}
local max_len = 0
for _, hint in pairs(line_hints) do
    assert_ok(type(hint) == "string" and hint ~= "", "hint should be string")
    assert_ok(not hint_set[hint], "hints should be unique")
    hint_set[hint] = true
    if #hint > max_len then
        max_len = #hint
    end
    local first_char = hint:sub(1, 1)
    assert_ok(not first_char:match("%d"), "hint should not start with digit")
end

assert_ok(max_len >= 3, "expected extended hints length to exceed 2")

print("pick extended variable length test: ok")
vim.cmd("qa")
