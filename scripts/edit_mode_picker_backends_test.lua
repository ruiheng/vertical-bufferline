-- Automated check for edit-mode picker backends
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
add_dep_rtp(vim.fn.getcwd() .. "/.deps/snacks.nvim")
add_dep_rtp(vim.fn.getcwd() .. "/.deps/fzf-lua")

local vbl = require('vertical-bufferline')

local function close_edit_buffer()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
            local name = vim.api.nvim_buf_get_name(buf)
            if name == "vertical-bufferline://edit" then
                pcall(vim.api.nvim_buf_delete, buf, { force = true })
            end
        end
    end
end

local function open_and_assert_header(picker)
    close_edit_buffer()
    if picker == "fzf-lua" then
        vim.g.fzf_lua_server = "test"
    end
    vbl.setup({
        edit_mode = {
            picker = picker,
        },
    })
    require('vertical-bufferline.edit_mode').open()
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local expected = "picker = " .. picker
    local actual = nil
    local found = false
    for _, line in ipairs(lines) do
        if line:find("# <C-p>:", 1, true) then
            actual = line
        end
        if line:find(expected, 1, true) then
            found = true
        end
    end
    assert_ok(found, "expected header to mention " .. expected .. ", got: " .. tostring(actual))
end

open_and_assert_header("snacks")
open_and_assert_header("fzf-lua")

print("OK: edit-mode picker backends")
vim.cmd("qa")
