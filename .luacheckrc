-- Luacheck configuration for vertical-bufferline
-- This file configures luacheck to work better with Neovim Lua development

-- Define read-only global variables (Neovim environment)
read_globals = {
    "vim",  -- Neovim global vim table
}

-- Ignore specific warning types
ignore = {
    -- Whitespace and formatting warnings
    "611",  -- line contains only whitespace
    "612",  -- line contains trailing whitespace  
    "613",  -- line contains trailing whitespace in string
    "614",  -- line contains trailing whitespace in comment
    "621",  -- consistent use of whitespace
    "631",  -- line is too long
}

-- Set reasonable line length limit for Neovim plugin development
max_line_length = 150

-- Allow defining globals implicitly at the top level (for module exports)
allow_defined_top = true

-- Standard library (max = union of all Lua versions)
std = "max"