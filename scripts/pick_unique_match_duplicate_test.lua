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

-- Simulate duplicate buffer lines mapped to different hints
local buffer_id = 42
state.set_line_to_buffer_id({
    [1] = buffer_id,
    [2] = buffer_id,
})
state.set_extended_picking_pick_chars(
    { [1] = "aa", [2] = "ab" },
    { aa = 1, ab = 2 },
    {}
)

local match_count, match_hint = vbl._get_pick_char_match("a")
assert_ok(match_count == 1, "expected unique buffer match count for duplicate lines")
assert_ok(match_hint ~= nil, "expected a matching hint")

print("pick unique match duplicate test: ok")
vim.cmd("qa")
