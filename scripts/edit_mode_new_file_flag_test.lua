-- Automated check for edit-mode [new] flag behavior
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

local function ensure_missing(path)
    if vim.loop.fs_stat(path) then
        vim.fn.delete(path)
    end
end

add_rtp_root()

local vbl = require('vertical-bufferline')
vbl.setup({
    group_scope = "global",
    auto_create_groups = true,
    auto_add_new_buffers = true,
})

local groups = require('vertical-bufferline.groups')
local edit_mode = require('vertical-bufferline.edit_mode')

local missing_path = vim.fn.tempname() .. "_missing"
local new_path = vim.fn.tempname() .. "_new"
ensure_missing(missing_path)
ensure_missing(new_path)

local edit_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, {
    "[Group] Missing",
    missing_path,
    "",
    "[Group] New",
    new_path .. " [new]",
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

local missing_group = find_group("Missing")
assert_ok(missing_group ~= nil, "expected Missing group to be created")
assert_ok(not group_has_path(missing_group, missing_path), "missing file should be skipped without [new]")
assert_ok(vim.fn.bufnr(missing_path, false) <= 0, "missing file should not create a buffer")

local new_group = find_group("New")
assert_ok(new_group ~= nil, "expected New group to be created")
assert_ok(group_has_path(new_group, new_path), "expected [new] file to be added to New group")
assert_ok(vim.fn.bufnr(new_path, false) > 0, "expected [new] file to create a buffer")

print("OK: edit-mode [new] flag")
vim.cmd("qa")
