-- Test script for horizontal position (top/bottom) height bug
-- Bug: placeholder window has one extra line compared to floating window
-- Expected: floating window height matches content height
-- Placeholder window height equals content height minus statusline height
-- Run with: nvim --headless -c "luafile scripts/horizontal_height_test.lua"
--
-- The bug occurs when:
-- 1. Initial creation: placeholder = content - statusline, float = content (correct)
-- 2. After populate with more content: placeholder should = content - statusline
--    But buggy code sets placeholder to content (too large by statusline)

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

local function setup_temp_cache()
    local cache_root = vim.fn.tempname()
    vim.fn.mkdir(cache_root, "p")
    vim.env.XDG_CACHE_HOME = cache_root
end

local function enable_winbar()
    return pcall(function()
        vim.o.winbar = "%=%f"
    end)
end

local function write_temp_file(lines)
    local name = vim.fn.tempname()
    vim.fn.writefile(lines, name)
    return name
end

add_rtp_root()
setup_temp_cache()
enable_winbar()
vim.o.shadafile = vim.fn.tempname()
vim.o.swapfile = false
vim.o.laststatus = 2
vim.o.cmdheight = 1
vim.o.equalalways = false
vim.o.winminheight = 0
if #vim.api.nvim_list_uis() == 0 and vim.api.nvim_ui_attach then
    vim.api.nvim_ui_attach(80, 24, { rgb = true, ext_linegrid = true })
end

local ok, err = xpcall(function()
    -- Test with position = "top"
    print("Testing position=top")
    local vbl = require('buffer-nexus')
    vbl.setup({
        position = "top",
        auto_create_groups = true,
        auto_add_new_buffers = true,
        group_scope = "global",
    })

    local path = write_temp_file({ "test content", "line 2", "line 3" })
    vim.cmd("edit " .. vim.fn.fnameescape(path))

    -- Open sidebar
    vbl.toggle()

    -- Wait for sidebar to fully render
    vim.cmd("redraw")
    vim.cmd("sleep 10m")  -- Wait 10ms for async operations

    -- Get window IDs
    local state_module = require('buffer-nexus.state')
    local placeholder_win_id = state_module.get_placeholder_win_id()
    local float_win_id = state_module.get_win_id()

    assert_ok(placeholder_win_id ~= nil, "placeholder_win_id should exist")
    assert_ok(float_win_id ~= nil, "float_win_id should exist")

    -- Check if windows are valid
    assert_ok(vim.api.nvim_win_is_valid(placeholder_win_id), "placeholder window should be valid")
    assert_ok(vim.api.nvim_win_is_valid(float_win_id), "float window should be valid")

    -- Get window heights
    local placeholder_height = vim.api.nvim_win_get_height(placeholder_win_id)
    local float_config = vim.api.nvim_win_get_config(float_win_id)
    local float_height = float_config.height

    local function count_normal_windows()
        local count = 0
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_config(win).relative == "" then
                count = count + 1
            end
        end
        return count
    end
    local normal_count = count_normal_windows()
    local laststatus = vim.o.laststatus
    local line_count = vim.api.nvim_buf_line_count(state_module.get_buf_id())

    print(string.format("Placeholder window height: %d", placeholder_height))
    print(string.format("Floating window height: %d", float_height))
    print(string.format("laststatus: %d", laststatus))
    print(string.format("cmdheight: %d", vim.o.cmdheight))
    print(string.format("Normal windows: %d", normal_count))
    print(string.format("Content lines: %d", line_count))
    local statusline_height = vim.o.laststatus == 2 and 1 or 0
    print(string.format("Statusline height: %d", statusline_height))
    print(string.format("Expected: float_height = content lines"))
    print(string.format("         %d = %d", float_height, line_count))
    print(string.format("Expected: placeholder_height = content lines - statusline_height"))
    print(string.format("         %d = %d - %d", placeholder_height, line_count, statusline_height))

    -- Verify the bug or the fix
    if float_height ~= line_count then
        print(string.format("\n❌ BUG DETECTED: float_height (%d) != content lines (%d)",
            float_height, line_count))
        print(string.format("   Difference: %d line(s)", float_height - line_count))
        error("Height mismatch bug detected")
    end
    if placeholder_height ~= line_count - statusline_height then
        print(string.format("\n❌ BUG DETECTED: placeholder height (%d) != content lines - statusline (%d)",
            placeholder_height, line_count - statusline_height))
        print(string.format("   Difference: %d line(s)", placeholder_height - (line_count - statusline_height)))
        error("Placeholder height mismatch detected")
    end
    print("\n✓ Heights are correct")

-- Test dynamic height adjustment by adding more files
    print("\n\nTesting dynamic height adjustment (after adding files)")
    for i = 2, 8 do
        local p = write_temp_file({ "file " .. i .. " content" })
        vim.cmd("edit " .. vim.fn.fnameescape(p))
    end
    vim.cmd("redraw")
    vim.cmd("sleep 10m")

-- Get window heights after adding files
    placeholder_height = vim.api.nvim_win_get_height(placeholder_win_id)
    float_config = vim.api.nvim_win_get_config(float_win_id)
    float_height = float_config.height
    line_count = vim.api.nvim_buf_line_count(state_module.get_buf_id())

    print(string.format("Placeholder window height: %d", placeholder_height))
    print(string.format("Floating window height: %d", float_height))
    print(string.format("Content lines: %d", line_count))
    print(string.format("Statusline height: %d", statusline_height))
    print(string.format("Expected: float_height = content lines"))
    print(string.format("         %d = %d", float_height, line_count))
    print(string.format("Expected: placeholder_height = content lines - statusline_height"))
    print(string.format("         %d = %d - %d", placeholder_height, line_count, statusline_height))

    if float_height ~= line_count then
        print(string.format("\n❌ BUG DETECTED: float_height (%d) != content lines (%d)",
            float_height, line_count))
        print(string.format("   Difference: %d line(s)", float_height - line_count))
        error("Height mismatch bug detected (dynamic adjustment)")
    end
    if placeholder_height ~= line_count - statusline_height then
        print(string.format("\n❌ BUG DETECTED: placeholder height (%d) != content lines - statusline (%d)",
            placeholder_height, line_count - statusline_height))
        print(string.format("   Difference: %d line(s)", placeholder_height - (line_count - statusline_height)))
        error("Placeholder height mismatch detected (dynamic adjustment)")
    end
    print("\n✓ Heights are correct after dynamic adjustment")

-- Test with position = "bottom"
    print("\n\nTesting position=bottom")
    vbl.toggle()  -- Close the sidebar

-- Change position setting
    local config = require('buffer-nexus.config')
    config.settings.position = "bottom"

    vbl.toggle()  -- Reopen with bottom position
    vim.cmd("redraw")
    vim.cmd("sleep 10m")

-- Get window IDs again
    placeholder_win_id = state_module.get_placeholder_win_id()
    float_win_id = state_module.get_win_id()

    assert_ok(placeholder_win_id ~= nil, "placeholder_win_id should exist (bottom)")
    assert_ok(float_win_id ~= nil, "float_win_id should exist (bottom)")

-- Get window heights
    placeholder_height = vim.api.nvim_win_get_height(placeholder_win_id)
    float_config = vim.api.nvim_win_get_config(float_win_id)
    float_height = float_config.height

    normal_count = count_normal_windows()
    line_count = vim.api.nvim_buf_line_count(state_module.get_buf_id())

    print(string.format("Placeholder window height: %d", placeholder_height))
    print(string.format("Floating window height: %d", float_height))
    print(string.format("Content lines: %d", line_count))
    statusline_height = vim.o.laststatus == 2 and 1 or 0
    print(string.format("Statusline height: %d", statusline_height))
    print(string.format("Expected: float_height = content lines"))
    print(string.format("         %d = %d", float_height, line_count))
    print(string.format("Expected: placeholder_height = content lines - statusline_height"))
    print(string.format("         %d = %d - %d", placeholder_height, line_count, statusline_height))

    if float_height ~= line_count then
        print(string.format("\n❌ BUG DETECTED: float_height (%d) != content lines (%d)",
            float_height, line_count))
        print(string.format("   Difference: %d line(s)", float_height - line_count))
        error("Height mismatch bug detected (bottom)")
    end
    if placeholder_height ~= line_count - statusline_height then
        print(string.format("\n❌ BUG DETECTED: placeholder height (%d) != content lines - statusline (%d)",
            placeholder_height, line_count - statusline_height))
        print(string.format("   Difference: %d line(s)", placeholder_height - (line_count - statusline_height)))
        error("Placeholder height mismatch detected (bottom)")
    end
    print("\n✓ Heights are correct (bottom)")

    print("\n✅ horizontal height test: ok")
end, debug.traceback)

if not ok then
    print(err)
    vim.cmd("qa!")
end

vim.cmd("qa!")
