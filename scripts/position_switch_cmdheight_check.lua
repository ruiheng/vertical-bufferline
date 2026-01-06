-- Automated check for cmdheight and window sizes when switching positions
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

local function find_sidebar_window()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
            local buf = vim.api.nvim_win_get_buf(win)
            if vim.api.nvim_buf_is_valid(buf) and
                vim.api.nvim_buf_get_option(buf, "filetype") == "buffer-nexus" then
                return win
            end
        end
    end
    return nil
end

local function find_main_window(sidebar_win)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if win ~= sidebar_win and vim.api.nvim_win_is_valid(win) then
            local config = vim.api.nvim_win_get_config(win)
            if config.relative == "" then
                return win
            end
        end
    end
    return nil
end

local function wait_for_sidebar()
    local ok = vim.wait(1000, function()
        local win = find_sidebar_window()
        return win ~= nil
    end, 10)
    return ok and find_sidebar_window() or nil
end

local function assert_vertical_sizes(sidebar_win, main_win, min_width, max_width)
    local sidebar_width = vim.api.nvim_win_get_width(sidebar_win)
    assert_ok(sidebar_width >= min_width, "sidebar width below min_width")
    assert_ok(sidebar_width <= max_width, "sidebar width above max_width")

    local main_width = vim.api.nvim_win_get_width(main_win)
    assert_ok(main_width > 0, "main window width not positive")
    assert_ok(main_width <= vim.o.columns, "main window width exceeds columns")
end

local function assert_horizontal_sizes(sidebar_win, main_win, _min_height, _max_height, enforce_min_height)
    local sidebar_height = vim.api.nvim_win_get_height(sidebar_win)
    if enforce_min_height then
        assert_ok(sidebar_height >= _min_height, "sidebar height below min_height")
    end
    assert_ok(sidebar_height <= vim.o.lines, "sidebar height above total lines")

    local main_height = vim.api.nvim_win_get_height(main_win)
    assert_ok(main_height > 0, "main window height not positive")
    assert_ok(main_height <= vim.o.lines, "main window height exceeds lines")

    local total_height = sidebar_height + main_height
    assert_ok(total_height <= vim.o.lines, "window heights exceed total lines")
end

local function assert_no_blank_lines(sidebar_win)
    local buf = vim.api.nvim_win_get_buf(sidebar_win)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, line in ipairs(lines) do
        assert_ok(line ~= "", "blank line found in sidebar at index " .. i)
    end
end

local function assert_horizontal_no_extra_space(sidebar_win, enforce_height)
    if not enforce_height then
        return
    end
    local buf = vim.api.nvim_win_get_buf(sidebar_win)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local sidebar_height = vim.api.nvim_win_get_height(sidebar_win)
    assert_ok(sidebar_height == #lines, "sidebar height exceeds content height")
end

add_rtp_root()

local vbl = require("buffer-nexus")
local config = require("buffer-nexus.config")
local state = require("buffer-nexus.state")

vbl.setup({
    position = "left",
    min_width = 20,
    max_width = 40,
    adaptive_width = false,
})

local function wait_for_sidebar_open()
    local ok = vim.wait(1500, function()
        return state.is_sidebar_open() or find_sidebar_window() ~= nil
    end, 10)
    if not ok then
        return nil
    end
    local win = find_sidebar_window()
    if win and vim.api.nvim_win_is_valid(win) then
        return win
    end
    local state_win = state.get_win_id()
    if state_win and vim.api.nvim_win_is_valid(state_win) then
        return state_win
    end
    return nil
end

local function run_test()
    config.settings.position = "left"

    if state.is_sidebar_open() then
        vbl.close_sidebar(config.settings.position)
    end

    vim.o.cmdheight = 1
    local baseline_cmdheight = vim.o.cmdheight

    vbl.toggle()
    local sidebar_win = wait_for_sidebar_open()
    assert_ok(sidebar_win, "sidebar did not open for left position")
    local main_win = find_main_window(sidebar_win)
    assert_ok(main_win, "main window not found for left position")

    assert_vertical_sizes(sidebar_win, main_win, config.settings.min_width, config.settings.max_width)

    vim.cmd("BNSetPosition top")
    local top_sidebar_win = wait_for_sidebar_open()
    assert_ok(top_sidebar_win, "sidebar did not open for top position")
    local top_main_win = find_main_window(top_sidebar_win)
    assert_ok(top_main_win, "main window not found for top position")

    assert_horizontal_sizes(top_sidebar_win, top_main_win, config.settings.min_height, config.settings.max_height, false)
    assert_no_blank_lines(top_sidebar_win)
    assert_horizontal_no_extra_space(top_sidebar_win, true)
    assert_ok(vim.o.cmdheight == baseline_cmdheight, "cmdheight changed after position switch")

    vbl.close_sidebar(config.settings.position)
end

local ok, err = xpcall(function()
    run_test()
end, debug.traceback)

if not ok then
    print(err)
    vim.cmd("qa!")
end

print("OK: cmdheight and window sizes are stable when switching left -> top")
vim.cmd("qa")
