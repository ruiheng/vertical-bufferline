-- Automated sanity check for group save/load file round trip
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

local function name_counts(list)
    local counts = {}
    for _, group in ipairs(list or {}) do
        local name = group.name or ""
        counts[name] = (counts[name] or 0) + 1
    end
    return counts
end

local function assert_name_counts(expected, actual)
    for name, count in pairs(expected) do
        assert_ok(actual[name] == count, "group name count mismatch for '" .. name .. "'")
    end
    for name, count in pairs(actual) do
        assert_ok(expected[name] == count, "unexpected group name '" .. name .. "'")
    end
end

add_rtp_root()

local vbl = require('buffer-nexus')
vbl.setup({
    group_scope = "global",
    auto_create_groups = true,
    auto_add_new_buffers = true,
})

local groups = require('buffer-nexus.groups')

local file1 = write_temp_file({ "one" })
local file2 = write_temp_file({ "two" })
vim.cmd("edit " .. vim.fn.fnameescape(file1))
local buf1 = vim.api.nvim_get_current_buf()
vim.cmd("edit " .. vim.fn.fnameescape(file2))
local buf2 = vim.api.nvim_get_current_buf()

local g1 = groups.create_group("Alpha")
local g2 = groups.create_group("Beta")
groups.add_buffer_to_group(buf1, g1)
groups.add_buffer_to_group(buf2, g2)

local saved_groups = groups.get_all_groups()
local saved_counts = name_counts(saved_groups)

local save_path = vim.fn.tempname()
local save_result = vbl.save_groups_to_file(save_path)
assert_ok(save_result == 0, "expected save to return 0")

local saved_lines = vim.fn.readfile(save_path)
for _, line in ipairs(saved_lines) do
    assert_ok(not line:match("^%s*#"), "saved file should not contain header comments")
end

groups.create_group("Gamma")
vbl.load_groups_from_file(save_path)

local loaded_groups = groups.get_all_groups()
local loaded_counts = name_counts(loaded_groups)
assert_name_counts(saved_counts, loaded_counts)

local function buffer_in_group(buf_id, name)
    for _, group in ipairs(groups.find_buffer_groups(buf_id) or {}) do
        if group.name == name then
            return true
        end
    end
    return false
end

assert_ok(buffer_in_group(buf1, "Alpha"), "buf1 should be in Alpha after load")
assert_ok(buffer_in_group(buf2, "Beta"), "buf2 should be in Beta after load")

print("OK: groups file round trip")
vim.cmd("qa")
