-- Automated sanity check for align_with_cursor behavior
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
    align_with_cursor = true,
    group_scope = "global",
    auto_create_groups = true,
    auto_add_new_buffers = true,
    position = "left",
})

local state = require('vertical-bufferline.state')

local lines = {}
for i = 1, 80 do
    lines[i] = string.format("line %d", i)
end
local file1 = write_temp_file(lines)

vim.cmd("edit " .. vim.fn.fnameescape(file1))
vbl.toggle()

local sidebar_win = state.get_win_id()
assert_ok(sidebar_win and vim.api.nvim_win_is_valid(sidebar_win), "sidebar should be open")

vim.api.nvim_win_set_cursor(0, { 1, 0 })
vbl.refresh("align_cursor_top")
assert_ok(state.get_line_offset() == 0, "line offset should be 0 near top")

vim.api.nvim_win_set_cursor(0, { 40, 0 })
vbl.refresh("align_cursor_down")
assert_ok(state.get_line_offset() > 0, "line offset should increase when cursor moves")

require('vertical-bufferline.config').settings.align_with_cursor = false
vbl.refresh("align_cursor_disabled")
assert_ok(state.get_line_offset() == 0, "line offset should reset when alignment is disabled")

vbl.close_sidebar()
print("OK: align_with_cursor behavior")
vim.cmd("qa")
