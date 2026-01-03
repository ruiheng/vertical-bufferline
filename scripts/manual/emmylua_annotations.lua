-- Test EmmyLua annotations for vertical-bufferline

local vbl = require('vertical-bufferline')

-- This file demonstrates that LSP autocompletion should work for these calls
-- When opened in Neovim with lua-language-server, you should get:
-- - Function signature hints
-- - Parameter type checking
-- - Return type information

-- Test setup with config
vbl.setup({
    min_width = 30,
    max_width = 70,
    adaptive_width = true,
    show_icons = true,
})

-- Test main toggle function
vbl.toggle()

-- Test group management functions
local new_group = vbl.create_group("My Project")
vbl.switch_to_next_group()
vbl.switch_to_prev_group()
vbl.add_current_buffer_to_group("My Project")
vbl.delete_current_group()

-- Test group operations
vbl.move_group_up()
vbl.move_group_down()

-- Test history functions
local success = vbl.clear_history()
vbl.switch_to_history_file(1)

-- Test refresh
vbl.refresh("manual_test")

-- Test toggle functions
vbl.toggle_expand_all()

print("EmmyLua annotations test completed!")
