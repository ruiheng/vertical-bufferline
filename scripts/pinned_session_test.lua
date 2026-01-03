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

local session = require('vertical-bufferline.session')
local groups = require('vertical-bufferline.groups')
local state = require('vertical-bufferline.state')

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")
groups.setup({ auto_add_new_buffers = false })

local path1 = tmpdir .. "/pin_a.lua"
local path2 = tmpdir .. "/pin.lua"
vim.fn.writefile({ "a" }, path1)
vim.fn.writefile({ "b" }, path2)

vim.cmd("edit " .. vim.fn.fnameescape(path1))
local buf1 = vim.api.nvim_get_current_buf()
vim.cmd("edit " .. vim.fn.fnameescape(path2))
local buf2 = vim.api.nvim_get_current_buf()

groups.add_buffer_to_group(buf1, "default")
groups.add_buffer_to_group(buf2, "default")

state.set_buffer_pinned(buf1, true)
state.set_buffer_pin_char(buf1, "a")
state.set_buffer_pinned(buf2, true)

local session_data = session.collect_current_state()
vim.g.VerticalBufferlineSession = vim.json.encode(session_data)

state.clear_pinned_buffers()

assert_eq(session.restore_state_from_global(), true, "session restore failed")

local function find_buf_by_name(target)
    for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            local name = vim.api.nvim_buf_get_name(buf_id)
            if name == target then
                return buf_id
            end
        end
    end
    return nil
end

local restored_buf1 = find_buf_by_name(path1)
local restored_buf2 = find_buf_by_name(path2)

assert_eq(state.is_buffer_pinned(restored_buf1), true, "buf1 should be pinned after restore")
assert_eq(state.get_buffer_pin_char(restored_buf1), "a", "buf1 pin char should restore")
assert_eq(state.is_buffer_pinned(restored_buf2), true, "buf2 should be pinned after restore")
assert_eq(state.get_buffer_pin_char(restored_buf2), nil, "buf2 pin char should be nil after restore")

print("pinned session test: ok")
vim.cmd("qa")
