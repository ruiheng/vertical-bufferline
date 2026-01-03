-- Test script for debugging pick mode highlights
local logger = require('vertical-bufferline.logger')

-- Enable debug logging
logger.enable(vim.fn.expand("~/vbl-pick-highlights-debug.log"), "DEBUG")
print("VBL Pick highlights debug logging enabled: ~/vbl-pick-highlights-debug.log")

-- Wait a moment for plugin to load
vim.defer_fn(function()
    print("\n=== Testing Pick Mode Highlights ===")

    -- Check if VBufferLinePick highlight exists and what its value is
    local vbl_pick = vim.api.nvim_get_hl(0, {name = "VBufferLinePick"})
    print("VBufferLinePick highlight:")
    print(vim.inspect(vbl_pick))

    -- Check BufferLinePick for comparison
    local bl_pick = vim.api.nvim_get_hl(0, {name = "BufferLinePick"})
    print("\nBufferLinePick highlight:")
    print(vim.inspect(bl_pick))

    -- Try to enter pick mode
    print("\nEntering pick mode in 2 seconds...")
    vim.defer_fn(function()
        vim.cmd("VBufferLinePickBuffer")

        -- Check highlights again after entering pick mode
        vim.defer_fn(function()
            local vbl_pick_after = vim.api.nvim_get_hl(0, {name = "VBufferLinePick"})
            print("\nVBufferLinePick highlight after entering pick mode:")
            print(vim.inspect(vbl_pick_after))

            print("\nCheck :messages and ~/vbl-pick-highlights-debug.log for details")
        end, 500)
    end, 2000)
end, 1000)
