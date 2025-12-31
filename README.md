# Vertical Bufferline

**Vertical sidebar for buffer groups, with optional bufferline.nvim integration and history for large projects.**

Use the unused space on the left/right to show every buffer at a glance, organized by group. Bufferline.nvim then only shows the buffers for your *current* group, keeping the horizontal bar clean and focused.

## Quick Start

1) Install this plugin and call setup.
2) Optional: install bufferline.nvim for integration (visible ordinals, shared picking, and pin sync).
3) (Optional) Apply the opt-in keymap preset.

```lua
-- lazy.nvim
{
  "ruiheng/vertical-bufferline",
  -- Optional: add bufferline.nvim for integration
  -- dependencies = { "akinsho/bufferline.nvim" },
  opts = {},
  config = function()
    local vbl = require("vertical-bufferline")
    vbl.apply_keymaps(vbl.keymap_preset())
  end,
}
```

Recommended bufferline integration (optional, for smart buffer closing):
```lua
require('bufferline').setup({
  options = {
    numbers = "ordinal",
    close_command = function(bufnum)
      require('vertical-bufferline.bufferline-integration').smart_close_buffer(bufnum)
    end,
    right_mouse_command = function(bufnum)
      require('vertical-bufferline.bufferline-integration').smart_close_buffer(bufnum)
    end,
  }
})
```

## Core Concepts

- **Groups**: Buffers are organized into groups. The sidebar shows groups and their buffers.
- **Active group**: Only the active group's buffers appear in bufferline.nvim.
- **History**: Each group keeps a recent-files list for fast jumping.

## Features

### Core Features
- **Vertical sidebar** showing buffer groups and their contents
- **Adaptive width** - sidebar automatically adjusts width based on content (configurable min/max)
- **Dynamic buffer grouping** with automatic management
- **Optional bufferline integration** - bufferline only shows current group's buffers when installed
- **Perfect picking mode compatibility** with synchronized highlighting
- **Two display modes**: Show only active group (default) or expand all groups
- **Smart filename disambiguation** - automatically resolves duplicate filenames with minimal path context
- **Cursor alignment** - VBL content automatically aligns with your cursor position in the main window
- **Pinned buffer indicator** - shows pin state in the sidebar (syncs with bufferline when installed)
- **Edit mode (modal)** - batch edit groups in a temporary buffer and apply

### Group Management
- **Automatic buffer addition** - new buffers auto-join the active group
- **Smart group creation** - create unnamed groups instantly
- **Group numbering** - groups displayed as `[1] ● GroupName (5 buffers)`
- **Empty group names supported** for cleaner interface
- **Intelligent buffer cleanup** - deleted buffers automatically removed from groups

## Keymaps

### Opt-in Keymap Preset

Apply the preset:
```lua
local vbl = require("vertical-bufferline")
vbl.apply_keymaps(vbl.keymap_preset())
```

Customize prefixes:
```lua
local vbl = require("vertical-bufferline")
vbl.apply_keymaps(vbl.keymap_preset({
  history_prefix = "<leader>h", -- defaults to <leader>h
  buffer_prefix = "<leader>",   -- defaults to <leader>
  group_prefix = "<leader>g",   -- defaults to <leader>g
}))
```

You can also override or remove any entry by editing the returned table before applying it.

### Plugin Functions (If You Prefer Custom Keymaps)

The following functions are available for you to map to your preferred keybindings. See Installation section for keymap examples.

**Sidebar Control:**
- `require('vertical-bufferline').toggle()` - Toggle vertical bufferline sidebar
- `require('vertical-bufferline').toggle_show_inactive_group_buffers()` - Toggle showing inactive group buffers
- `require('vertical-bufferline').close_sidebar()` - Close the sidebar

**Group Management:**
- `require('vertical-bufferline').create_group()` - Create new unnamed group
- `require('vertical-bufferline').switch_to_next_group()` - Switch to next group
- `require('vertical-bufferline').switch_to_prev_group()` - Switch to previous group
- `require('vertical-bufferline').move_group_up()` - Move current group up in the list
- `require('vertical-bufferline').move_group_down()` - Move current group down in the list
- `require('vertical-bufferline').groups.switch_to_group_by_display_number(n)` - Switch directly to group n by display number

**History Quick Access:**
- `require('vertical-bufferline').switch_to_history_file(n)` - Switch to nth recent file in current group history
- `require('vertical-bufferline').switch_to_group_buffer(n)` - Switch to nth buffer in current group

Note: `BufferLineGoToBuffer` and `BufferLinePick` are provided by bufferline.nvim. Without bufferline, use `:VBufferLinePick`.

## Commands

### Edit Mode
- `:VBufferLineEdit` - Open a modal edit buffer to batch-edit groups (apply with `:w`, discard by closing the window)

### Group Operations
- `:VBufferLineCreateGroup [name]` - Create new group with optional name
- `:VBufferLineDeleteGroup <name_or_id>` - Delete specified group
- `:VBufferLineRenameGroup <new_name>` - Rename current active group
- `:VBufferLineSwitchGroup [name_or_id]` - Switch to specified group
- `:VBufferLineAddToGroup <name_or_id>` - Add current buffer to specified group

### Navigation
- `:VBufferLineNextGroup` - Switch to next group
- `:VBufferLinePrevGroup` - Switch to previous group
- `:VBufferLineToggleInactiveGroupBuffers` - Toggle showing buffer lists for inactive groups (same as `:VBufferLineToggleExpandAll`)
- `:VBufferLinePick` - Pick a buffer across groups
- `:VBufferLinePickClose` - Pick a buffer across groups and close it

### Group Reordering
- `:VBufferLineMoveGroupUp` - Move current group up in the list
- `:VBufferLineMoveGroupDown` - Move current group down in the list
- `:VBufferLineMoveGroupToPosition <position>` - Move current group to specified position

### Utilities
- `:VBufferLineDebug` - Show debug information
- `:VBufferLineRefreshBuffers` - Manually refresh and add current buffers to active group
- `:VBufferLineClearHistory [group_name]` - Clear history for all groups or specific group
- `:VBufferLineToggleCursorAlign` - Toggle cursor alignment for VBL content
- `:VBufferLineToggleAdaptiveWidth` - Toggle adaptive width for VBL sidebar

## Display Modes

### Active Group Only Mode (Default)
Shows only the current active group's buffers:
```
[1] ● Frontend (3 buffers)
├─ ► 1 🌙 App.tsx
├─ 2 📄 Button.jsx
└─ 3 📝 README.md

[2] ○ Backend (2 buffers)
```

### Expand All Groups Mode
Shows all groups expanded with their buffers visible:
```
[1] ● Frontend (3 buffers)
├─ ► 1 🌙 App.tsx
├─ 2 📄 Button.jsx
└─ 3 📝 README.md

[2] ○ Backend (2 buffers)
├─ 1 🐍 api.py
└─ 2 📋 config.json
```

Toggle between modes with `:VBufferLineToggleInactiveGroupBuffers` or by calling `require('vertical-bufferline').toggle_show_inactive_group_buffers()`.

## Interface Elements

### Group Headers
- `[1] ● GroupName (5 buffers)` - Active group with name (PmenuSel background, bold text)
- `[2] ○ (3 buffers)` - Inactive unnamed group (Pmenu background)
- Numbers correspond to the group's display number (use your own keymaps to jump).
- Each group header uses semantic highlight groups that adapt to your theme

### Buffer Lines

**Dual Numbering System (bufferline.nvim only):**

VBL displays buffer ordinal numbers to help you navigate efficiently. Each buffer shows its position with one or two numbers:

- **Group Ordinal** (always shown): The buffer's ordinal position within the current group
- **Visible Ordinal** (shown only when different): The buffer's ordinal position in bufferline's visible elements

When bufferline truncates the list (many open buffers), some buffers won't appear in the horizontal bufferline. In this case, VBL shows both ordinals to clarify the buffer's location:

```
Format: [visible|group] or just [group] when they match

Examples:
  1 App.tsx            # 1st in both bufferline visible elements and group
2|5 Utils.js           # 2nd in bufferline visible elements, 5th in group
-|9 Config.json        # Not in bufferline visible elements, 9th in group
```

The visible ordinal corresponds to bufferline's ordinal numbers (for example, if you map them to `<leader>1`, `<leader>2`, etc.), making it easy to jump to visible buffers using those shortcuts. Without bufferline.nvim, VBL shows only the group ordinal.

**Buffer Display Elements:**
- `► 1 🌙 filename.lua` - Current buffer with arrow marker
- `2 ● 📄 modified.js` - Modified buffer with dot indicator
- `📌 3 utils.lua` - Pinned buffer (matches bufferline pinned state)
- `└─ 3 📋 src/config.json` - Tree structure with smart disambiguation for duplicate names

### Picking Mode Integration
When using `:BufferLinePick` (bufferline.nvim) or `:VBufferLinePick` (built-in), the sidebar shows hint characters:
```
├─ a ► 1 🌙 App.tsx
├─ s 2 📄 Button.jsx
└─ d 3 📝 README.md
```

## Workflow Examples

### Basic Project Organization
Use commands directly, or map them to your own keys.
```
# Create groups for different areas
:VBufferLineCreateGroup Frontend
:VBufferLineCreateGroup Backend

# Switch between groups
:VBufferLineNextGroup
:VBufferLinePrevGroup
```

## Automatic Features

1. **Auto-add new buffers** - Files opened are automatically added to the active group
2. **Auto-cleanup deleted buffers** - Deleted files are automatically removed from all groups
3. **Smart buffer filtering** - Only normal file buffers are managed (excludes terminals, quickfix, etc.)
4. **Instant refresh** - UI updates immediately on group operations
5. **BufferLine synchronization** - BufferLine automatically shows only current group's buffers (bufferline.nvim only)
6. **Session persistence** - Automatically save and restore group configurations across sessions
7. **Smart filename disambiguation** - When multiple files have the same name, automatically shows minimal unique paths

## History

Each group maintains its own history of recently accessed files. The current active group's history is displayed as a special group at the top of the sidebar.

### History Display
- **Current Group History**: Shows recent files from the currently active group at the top
- **Current file first**: The current file is shown first without a number (marked with ►)
- **Numbered history**: Following files are numbered 1, 2, 3... representing access order
- **Auto mode**: History is shown when active group has 3+ files and history isn't empty
- **Manual toggle**: Use `h` key in sidebar to cycle through yes/no/auto modes
- **Configurable display count**: Maximum number of history items shown (default: 5)

### History Quick Access
Map `require('vertical-bufferline').switch_to_history_file(n)` to your preferred keys. Example mapping to positions 1-9:
```lua
for i = 1, 9 do
  vim.keymap.set('n', '<leader>h' .. i, function()
    require('vertical-bufferline').switch_to_history_file(i)
  end, { desc = "VBL history " .. i })
end
```
Behavior (with the example mapping above):
- `<leader>h1` jumps to the most recent history entry (the first numbered item)
- `<leader>h2` jumps to the next most recent entry, etc.
- `n` can be any position within your configured history size
- History entries are ordered by recency (most recent first)
- History automatically updates when switching between files in the active group

### History Management
- `:VBufferLineClearHistory` - Clear history for all groups
- `:VBufferLineClearHistory [group_name]` - Clear history for specific group
- History is automatically saved and restored with sessions
- History size is configurable (default: 10 entries per group)
- History display count is configurable (default: 5 items shown)

### Example History Display
```
[H] 📋 Recent Files (5)
► 🌙 App.tsx          (current file, no number)
1 📄 utils.js         (most recent)
2 📄 config.js        (second most recent)
3 📝 README.md        (third most recent)
4 📋 package.json     (fourth most recent)

[1] ● Frontend (3 buffers)
► 1 🌙 Button.jsx
2 📄 styles.css
3 📄 index.html
```

## Session Management

### How It Works

- Every 3 seconds, the plugin saves your group configuration to `vim.g.VerticalBufferlineSession`
- When you use `:mksession`, this global variable is saved
- When you `:source` the session, your groups are restored

**Saved Data:**
- All group structures and names
- Buffer assignments to each group
- Active group
- Display mode settings
- History data per group

### Usage

Simply use Neovim's native session commands:

```vim
" Save a session (includes all VBL state automatically)
:mksession ~/my-project.vim

" Restore a session (restores all VBL state automatically)
:source ~/my-project.vim
```

That's it! No need to manually save or load VBL-specific sessions.

### Integration

- **mini.sessions**: integrates automatically when enabled
- **Native :mksession**: works with Neovim session management
- **No conflicts**: state is stored in a global variable

## Adaptive Width

The sidebar automatically adjusts its width based on the content being displayed, providing an optimal balance between space efficiency and readability.

### How It Works

1. **Content Analysis**: The plugin calculates the display width of all visible lines
2. **Smart Sizing**: Width adjusts between configured min/max bounds to fit content
3. **Automatic Updates**: Width recalculates whenever content changes (switching groups, adding buffers, etc.)
4. **State Persistence**: Width is preserved when closing and reopening the sidebar

### Configuration

```lua
require('vertical-bufferline').setup({
    min_width = 15,          -- Minimum width
    max_width = 60,          -- Maximum width
    adaptive_width = true,   -- Enable adaptive sizing (default: true)
})
```

### Examples

**Narrow content** - Sidebar uses minimal space:
```
[1] ● Frontend (3)
► 1 App.tsx
  2 util.js
  3 api.py
```
Width: ~25 chars

**Wide content** - Sidebar expands to show full paths:
```
[1] ● Frontend (3)
► 1 src/components/Button.tsx
  2 src/utils/formatting.js
  3 src/api/endpoints.py
```
Width: ~45 chars (auto-adjusted)

### Runtime Control

Toggle adaptive width on/off:
```vim
:VBufferLineToggleAdaptiveWidth
```

Or disable it in configuration for fixed width behavior:
```lua
require('vertical-bufferline').setup({
    min_width = 40,
    adaptive_width = false,  -- Fixed width mode
})
```

## Smart Filename Disambiguation

When you have multiple files with the same name in different directories, the plugin automatically shows just enough path context to make them distinguishable:

```
▎[1] ● Frontend (4 buffers)
  ├─ ► 1 🌙 App.tsx                    # Unique filename
  ├─ 2 📄 src/Button.tsx               # Disambiguation: src/Button.tsx 
  ├─ 3 📄 components/Button.tsx        # Disambiguation: components/Button.tsx
  └─ 4 📝 README.md                    # Unique filename
```

The algorithm automatically determines the minimal path suffix needed to uniquely identify each file, keeping the display clean while providing clarity.

## Configuration

### Lazy.nvim Setup (Full Options)

```lua
{
  "ruiheng/vertical-bufferline",
  opts = {
    -- UI settings
    min_width = 15,                 -- Minimum sidebar width (for adaptive sizing)
    max_width = 60,                 -- Maximum sidebar width (for adaptive sizing)
    adaptive_width = true,          -- Enable adaptive width based on content
    min_height = 3,                 -- Minimum bar height for top/bottom
    max_height = 10,                -- Maximum bar height for top/bottom
    adaptive_height = true,         -- Enable adaptive height based on content
    show_inactive_group_buffers = false,  -- Show buffer lists for inactive groups (default: only active group)
    show_icons = false,             -- Show file type emoji icons
    position = "left",              -- Sidebar position: "left", "right", "top", "bottom"
    show_tree_lines = false,        -- Show tree-style connection lines
    floating = false,               -- Use floating window (right side, focusable=false) instead of split
    
    -- Group management  
    auto_create_groups = true,      -- Enable automatic group creation
    auto_add_new_buffers = true,    -- Auto-add new buffers to active group
    
    -- Path display settings
    show_path = "auto",             -- "yes", "no", "auto"
    path_style = "relative",        -- "relative", "absolute", "smart"
    path_max_length = 50,           -- Maximum path display length

    -- Cursor alignment settings
    align_with_cursor = true,       -- Align VBL content with main window cursor position
    
    -- History settings
    show_history = "auto",          -- "yes", "no", "auto" - show recent files history per group
    history_size = 10,              -- Maximum number of recent files to track per group
    history_auto_threshold = 2,     -- Minimum files needed for auto mode to show history
    history_display_count = 7,      -- Maximum number of history items to display
    
    -- Session persistence settings
    auto_save = false,              -- Auto-save session on Neovim exit
    auto_load = false,              -- Auto-load session on startup
    session_name_strategy = "cwd_hash", -- "cwd_hash", "cwd_path", "manual"

    session = {
        mini_sessions_integration = true,    -- Integrate with mini.sessions
        auto_serialize = true,               -- Auto-serialize to global variable
        serialize_interval = 3000,           -- Serialization interval (ms)
        optimize_serialize = true,           -- Only serialize when state changes
        auto_restore_prompt = true,          -- Show restore prompt for session changes
        confirm_restore = true,              -- Ask confirmation before restoring
        global_variable = "VerticalBufferlineSession"  -- Global variable name
    }
  },
  keys = {
    -- Example keymaps (define your own)
    { "<leader>vb", "<cmd>lua require('vertical-bufferline').toggle()<cr>", desc = "Toggle vertical bufferline" },
    { "<leader>ve", "<cmd>lua require('vertical-bufferline').toggle_show_inactive_group_buffers()<cr>", desc = "Toggle showing inactive group buffers" },
    { "<leader>gc", "<cmd>lua require('vertical-bufferline').create_group()<cr>", desc = "Create new group" },
    { "<leader>gn", "<cmd>lua require('vertical-bufferline').switch_to_next_group()<cr>", desc = "Next group" },
    { "<leader>gp", "<cmd>lua require('vertical-bufferline').switch_to_prev_group()<cr>", desc = "Previous group" },
    { "<leader>G", "<cmd>lua require('vertical-bufferline.groups').switch_to_previous_group()<cr>", desc = "Last-used group" },
    { "<leader>Bo", "<cmd>lua require('vertical-bufferline').close_other_buffers_in_group()<cr>", desc = "Close other buffers in group" },
    { "<leader>BO", "<cmd>lua require('vertical-bufferline').close_other_buffers_in_group()<cr>", desc = "Close other buffers in group" },
    { "<leader>bb", "<cmd>lua require('vertical-bufferline').open_buffer_menu()<cr>", desc = "Buffer menu" },
    { "<leader>gg", "<cmd>lua require('vertical-bufferline').open_group_menu()<cr>", desc = "Group menu" },
    { "<leader>hh", "<cmd>lua require('vertical-bufferline').open_history_menu()<cr>", desc = "History menu" },
  }
}
```

Top/bottom positions use a compact, multi-item layout with wrapping; History comes first, then the active group file list, then a group list. Each file shows its ordinal number, and path lines are suppressed to save vertical space.

For a minimal setup, `require("vertical-bufferline").setup()` is enough.

## Integration

### BufferLine.nvim
- Seamlessly filters buffers to show only current group
- Perfect picking mode integration with synchronized highlights
- All BufferLine commands work within the current group context

### Scope.nvim
- Compatible with tabpage-scoped buffer management
- Buffer deletion respects scope.nvim's buffer handling

### Telescope.nvim
- Provides a picker for buffers in the current group
- Use `:Telescope vertical-bufferline current_group` to open the picker

### Filetype Support
The sidebar buffer uses the `vertical-bufferline` filetype, making it easy to:
- Set buffer-specific configurations and keymaps
- Integrate with other plugins that check buffer filetype
- Apply custom syntax highlighting or statusline behavior
- Use filetype-specific autocommands for enhanced functionality

Example configuration for the sidebar buffer:
```lua
-- Custom configuration for vertical-bufferline buffers
vim.api.nvim_create_autocmd("FileType", {
    pattern = "vertical-bufferline",
    callback = function()
        -- Custom settings for sidebar buffer
        vim.opt_local.wrap = false
        vim.opt_local.signcolumn = "no"
        -- Add custom keymaps or settings here
    end,
})
```

## Technical Details

- **Event-driven architecture** - Responds to Neovim buffer events automatically
- **High performance** - Minimal overhead, only processes when needed
- **Memory efficient** - Smart cleanup of invalid buffers and groups
- **Extensible design** - Clean API for future enhancements

## Installation

### Using lazy.nvim (Recommended)

Add to your lazy.nvim configuration:

```lua
{
  "ruiheng/vertical-bufferline",
  opts = {
    min_width = 40,
    show_inactive_group_buffers = false,  -- Show only active group (default)
    show_icons = false,
    position = "left",
  },
  keys = {
    -- Example keymaps (define your own)
    { "<leader>vb", "<cmd>lua require('vertical-bufferline').toggle()<cr>", desc = "Toggle vertical bufferline" },
    { "<leader>ve", "<cmd>lua require('vertical-bufferline').toggle_show_inactive_group_buffers()<cr>", desc = "Toggle showing inactive group buffers" },
    { "<leader>gc", "<cmd>lua require('vertical-bufferline').create_group()<cr>", desc = "Create new group" },
    { "<leader>gn", "<cmd>lua require('vertical-bufferline').switch_to_next_group()<cr>", desc = "Next group" },
    { "<leader>gp", "<cmd>lua require('vertical-bufferline').switch_to_prev_group()<cr>", desc = "Previous group" },
    { "<leader>G", "<cmd>lua require('vertical-bufferline.groups').switch_to_previous_group()<cr>", desc = "Last-used group" },
    { "<leader>Bo", "<cmd>lua require('vertical-bufferline').close_other_buffers_in_group()<cr>", desc = "Close other buffers in group" },
    { "<leader>BO", "<cmd>lua require('vertical-bufferline').close_other_buffers_in_group()<cr>", desc = "Close other buffers in group" },
    { "<leader>bb", "<cmd>lua require('vertical-bufferline').open_buffer_menu()<cr>", desc = "Buffer menu" },
    { "<leader>gg", "<cmd>lua require('vertical-bufferline').open_group_menu()<cr>", desc = "Group menu" },
    { "<leader>hh", "<cmd>lua require('vertical-bufferline').open_history_menu()<cr>", desc = "History menu" },
  }
}
```

### Using packer.nvim

```lua
use {
  'ruiheng/vertical-bufferline',
  config = function()
    require('vertical-bufferline').setup({
      min_width = 40,
      show_inactive_group_buffers = false,  -- Show only active group (default)
      show_icons = false,
      position = "left",
    })
  end
}
```

### Using vim-plug

```vim
Plug 'ruiheng/vertical-bufferline'

" In your init.vim or init.lua
lua << EOF
require('vertical-bufferline').setup({
  min_width = 40,
  show_inactive_group_buffers = false,  -- Show only active group (default)
  show_icons = false,
  position = "left",
})
EOF
```

### Using dein.vim

```vim
call dein#add('ruiheng/vertical-bufferline')

" Configuration in init.vim
lua << EOF
require('vertical-bufferline').setup()
EOF
```

### Manual Installation

1. Clone the repository:
```bash
git clone https://github.com/ruiheng/vertical-bufferline.git ~/.local/share/nvim/site/pack/plugins/start/vertical-bufferline
```

2. Add to your init.lua:
```lua
require('vertical-bufferline').setup()
```

### Requirements

- Neovim 0.8.0 or higher
- [bufferline.nvim](https://github.com/akinsho/bufferline.nvim)

This plugin transforms buffer management from a flat list into an organized, navigable workspace that scales with your project complexity.
