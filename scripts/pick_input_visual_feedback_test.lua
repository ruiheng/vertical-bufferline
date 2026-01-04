local function assert_ok(condition, message)
    if not condition then
        error(message or "assertion failed")
    end
end

local function add_rtp_root()
    local cwd = vim.fn.getcwd()
    local rtp_root = vim.fn.fnamemodify(cwd, ":h:h")
    vim.opt.rtp:prepend(rtp_root)
end

add_rtp_root()
vim.o.shadafile = vim.fn.tempname()
vim.o.swapfile = false

local vbl = require('vertical-bufferline')
local groups = require('vertical-bufferline.groups')
local state = require('vertical-bufferline.state')
local bufferline_integration = require('vertical-bufferline.bufferline-integration')

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

vbl.setup({ position = "left", floating = false, pick_chars = "ab1" })
groups.setup({ auto_add_new_buffers = false })
bufferline_integration.is_available = function()
    return false
end

local buffers = {}
for i = 1, 4 do
    local path = string.format("%s/%03d.txt", tmpdir, i)
    vim.fn.writefile({ "x" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local buf_id = vim.api.nvim_get_current_buf()
    buffers[i] = buf_id
    groups.add_buffer_to_group(buf_id, "default")
end

vbl.toggle()

state.set_extended_picking_active(true)
state.set_extended_picking_mode("switch")
state.set_was_picking(false)
vbl.refresh("pick_visual_setup")
vbl._update_pick_display("")

local target_buf = nil
local target_hint = nil
local hint_lines = state.get_extended_picking_state().hint_lines or {}
for hint, buf_id in pairs(hint_lines) do
    if type(hint) == "string" and #hint > 1 then
        target_buf = buf_id
        target_hint = hint
        break
    end
end

assert_ok(target_buf and target_hint, "expected multi-char hint for visual test")

local target_line = nil
local line_to_buffer = state.get_line_to_buffer_id()
for line_num, buf_id in pairs(line_to_buffer or {}) do
    if buf_id == target_buf then
        target_line = line_num
        break
    end
end

assert_ok(target_line, "expected target buffer line for visual test")

local sidebar_buf = state.get_buf_id()
assert_ok(sidebar_buf and vim.api.nvim_buf_is_valid(sidebar_buf), "sidebar buffer should be valid")

local before_lines = vim.api.nvim_buf_get_lines(sidebar_buf, 0, -1, false)
local before_line = before_lines[target_line] or ""
local hint_pos = before_line:find(target_hint, 1, true)
assert_ok(hint_pos, "expected full hint in line before input")

local nonmatch_hint = nil
local nonmatch_line = nil
local nonmatch_pos = nil
local line_hints = state.get_extended_picking_state().line_hints or {}
for line_num, hint in pairs(line_hints) do
    if hint:sub(1, 1) ~= target_hint:sub(1, 1) then
        local line = before_lines[line_num]
        local pos = line and line:find(hint, 1, true)
        if pos then
            nonmatch_hint = hint
            nonmatch_line = line_num
            nonmatch_pos = pos
            break
        end
    end
end

local prefix = target_hint:sub(1, 1)
state.set_extended_picking_input_prefix(prefix)
vbl._update_pick_display(prefix)
vim.wait(20)

local after_line = vim.api.nvim_buf_get_lines(sidebar_buf, target_line - 1, target_line, false)[1] or ""
local prefix_spaces = string.rep(" ", #prefix)
assert_ok(after_line:sub(hint_pos, hint_pos + #prefix - 1) == prefix_spaces, "expected prefix to be replaced with spaces")
assert_ok(after_line:sub(hint_pos + #prefix, hint_pos + #target_hint - 1) == target_hint:sub(2), "expected suffix to remain after prefix input")

if nonmatch_hint then
    local after_nonmatch = vim.api.nvim_buf_get_lines(sidebar_buf, nonmatch_line - 1, nonmatch_line, false)[1] or ""
    local expected_spaces = string.rep(" ", #nonmatch_hint)
    assert_ok(after_nonmatch:sub(nonmatch_pos, nonmatch_pos + #nonmatch_hint - 1) == expected_spaces, "expected non-matching hint to be blanked")
end

vbl.close_sidebar()

print("pick input visual feedback test: ok")
vim.cmd("qa")
