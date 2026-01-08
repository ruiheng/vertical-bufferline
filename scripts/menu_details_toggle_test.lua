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
add_rtp_root()

local vbl = require('buffer-nexus')
local config = require('buffer-nexus.config')
local groups = require('buffer-nexus.groups')

-- Mock components to always return status
local components = require('buffer-nexus.components')
local original_get_git = components.get_git_status
local original_get_lsp = components.get_lsp_status

components.get_git_status = function()
    return { added = 1, changed = 1, removed = 1 }
end
components.get_lsp_status = function()
    return { error = 1, warning = 1, info = 0, hint = 0 }
end

vbl.setup({
    auto_create_groups = true,
    show_menu_git = true,
    show_menu_lsp = true,
})

-- Create dummy buffers and ensure it's in a group
vim.cmd('enew')
local buf1 = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(buf1, "test1.lua")

-- Force add to active group to ensure it shows up in menu
local active_group = groups.get_active_group()
if active_group then
    groups.add_buffer_to_group(buf1, active_group.id)
end

-- Helper to check menu content
local function check_menu_content(expect_git, expect_lsp)
    vbl.open_buffer_menu()
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    
    local found_line = false
    for _, line in ipairs(lines) do
        if line:match("test1.lua") then
            found_line = true
            local has_git = line:match("%+1")
            local has_lsp = line:match("E1")
            
            if expect_git then
                assert_ok(has_git, "Git status should be present")
            else
                assert_ok(not has_git, "Git status should NOT be present")
            end
            
            if expect_lsp then
                assert_ok(has_lsp, "LSP status should be present")
            else
                assert_ok(not has_lsp, "LSP status should NOT be present")
            end
        end
    end
    assert_ok(found_line, "Menu line for test1.lua not found")
    vim.cmd('close') -- close menu
end

print("Testing default (both enabled)...")
check_menu_content(true, true)

print("Testing disable Git...")
config.settings.show_menu_git = false
check_menu_content(false, true)

print("Testing disable LSP...")
config.settings.show_menu_lsp = false
check_menu_content(false, false)

print("Testing enable Git only...")
config.settings.show_menu_git = true
check_menu_content(true, false)

-- Restore mocks
components.get_git_status = original_get_git
components.get_lsp_status = original_get_lsp

print("menu details toggle test: ok")
vim.cmd("qa!")
