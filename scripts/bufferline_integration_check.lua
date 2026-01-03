-- Automated sanity check for bufferline integration
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

local function add_bufferline_rtp()
    local cwd = vim.fn.getcwd()
    local bufferline_path = cwd .. "/vendor/bufferline.nvim"
    if vim.fn.isdirectory(bufferline_path) == 0 then
        print("SKIP: vendor/bufferline.nvim not found")
        vim.cmd("qa")
        return false
    end
    vim.opt.rtp:append(bufferline_path)
    return true
end

local function write_temp_file(lines)
    local name = vim.fn.tempname()
    vim.fn.writefile(lines, name)
    return name
end

add_rtp_root()
if not add_bufferline_rtp() then
    return
end

require('bufferline').setup({})

local vbl = require('vertical-bufferline')
vbl.setup({
    group_scope = "window",
    auto_create_groups = true,
    auto_add_new_buffers = true,
})

local groups = require('vertical-bufferline.groups')
assert_ok(groups.is_window_scope_enabled() == false, "window scope should be disabled with bufferline")

local file1 = write_temp_file({ "one" })
local file2 = write_temp_file({ "two" })

vim.cmd("edit " .. vim.fn.fnameescape(file1))
vim.cmd("vsplit " .. vim.fn.fnameescape(file2))

local group_id = groups.create_group("BuflineTest")
groups.set_active_group(group_id)
vbl.refresh("bufferline_integration_check")

print("OK: bufferline integration basic check")
vim.cmd("qa")
