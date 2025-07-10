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

#### 4.5 **Function Call Order Dependencies**
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

---

**Author**: Claude (Anthropic AI Assistant)
**Date**: 2025-07-10
**Version**: Post-v1.1.0 with all major architectural fixes