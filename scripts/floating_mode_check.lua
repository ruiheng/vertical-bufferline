-- Automated sanity check for floating mode
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
    floating = true,
    position = "right",
    group_scope = "global",
    auto_create_groups = true,
    auto_add_new_buffers = true,
})

local state = require('buffer-nexus.state')

local file1 = write_temp_file({ "one" })
vim.cmd("edit " .. vim.fn.fnameescape(file1))

vbl.toggle()
local win_id = state.get_win_id()
assert_ok(win_id and vim.api.nvim_win_is_valid(win_id), "sidebar should open")

local config = vim.api.nvim_win_get_config(win_id)
assert_ok(config.relative ~= "", "floating window should have relative config")
assert_ok(config.focusable == false, "floating window should be non-focusable")

vbl.close_sidebar()
assert_ok(state.get_win_id() == nil, "sidebar should close")

print("OK: floating mode")
vim.cmd("qa")
