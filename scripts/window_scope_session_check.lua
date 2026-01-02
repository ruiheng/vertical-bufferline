-- Automated sanity check for window-scoped session save/restore
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

local function find_group_by_name(groups_list, name)
    for _, group in ipairs(groups_list or {}) do
        if group.name == name then
            return group
        end
    end
    return nil
end

local function contains(tbl, val)
    for _, item in ipairs(tbl or {}) do
        if item == val then
            return true
        end
    end
    return false
end

add_rtp_root()

local vbl = require('vertical-bufferline')
vbl.setup({
    group_scope = "window",
    inherit_on_new_window = false,
    auto_create_groups = true,
    auto_add_new_buffers = true,
})

local groups = require('vertical-bufferline.groups')
local session = require('vertical-bufferline.session')
assert_ok(groups.is_window_scope_enabled(), "window scope not enabled (bufferline may be active)")

local file1 = write_temp_file({ "alpha" })
local file2 = write_temp_file({ "beta" })

vim.cmd("edit " .. vim.fn.fnameescape(file1))
local win1 = vim.api.nvim_get_current_win()
local buf1 = vim.api.nvim_get_current_buf()
groups.activate_window_context(win1, { seed_buffer_id = buf1 })
local group1_id = groups.create_group("Alpha")
groups.add_buffer_to_group(buf1, group1_id)
groups.set_active_group(group1_id)

vim.cmd("vsplit " .. vim.fn.fnameescape(file2))
local win2 = vim.api.nvim_get_current_win()
local buf2 = vim.api.nvim_get_current_buf()
groups.activate_window_context(win2, { seed_buffer_id = buf2 })
local group2_id = groups.create_group("Beta")
groups.add_buffer_to_group(buf2, group2_id)
groups.set_active_group(group2_id)

local session_data = session.collect_current_state()
vim.g.VerticalBufferlineSession = vim.json.encode(session_data)

groups.reset_window_contexts()
assert_ok(session.restore_state_from_global(), "session restore failed")

groups.activate_window_context(win1, { seed_buffer_id = buf1 })
local groups_win1 = groups.get_all_groups()
local alpha_group = find_group_by_name(groups_win1, "Alpha")
assert_ok(alpha_group, "win1 missing Alpha group after restore")
assert_ok(contains(alpha_group.buffers, buf1), "win1 Alpha group missing buf1 after restore")
assert_ok(not find_group_by_name(groups_win1, "Beta"), "win1 unexpectedly has Beta group")

groups.activate_window_context(win2, { seed_buffer_id = buf2 })
local groups_win2 = groups.get_all_groups()
local beta_group = find_group_by_name(groups_win2, "Beta")
assert_ok(beta_group, "win2 missing Beta group after restore")
assert_ok(contains(beta_group.buffers, buf2), "win2 Beta group missing buf2 after restore")
assert_ok(not find_group_by_name(groups_win2, "Alpha"), "win2 unexpectedly has Alpha group")

print("OK: window-scoped session save/restore works")
vim.cmd("qa")
