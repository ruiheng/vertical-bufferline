-- Automated check for edit-mode handling unopened file paths
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

add_rtp_root()

local vbl = require('buffer-nexus')
vbl.setup({
    group_scope = "global",
    auto_create_groups = true,
    auto_add_new_buffers = true,
})

local groups = require('buffer-nexus.groups')
local edit_mode = require('buffer-nexus.edit_mode')

local file_path = write_temp_file({ "unopened" })
local abs_path = vim.fn.fnamemodify(file_path, ":p")

local edit_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, {
    "[Group] Alpha",
    abs_path,
})

edit_mode.apply(edit_buf)

local function find_group(name)
    for _, group in ipairs(groups.get_all_groups() or {}) do
        if group.name == name then
            return group
        end
    end
    return nil
end

local function group_has_path(group, target)
    for _, buf_id in ipairs(group.buffers or {}) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            local name = vim.api.nvim_buf_get_name(buf_id)
            if name == target then
                return true
            end
        end
    end
    return false
end

local alpha = find_group("Alpha")
assert_ok(alpha ~= nil, "expected Alpha group to be created")
assert_ok(group_has_path(alpha, abs_path), "expected unopened file to be added to Alpha")

print("OK: edit-mode unopened file")
vim.cmd("qa")
