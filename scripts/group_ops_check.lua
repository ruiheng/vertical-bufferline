-- Automated sanity check for group operations
local function assert_ok(condition, message)
    if not condition then
        error(message, 2)
    end
end

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)), 2)
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

local function find_group_by_name(groups_list, name)
    for _, group in ipairs(groups_list or {}) do
        if group.name == name then
            return group
        end
    end
    return nil
end

add_rtp_root()

local vbl = require('buffer-nexus')
vbl.setup({
    auto_create_groups = true,
    auto_add_new_buffers = true,
    group_scope = "global",
})

local groups = require('buffer-nexus.groups')

local file1 = write_temp_file({ "one" })
vim.cmd("edit " .. vim.fn.fnameescape(file1))

local g1 = groups.create_group("Alpha")
local g2 = groups.create_group("Beta")

assert_ok(find_group_by_name(groups.get_all_groups(), "Alpha"), "Alpha group should exist")
assert_ok(find_group_by_name(groups.get_all_groups(), "Beta"), "Beta group should exist")

assert_ok(groups.set_active_group(g1), "should switch to Alpha")
assert_eq(groups.get_active_group().name, "Alpha", "active group should be Alpha")

assert_ok(groups.set_active_group(g2), "should switch to Beta")
assert_eq(groups.get_active_group().name, "Beta", "active group should be Beta")

assert_ok(groups.move_group_up(g2), "should move Beta up")
local list_after_move = groups.get_all_groups()
for idx, group in ipairs(list_after_move) do
    assert_eq(group.display_number, idx, "display_number should match index")
end

assert_ok(groups.delete_group(g1), "should delete Alpha")
assert_ok(find_group_by_name(groups.get_all_groups(), "Alpha") == nil, "Alpha group should be deleted")

print("OK: group operations check")
vim.cmd("qa")
