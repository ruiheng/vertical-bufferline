-- Automated sanity check for edit-mode folding
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

add_rtp_root()

local vbl = require('vertical-bufferline')
vbl.setup({
    auto_create_groups = true,
    auto_add_new_buffers = true,
})

local edit_mode = require('vertical-bufferline.edit_mode')
edit_mode.open()

local buf_id = vim.api.nvim_get_current_buf()
assert_ok(vim.bo[buf_id].filetype == "vertical-bufferline-edit", "edit mode buffer not active")

local ok, result = pcall(function()
    return edit_mode.foldexpr(1)
end)
assert_ok(ok, "foldexpr errored: " .. tostring(result))

print("OK: edit-mode foldexpr works")
vim.cmd("qa!")
