# Adaptive Width Feature

## Overview

The BN sidebar now supports adaptive width that automatically adjusts based on the content being displayed. Instead of a fixed width, the sidebar will dynamically resize within configured min/max bounds to fit the content optimally.

## Configuration Options

### New Options

```lua
require('buffernexus').setup({
    min_width = 15,          -- Minimum width (default: 15)
    max_width = 60,          -- Maximum width (default: 60)
    adaptive_width = true,   -- Enable adaptive width (default: true)
})
```

### Option Details

- **`min_width`**: Minimum width for the sidebar. The sidebar will never be narrower than this value.
- **`max_width`**: Maximum width for the sidebar. The sidebar will never be wider than this value.
- **`adaptive_width`**: Boolean flag to enable/disable adaptive width feature.

## How It Works

1. **Content Analysis**: After rendering the sidebar content, the plugin calculates the display width of all lines.

2. **Width Calculation**:
   - Takes the maximum line width from the content
   - Adds 2 characters for padding
   - Clamps the result between `min_width` (min) and `max_width` (max)

3. **Smart Updates**:
   - Only updates when the calculated width differs from current width
   - Preserves width state when closing/reopening sidebar
   - Handles both split and floating window modes

4. **Floating Window Support**: For floating windows, the position is automatically adjusted to keep the sidebar aligned when width changes.

## User Commands

### Toggle Adaptive Width

```vim
:BNToggleAdaptiveWidth
```

Toggles adaptive width on/off at runtime. Shows a notification with the current state.

## Implementation Details

### Key Functions

1. **`calculate_content_width(lines_text)`** (init.lua:1482)
   - Calculates maximum display width of all content lines
   - Uses `vim.fn.strdisplaywidth()` to properly handle multi-byte characters

2. **`apply_adaptive_width(content_width)`** (init.lua:1495)
   - Applies the calculated width to the sidebar window
   - Handles both split and floating window modes
   - Updates saved width state for persistence

3. **Integration Point**: `finalize_buffer_display()` (init.lua:1614)
   - Calls adaptive width calculation after setting buffer lines
   - Only runs when `adaptive_width` is enabled

### Configuration Module Updates

New validation functions in `config.lua`:

```lua
function M.validate_max_width(max_width)
    return type(max_width) == "number" and max_width > 0 and max_width <= 200
end

function M.validate_adaptive_width(adaptive_width)
    return type(adaptive_width) == "boolean"
end
```

## Usage Examples

### Example 1: Conservative Range
```lua
-- Keep sidebar compact
require('buffernexus').setup({
    min_width = 20,
    max_width = 40,
    adaptive_width = true,
})
```

### Example 2: Wide Range
```lua
-- Allow sidebar to grow with content
require('buffernexus').setup({
    min_width = 15,
    max_width = 80,
    adaptive_width = true,
})
```

### Example 3: Disable Adaptive Width
```lua
-- Fixed width (traditional behavior)
require('buffernexus').setup({
    min_width = 40,
    adaptive_width = false,
})
```

## Benefits

1. **Space Efficiency**: Sidebar uses minimal space when content is narrow
2. **Readability**: Sidebar expands to show full content when needed
3. **Flexibility**: Users control min/max bounds to match their preferences
4. **Smooth UX**: Automatic adjustments without manual resizing

## Testing

Run the test script to verify the implementation:

```bash
cd /home/ruiheng/config_files/nvim/lua/buffernexus
nvim --headless -c "luafile test_adaptive_width.lua" -c "quit"
```

## Related Files

- `config.lua`: Configuration defaults and validation
- `init.lua`: Core implementation (calculate_content_width, apply_adaptive_width)
- `commands.lua`: Toggle command
- `state.lua`: Width persistence via last_width
