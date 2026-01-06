local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
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
local state = require('buffer-nexus.state')

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

vbl.setup({
    position = "left",
    floating = false,
    show_history = "yes",
})
groups.setup({ auto_add_new_buffers = false })

local function write_file(name, contents)
    local path = tmpdir .. "/" .. name
    vim.fn.writefile(contents, path)
    return path
end

local function open_and_track(path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local buf_id = vim.api.nvim_get_current_buf()
    groups.add_buffer_to_group(buf_id, "default")
    groups.sync_group_history_with_current("default", buf_id)
    return buf_id
end

local buf_a = open_and_track(write_file("a.lua", { "a" }))
local buf_b = open_and_track(write_file("b.lua", { "b" }))
local buf_c = open_and_track(write_file("c.lua", { "c" }))
local buf_d = open_and_track(write_file("d.lua", { "d" }))

state.set_buffer_pinned(buf_c, true)

vbl.toggle()
vbl.refresh("history_nav_pinned_test")

local display_history = state.get_history_display_buffers()
assert_eq(display_history[1], buf_d, "display history should start with current buffer")
assert_eq(display_history[2], buf_b, "display history should skip pinned buffers")
assert_eq(display_history[3], buf_a, "display history should include older buffers")

vbl.switch_to_history_file(2)
assert_eq(vim.api.nvim_get_current_buf(), buf_a, "history position 2 should match displayed list")

vbl.close_sidebar()
print("history nav pinned test: ok")
vim.cmd("qa")
