-- Automated check for edit-mode insert path keymap
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

local function add_dep_rtp(path)
    if vim.fn.isdirectory(path) == 1 then
        vim.opt.rtp:append(path)
    end
end

add_rtp_root()
add_dep_rtp(vim.fn.getcwd() .. "/.deps/telescope.nvim")
add_dep_rtp(vim.fn.getcwd() .. "/.deps/mini.nvim")

local vbl = require('vertical-bufferline')
vbl.setup({
    edit_mode = {
        picker = "auto",
    },
})

local edit_mode = require('vertical-bufferline.edit_mode')

local function find_mapping(buf_id)
    local targets = { "<C-p>", "<C-P>" }
    for _, mode in ipairs({ "n", "i" }) do
        local maps = vim.api.nvim_buf_get_keymap(buf_id, mode)
        for _, map in ipairs(maps) do
            for _, target in ipairs(targets) do
                if map.lhs == target then
                    return true, mode
                end
            end
        end
    end
    return false, nil
end

edit_mode.open()
local buf_id = vim.api.nvim_get_current_buf()
local ok, mode = find_mapping(buf_id)
assert_ok(ok, "expected <C-p> mapping in edit buffer after first open")

-- Re-open existing edit buffer to ensure mapping is reapplied
edit_mode.open()
buf_id = vim.api.nvim_get_current_buf()
ok, mode = find_mapping(buf_id)
assert_ok(ok, "expected <C-p> mapping in edit buffer after re-open")

print("OK: edit-mode insert keymap")
vim.cmd("qa")
