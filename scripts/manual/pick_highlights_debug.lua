-- Test script for debugging pick mode highlights
local logger = require('buffer-nexus.logger')

-- Enable debug logging
logger.enable(vim.fn.expand("~/bn-pick-highlights-debug.log"), "DEBUG")
print("BN Pick highlights debug logging enabled: ~/bn-pick-highlights-debug.log")

-- Wait a moment for plugin to load
vim.defer_fn(function()
    print("\n=== Testing Pick Mode Highlights ===")

    -- Check if BufferNexusPick highlight exists and what its value is
    local vbl_pick = vim.api.nvim_get_hl(0, {name = "BufferNexusPick"})
    print("BufferNexusPick highlight:")
    print(vim.inspect(vbl_pick))

    -- Check BufferLinePick for comparison
    local bl_pick = vim.api.nvim_get_hl(0, {name = "BufferLinePick"})
    print("\nBufferLinePick highlight:")
    print(vim.inspect(bl_pick))

    -- Try to enter pick mode
    print("\nEntering pick mode in 2 seconds...")
    vim.defer_fn(function()
        vim.cmd("BufferNexusPickBuffer")

        -- Check highlights again after entering pick mode
        vim.defer_fn(function()
            local vbl_pick_after = vim.api.nvim_get_hl(0, {name = "BufferNexusPick"})
            print("\nBufferNexusPick highlight after entering pick mode:")
            print(vim.inspect(vbl_pick_after))

            print("\nCheck :messages and ~/bn-pick-highlights-debug.log for details")
        end, 500)
    end, 2000)
end, 1000)
