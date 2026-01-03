-- Automated sanity check for path display helpers
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

local function mkdir_p(path)
    vim.fn.mkdir(path, "p")
end

local function write_file(path, lines)
    vim.fn.writefile(lines, path)
end

add_rtp_root()

local filename_utils = require('vertical-bufferline.filename_utils')

local tmpdir = vim.fn.tempname()
mkdir_p(tmpdir .. "/one/dir")
mkdir_p(tmpdir .. "/two/dir")

local path1 = tmpdir .. "/one/dir/config.lua"
local path2 = tmpdir .. "/two/dir/config.lua"
write_file(path1, { "a" })
write_file(path2, { "b" })

vim.cmd("edit " .. vim.fn.fnameescape(path1))
local buf1 = vim.api.nvim_get_current_buf()
vim.cmd("edit " .. vim.fn.fnameescape(path2))
local buf2 = vim.api.nvim_get_current_buf()

local unique_names = filename_utils.generate_unique_names({ buf1, buf2 })
assert_ok(unique_names[1] and unique_names[2], "unique name results should exist")
assert_ok(unique_names[1] ~= unique_names[2], "unique names should differ for same filename")

local long_path = tmpdir .. "/a/very/long/path/that/should/be/compressed/file.lua"
local compressed = filename_utils.compress_path_smart(long_path, 20, 1)
assert_ok(#compressed <= 20, "compressed path should respect max width")

print("OK: path display helpers")
vim.cmd("qa")
