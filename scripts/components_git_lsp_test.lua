local function assert_equals(expected, actual, msg)
    if expected ~= actual then
        error(string.format("%s: Expected %s, got %s", msg or "Assertion failed", vim.inspect(expected), vim.inspect(actual)))
    end
end

-- Setup RTP to include the project root
local function add_rtp_root()
    local cwd = vim.fn.getcwd()
    local rtp_root = vim.fn.fnamemodify(cwd, ":h:h")
    vim.opt.rtp:append(rtp_root)
end
add_rtp_root()

local components = require("buffer-nexus.components")
local renderer = require("buffer-nexus.renderer")

local function run_test()
    print("Testing components Git/LSP logic...")

    -- Test Git status
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_var(buf, "gitsigns_status_dict", {
        added = 10,
        changed = 5,
        removed = 2
    })

    local git_status = components.get_git_status(buf)
    assert_equals(10, git_status.added, "Git added")
    assert_equals(5, git_status.changed, "Git changed")
    assert_equals(2, git_status.removed, "Git removed")

    local git_parts = components.create_git_indicator(git_status)
    assert_equals(3, #git_parts, "Git parts count")
    assert_equals(" +10", git_parts[1].text, "Git added text")
    assert_equals("DiffAdd", git_parts[1].highlight, "Git added hl")
    assert_equals(" ~5", git_parts[2].text, "Git changed text")
    assert_equals("DiffChange", git_parts[2].highlight, "Git changed hl")
    assert_equals(" -2", git_parts[3].text, "Git removed text")
    assert_equals("DiffDelete", git_parts[3].highlight, "Git removed hl")

    print("Git status test passed")

    -- Test LSP status
    local ns = vim.api.nvim_create_namespace("test_lsp")
    vim.diagnostic.set(ns, buf, {
        { lnum = 0, col = 0, message = "Error", severity = vim.diagnostic.severity.ERROR },
        { lnum = 1, col = 0, message = "Warning 1", severity = vim.diagnostic.severity.WARN },
        { lnum = 2, col = 0, message = "Warning 2", severity = vim.diagnostic.severity.WARN },
    })

    local lsp_status = components.get_lsp_status(buf)
    assert_equals(1, lsp_status.error, "LSP error count")
    assert_equals(2, lsp_status.warning, "LSP warning count")

    local lsp_parts = components.create_lsp_indicator(lsp_status)
    assert_equals(2, #lsp_parts, "LSP parts count")
    assert_equals(" E1", lsp_parts[1].text, "LSP error text")
    assert_equals("DiagnosticError", lsp_parts[1].highlight, "LSP error hl")
    assert_equals(" W2", lsp_parts[2].text, "LSP warning text")
    assert_equals("DiagnosticWarn", lsp_parts[2].highlight, "LSP warning hl")

    print("LSP status test passed")
    
    print("All component tests passed!")
end

run_test()
vim.cmd("qa!")
