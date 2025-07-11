# Vertical Bufferline Technical Documentation

## Project Overview

This is a Neovim plugin that provides a vertical sidebar for managing buffer groups, with bidirectional synchronization with bufferline.nvim. The plugin allows users to organize buffers into logical groups and switch between them seamlessly.

## Critical Architecture Components

### 1. Core Module Structure

```
vertical-bufferline/
├── init.lua                    # Main entry point and UI management
├── groups.lua                  # Group data structure and operations
├── bufferline-integration.lua  # Bidirectional sync with bufferline.nvim
├── state.lua                   # Plugin state management
├── config.lua                  # Configuration and constants
├── commands.lua                # User commands
├── session.lua                 # Session persistence
└── filename_utils.lua          # File path utilities
```

### 2. Data Flow Architecture

**THE MOST CRITICAL CONCEPT**: This plugin operates on a **bidirectional synchronization model** between the plugin's group system and bufferline.nvim.

```
┌─────────────────┐    sync     ┌─────────────────┐
│  Group System   │ ←--------→  │  bufferline.nvim│
│  (Our Plugin)   │  (100ms)    │  (External)     │
└─────────────────┘             └─────────────────┘
```

#### 2.1 Forward Sync: bufferline → group (90% of time)
- Runs every 100ms via timer
- Copies all valid buffers from bufferline to the active group
- **CRITICAL**: This will overwrite manual changes unless properly handled

#### 2.2 Reverse Sync: group → bufferline (10% of time)
- Triggered when switching groups or manual operations
- Updates bufferline's buffer list to match the active group
- **CRITICAL**: Must pause forward sync during reverse sync operations

### 3. Key Data Structures

#### 3.1 Group Structure
```lua
{
    id = "unique_id",
    name = "Group Name",
    buffers = { 1, 2, 3 },  -- Array of buffer IDs
    current_buffer = 1,      -- Currently active buffer in this group
    window_state = {         -- Per-group window state preservation
        last_win_id = nil,
        last_cursor_pos = nil
    }
}
```

#### 3.2 State Management
- Sidebar window ID and buffer ID tracking
- Current active group tracking
- Buffer-to-line mapping for sidebar display

### 4. Critical Technical Pitfalls and Solutions

#### 4.1 **Cross-Group Current Buffer Pollution** (MAJOR BUG FIXED)
**Problem**: Switching buffers in one group affected triangle markers in all other groups containing the same buffer.

**Root Cause**: Display logic used `get_main_window_current_buffer()` which returns the globally current buffer, causing all instances of a buffer across groups to show as current.

**Solution**: Implement per-group current buffer tracking:
```lua
-- WRONG - causes cross-group pollution
local current_buf = get_main_window_current_buffer()

-- CORRECT - use group-specific current buffer
local current_buf = group.current_buffer
```

#### 4.2 **Sync Timing Race Conditions** (CRITICAL)
**Problem**: Manual operations (like buffer removal) get immediately overwritten by the 100ms sync timer.

**Solution**: Always pause sync during manual operations:
```lua
-- CRITICAL PATTERN for any manual buffer list modification
bufferline_integration.set_sync_target(nil)  -- Pause sync
bufferline_integration.set_bufferline_buffers(new_buffer_list)  -- Apply changes
bufferline_integration.set_sync_target(group_id)  -- Resume sync
```

#### 4.3 **Buffer Management Confusion** (MAJOR)
**Problem**: Confusion between "close buffer" vs "remove from group" operations.

**Functions**:
- `smart_close_buffer()`: Actually closes the buffer (calls `:bd`)
- `remove_from_group()`: Only removes buffer from current group, doesn't close
- Both have different use cases and must be clearly distinguished

#### 4.4 **External Tool Interference** (SIDEBAR CORRUPTION)
**Problem**: External tools like telescope can open files in the sidebar window when cursor is positioned there.

**Solution**: Dual protection:
```lua
-- 1. winfixbuf option (Neovim 0.8+)
api.nvim_win_set_option(sidebar_win, 'winfixbuf', true)

-- 2. Autocmd protection
api.nvim_create_autocmd("BufWinEnter", {
    callback = function(ev)
        if win_id == sidebar_win and ev.buf ~= sidebar_buf then
            api.nvim_win_set_buf(win_id, sidebar_buf)  -- Restore
        end
    end
})
```

#### 4.5 **Autocmd Scope and Event Filtering** (CRITICAL - v1.1.1 BUG)
**Problem**: Overly broad autocmd listeners respond to unrelated events, causing conflicts.

**Case Study - Sidebar Protection Autocmd**:
```lua
-- WRONG - too broad, responds to all BufWinEnter events
api.nvim_create_autocmd("BufWinEnter", {
    callback = function(ev)
        -- This fires during group switching and causes conflicts
    end
})

-- BETTER - limited to specific buffer
api.nvim_create_autocmd("BufWinEnter", {
    buffer = buf_id,  -- Only when this buffer enters a window
    callback = function(ev) -- ... end
})

-- BEST - window-specific filtering
api.nvim_create_autocmd("BufWinEnter", {
    callback = function(ev)
        local current_win = vim.fn.win_findbuf(ev.buf)[1]
        if current_win ~= sidebar_win_id then
            return -- Ignore events not in sidebar window
        end
        -- Only process sidebar-specific events
    end
})
```

**Critical Insight**: Autocmds should be scoped as narrowly as possible to avoid interference with normal operations like group switching.

#### 4.6 **Keymap Persistence After Buffer Recreation** (CRITICAL - v1.1.1 BUG)
**Problem**: When sidebar protection recreates the sidebar buffer, keymaps are lost.

**Root Cause**: 
1. Sidebar protection detects external file opening
2. Creates new sidebar buffer to replace the corrupted one
3. Updates `state.buf_id` but forgets to re-setup keymaps
4. Second keypress (like `<CR>`) has no effect because keymap is missing

**Solution**: Always re-setup keymaps when creating replacement buffers:
```lua
-- After creating new sidebar buffer
local new_sidebar_buf = api.nvim_create_buf(false, true)
state_module.set_buf_id(new_sidebar_buf)

-- CRITICAL: Must re-setup ALL keymaps
local keymap_opts = { noremap = true, silent = true }
api.nvim_buf_set_keymap(new_sidebar_buf, "n", "<CR>", ":lua require('vertical-bufferline').handle_selection()<CR>", keymap_opts)
-- ... all other keymaps
```

**Lesson**: Buffer recreation requires complete state restoration, not just buffer ID updates.

#### 4.7 **Function Call Order Dependencies**
**Problem**: Functions must be called in specific order to work correctly.

**Critical Order for Group Operations**:
1. Modify group data structure
2. Pause sync (`set_sync_target(nil)`)
3. Update bufferline (`set_bufferline_buffers()`)
4. Resume sync (`set_sync_target(group_id)`)
5. Refresh display (`M.refresh()`)

### 5. Extended Picking Mode Architecture

The plugin supports an extended picking mode for cross-group buffer selection:

```lua
extended_picking_state = {
    active = false,
    mode_type = "switch" | "close",
    extended_hints = {},  -- line_num -> hint_char mapping
    bufferline_used_chars = {},  -- Avoid conflicts with bufferline
    original_commands = {}  -- Store for restoration
}
```

**Key Implementation Details**:
- Must coordinate with bufferline.nvim's own picking mode
- Dynamically creates keymaps for hint characters
- Properly restores original keymaps after use

### 6. Session Management

**File**: `session.lua`
**Purpose**: Persist group configurations across Neovim sessions.

**Critical Notes**:
- Only saves buffer file paths, not buffer IDs (IDs change between sessions)
- Reconstructs buffer IDs during session restore
- Handles missing files gracefully

### 7. Debugging and Maintenance

#### 7.1 Common Debug Patterns
```lua
-- Add temporary debug logging
print("DEBUG: variable_name:", variable_name)

-- Check buffer validity
if not api.nvim_buf_is_valid(bufnr) then
    print("DEBUG: Invalid buffer:", bufnr)
end

-- Monitor sync state
print("DEBUG: sync_target:", bufferline_integration.get_sync_target())
```

#### 7.2 Key Functions for Debugging
- `groups.get_all_groups()`: Inspect all group data
- `groups.find_buffer_group(bufnr)`: Find which group contains a buffer
- `state_module.get_buffer_for_line(line)`: Map sidebar lines to buffers
- `bufferline_integration.get_sync_target()`: Check sync state

### 8. Performance Considerations

#### 8.1 Timer Management
- Single 100ms timer for bufferline sync
- Proper timer cleanup on plugin disable
- Avoid multiple timers running simultaneously

#### 8.2 Buffer Validation
- Always check `api.nvim_buf_is_valid(bufnr)` before operations
- Handle invalid buffers gracefully
- Clean up invalid buffers from group data

### 9. Integration Points

#### 9.1 bufferline.nvim Integration
**File**: `bufferline-integration.lua`
**Critical Functions**:
- `set_sync_target(group_id)`: Set which group to sync with
- `set_bufferline_buffers(buffer_list)`: Update bufferline display
- `smart_close_buffer(bufnr)`: Close buffer with proper cleanup

#### 9.2 Window Management
- Sidebar window creation and management
- Main window detection and switching
- Floating window detection and avoidance

### 10. Common Error Patterns

#### 10.1 "attempt to call field 'function_name' (a nil value)"
**Cause**: Function doesn't exist or module not properly loaded
**Solution**: Check function names and module requires

#### 10.2 Buffers disappearing from groups
**Cause**: Sync timer overwriting manual changes
**Solution**: Ensure proper sync pause/resume pattern

#### 10.3 Triangle markers in wrong groups
**Cause**: Using global current buffer instead of group-specific
**Solution**: Use `group.current_buffer` in display logic

#### 10.4 Group header clicks stop working after first use (v1.1.1)
**Cause**: Sidebar protection recreates buffer but doesn't restore keymaps
**Symptoms**: First `<CR>` on group header works, subsequent ones don't
**Solution**: Always re-setup keymaps when recreating sidebar buffer

#### 10.5 Autocmd interference with normal operations (v1.1.1)
**Cause**: Overly broad autocmd scope responding to unrelated events
**Symptoms**: Group switching triggers sidebar protection unnecessarily
**Solution**: Use window-specific filtering in autocmd callbacks

### 11. Testing and Validation

#### 11.1 Manual Test Cases
1. **Cross-group buffer presence**: Same buffer in multiple groups
2. **Buffer removal**: Remove buffer from one group, check other groups
3. **Group switching**: Switch groups, verify bufferline updates
4. **External tool usage**: Use telescope with cursor in sidebar
5. **Session persistence**: Save/restore session with multiple groups

#### 11.2 Key Test Scenarios
- Buffer removal from active vs inactive groups
- Group switching with overlapping buffers
- External tool interference prevention
- Session save/restore with complex group structures

### 12. Future Maintenance Notes

#### 12.1 When Adding New Features
1. Always consider sync implications
2. Test with multiple groups containing same buffers
3. Verify external tool compatibility
4. Check session persistence impact

#### 12.2 When Fixing Bugs
1. Identify if it's a sync timing issue
2. Check if it affects cross-group scenarios
3. Verify the fix doesn't break existing functionality
4. Test with edge cases (empty groups, invalid buffers)

### 13. Key Takeaways for New Maintainers

1. **The sync system is the heart of this plugin** - understand it deeply
2. **Always pause sync during manual operations** - this cannot be overstated
3. **Per-group state isolation is critical** - avoid global state pollution
4. **External tool interference is a real concern** - protect the sidebar
5. **Buffer validation is essential** - invalid buffers cause crashes
6. **Session persistence is complex** - handle missing files gracefully
7. **Cross-group scenarios are the main source of bugs** - test thoroughly
8. **Autocmd scope matters enormously** - narrow event filtering prevents conflicts (v1.1.1)
9. **Buffer recreation requires complete state restoration** - don't forget keymaps (v1.1.1)
10. **Window-specific event filtering is often better than buffer-specific** - more precise control (v1.1.1)

---

**Author**: Claude (Anthropic AI Assistant)
**Date**: 2025-07-11
**Version**: Post-v1.1.1 with autocmd optimization and keymap persistence fixes