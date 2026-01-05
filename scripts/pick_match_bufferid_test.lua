local function assert_ok(condition, message)
    if not condition then
        error(message or "assertion failed")
    end
end

local function add_rtp_root()
    local cwd = vim.fn.getcwd()
    local rtp_root = vim.fn.fnamemodify(cwd, ":h:h")
    vim.opt.rtp:prepend(rtp_root)
end

add_rtp_root()
vim.o.shadafile = vim.fn.tempname()
vim.o.swapfile = false

local vbl = require('vertical-bufferline')
local state = require('vertical-bufferline.state')

-- Simulate hint_lines mapping directly to buffer_id (line_hints empty).
local buffer_id = 99
state.set_line_to_buffer_id({})
state.set_extended_picking_pick_chars(
    {},
    { a = buffer_id },
    {}
)

local match_count, match_hint = vbl._get_pick_char_match("a")
assert_ok(match_count == 1, "expected buffer_id match count")
assert_ok(match_hint == "a", "expected exact hint match")

print("pick match buffer_id test: ok")
vim.cmd("qa")
