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
vim.o.shadafile = vim.fn.tempname()
vim.o.swapfile = false

local vbl = require('vertical-bufferline')
vbl.setup({
    auto_create_groups = true,
    auto_add_new_buffers = true,
    group_scope = "global",
})

local path = write_temp_file({ "menu modified" })
vim.cmd("edit " .. vim.fn.fnameescape(path))

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed" })
assert_ok(vim.api.nvim_buf_get_option(0, "modified"), "buffer should be modified")

vbl.open_buffer_menu()

local menu_buf = vim.api.nvim_get_current_buf()
local lines = vim.api.nvim_buf_get_lines(menu_buf, 0, -1, false)
local has_modified = false
for i, line in ipairs(lines) do
    if i > 1 and line:find("•", 1, true) then
        has_modified = true
        break
    end
end

assert_ok(has_modified, "menu should show modified indicator")

print("menu modified indicator test: ok")
vim.cmd("qa!")
