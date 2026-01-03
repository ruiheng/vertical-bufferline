-- Automated smoke check for pick/highlight behavior
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

local state = require('vertical-bufferline.state')

local file1 = write_temp_file({ "one" })
local file2 = write_temp_file({ "two" })
vim.cmd("edit " .. vim.fn.fnameescape(file1))
vim.cmd("edit " .. vim.fn.fnameescape(file2))

vbl.toggle()
assert_ok(state.get_win_id() ~= nil, "sidebar should be open")

vbl.apply_picking_highlights()
local vbl_pick = vim.api.nvim_get_hl(0, { name = "VBufferLinePick" })
assert_ok(type(vbl_pick) == "table", "VBufferLinePick highlight should exist")

state.set_extended_picking_active(true)
state.set_extended_picking_mode("switch")
vbl.refresh("pick_highlight_smoke")
local hint_lines = state.get_extended_picking_state().hint_lines or {}
assert_ok(next(hint_lines) ~= nil, "pick hints should be generated")

vbl.close_sidebar()
print("OK: pick/highlight smoke")
vim.cmd("qa")
