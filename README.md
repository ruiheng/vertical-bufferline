# Vertical Bufferline

A Neovim plugin that provides a vertical sidebar displaying buffer groups with enhanced organization and navigation features.

## Features

### Core Features
- **Vertical sidebar** showing buffer groups and their contents
- **Adaptive width** - sidebar automatically adjusts width based on content (configurable min/max)
- **Dynamic buffer grouping** with automatic management
- **Seamless bufferline integration** - bufferline only shows current group's buffers
- **Perfect picking mode compatibility** with synchronized highlighting
- **Two display modes**: Expand all groups (default) or show only active group
- **Smart filename disambiguation** - automatically resolves duplicate filenames with minimal path context
- **Cursor alignment** - VBL content automatically aligns with your cursor position in the main window

### Group Management
- **Automatic buffer addition** - new buffers auto-join the active group
- **Smart group creation** - create unnamed groups instantly
- **Group numbering** - groups displayed as `[1] ● GroupName (5 buffers)`
- **Empty group names supported** for cleaner interface
- **Intelligent buffer cleanup** - deleted buffers automatically removed from groups

## Keymaps

### Built-in Keymaps (Sidebar Internal Only)

These keymaps are **hardcoded** and work automatically when the sidebar is open:
- `j/k` - Navigate up/down in sidebar
- `<CR>` - Switch to selected buffer
- `d` - Close selected buffer (with modification check)
- `q` - Close sidebar
- `h` - Toggle history display mode (yes/no/auto)
- `p` - Toggle path display mode (yes/no/auto)

### Plugin Functions (Require User Configuration)

The following keymaps are **not automatically configured** - you need to set them up in your plugin manager. See Installation section for examples.

**Sidebar Control:**
- `<leader>vb` - Toggle vertical bufferline sidebar
- `<leader>ve` - Toggle expand all groups mode
- `<leader>vi` - Toggle showing inactive groups

**Group Management:**
- `<leader>gc` - Create new unnamed group
- `<leader>gr` - Rename current group
- `<leader>gn` - Switch to next group
- `<leader>gp` - Switch to previous group
- `<leader>g1` to `<leader>g9` - Switch directly to group 1-9
- `<leader>gU` - Move current group up in the list
- `<leader>gD` - Move current group down in the list

**History Quick Access:**
- `<leader>h1` to `<leader>h9` - Quick switch to recent files 1-9 in current group history

### Recommended BufferLine Integration

This plugin is designed to work with [bufferline.nvim](https://github.com/akinsho/bufferline.nvim). Here are recommended bufferline keymaps that complement this plugin:

**Buffer Quick Access (provided by bufferline.nvim):**
- `<leader>1` to `<leader>9` - Quick switch to buffers 1-9 in current group
- `<leader>0` - Switch to 10th buffer in current group
- `<leader>p` - BufferLine picking mode (shows only current group buffers)

Example bufferline configuration:
```lua
-- In your bufferline.nvim setup
require('bufferline').setup({
  options = {
    numbers = "ordinal",  -- Shows 1, 2, 3... for <leader>1-9 access
  }
})

-- Keymaps for bufferline (add to your keymap configuration)
for i = 1, 9 do
  vim.keymap.set('n', '<leader>' .. i, '<cmd>BufferLineGoToBuffer ' .. i .. '<cr>',
    { desc = "Go to buffer " .. i })
end
vim.keymap.set('n', '<leader>p', '<cmd>BufferLinePick<cr>', { desc = "Pick buffer" })
```

## Commands

### Group Operations
- `:VBufferLineCreateGroup [name]` - Create new group with optional name
- `:VBufferLineDeleteGroup <name_or_id>` - Delete specified group
- `:VBufferLineRenameGroup <new_name>` - Rename current active group
- `:VBufferLineSwitchGroup [name_or_id]` - Switch to specified group
- `:VBufferLineAddToGroup <name_or_id>` - Add current buffer to specified group

### Navigation
- `:VBufferLineNextGroup` - Switch to next group
- `:VBufferLinePrevGroup` - Switch to previous group
- `:VBufferLineToggleExpandAll` - Toggle expand all groups mode
- `:VBufferLineToggleInactiveGroups` - Toggle showing buffer lists for inactive groups

### Group Reordering
- `:VBufferLineMoveGroupUp` - Move current group up in the list
- `:VBufferLineMoveGroupDown` - Move current group down in the list
- `:VBufferLineMoveGroupToPosition <position>` - Move current group to specified position

### Session Management
- `:VBufferLineSaveSession [filename]` - Save current groups configuration
- `:VBufferLineLoadSession [filename]` - Load groups configuration from session
- `:VBufferLineDeleteSession [filename]` - Delete a session file
- `:VBufferLineListSessions` - List all available sessions

### Utilities
- `:VBufferLineDebug` - Show debug information
- `:VBufferLineRefreshBuffers` - Manually refresh and add current buffers to active group
- `:VBufferLineClearHistory [group_name]` - Clear history for all groups or specific group
- `:VBufferLineToggleCursorAlign` - Toggle cursor alignment for VBL content
- `:VBufferLineToggleAdaptiveWidth` - Toggle adaptive width for VBL sidebar

## Display Modes

### Expand All Groups (Default)
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

### Active Group Only Mode
Shows only the current active group's buffers (classic mode):
```
[1] ● Frontend (3 buffers)
├─ ► 1 🌙 App.tsx
├─ 2 📄 Button.jsx
└─ 3 📝 README.md

[2] ○ Backend (2 buffers)
```

Toggle between modes with `<leader>ve` or `:VBufferLineToggleExpandAll`.

## Interface Elements

### Group Headers
- `[1] ● GroupName (5 buffers)` - Active group with name (PmenuSel background, bold text)
- `[2] ○ (3 buffers)` - Inactive unnamed group (Pmenu background)
- Numbers correspond to `<leader>g1`, `<leader>g2`, etc.
- Each group header uses semantic highlight groups that adapt to your theme

### Buffer Lines
- `► 1 🌙 filename.lua` - Current buffer with arrow marker
- `2 ● 📄 modified.js` - Modified buffer with dot indicator
- `└─ 3 📋 src/config.json` - Tree structure with smart disambiguation for duplicate names

### Picking Mode Integration
When using `<leader>p` (BufferLine picking), the sidebar shows hint characters:
```
├─ a ► 1 🌙 App.tsx
├─ s 2 📄 Button.jsx
└─ d 3 📝 README.md
```

## Workflow Examples

### Project Organization
```bash
# Create groups for different project areas
<leader>gc  # Create "Frontend" group (rename with <leader>gr)
<leader>gc  # Create "Backend" group
<leader>gc  # Create "Tests" group

# Organize group order
<leader>gU  # Move current group up
<leader>gD  # Move current group down

# Switch between project areas
<leader>g1  # Frontend
<leader>g2  # Backend
<leader>g3  # Tests
```

### File Type Organization
```bash
# Automatically organize by opening files
# Open React components → auto-added to current group
# Switch to new group → <leader>gc
# Open Python files → auto-added to new group
```

### Quick Navigation
```bash
# Within a group
<leader>1   # First buffer
<leader>2   # Second buffer
<leader>p   # Picking mode for current group

# Between groups
<leader>gn  # Next group
<leader>gp  # Previous group
```

### Session Persistence
```bash
# Sessions are automatically saved on exit and loaded on startup
# Manual session management:
:VBufferLineSaveSession          # Save current configuration
:VBufferLineLoadSession          # Load saved configuration
:VBufferLineListSessions         # View all available sessions

# Each working directory gets its own session file automatically
# Sessions include: group structure, buffer assignments, active group, display mode
```

### Advanced Workflow Examples

#### Multi-Project Development
```bash
# Working on frontend and backend simultaneously
<leader>gc                       # Create "Frontend" group
# Open React/Vue files → auto-added to Frontend group
<leader>gc                       # Create "Backend" group  
# Open API/server files → auto-added to Backend group
<leader>gc                       # Create "Database" group
# Open schema/migration files → auto-added to Database group

# Quick switching between contexts
<leader>g1                       # Frontend work
<leader>g2                       # Backend work
<leader>g3                       # Database work
```

#### Feature Branch Development
```bash
# Create feature-specific groups
<leader>gc                       # Create "Feature-Auth" group
<leader>gc                       # Create "Tests" group
<leader>gc                       # Create "Documentation" group

# Use history for quick access to recently modified files
<leader>h1                       # Most recent file in current group (2nd in history list)
<leader>h2                       # Second most recent file (3rd in history list)
```

#### Code Review Workflow
```bash
# Create review-specific groups
<leader>gc                       # Create "Review-Files" group
# Add files under review to this group
:VBufferLineAddToGroup Review-Files

# Toggle between original and reviewed code
<leader>g1                       # Original codebase group
<leader>g2                       # Review-Files group
```

#### Large Codebase Navigation
```bash
# Organize by module/component
<leader>gc                       # "Core"
<leader>gc                       # "Utils"  
<leader>gc                       # "UI-Components"
<leader>gc                       # "API-Layer"

# Use path display for disambiguation
p                                # Toggle path display in sidebar
# Shows minimal paths: src/Button.tsx vs components/Button.tsx

# Use history for recent work context
h                                # Toggle history display
<leader>h1-h9                    # Quick access to recent files
```

## Automatic Features

1. **Auto-add new buffers** - Files opened are automatically added to the active group
2. **Auto-cleanup deleted buffers** - Deleted files are automatically removed from all groups
3. **Smart buffer filtering** - Only normal file buffers are managed (excludes terminals, quickfix, etc.)
4. **Instant refresh** - UI updates immediately on group operations
5. **BufferLine synchronization** - BufferLine automatically shows only current group's buffers
6. **Session persistence** - Automatically save and restore group configurations across sessions
7. **Smart filename disambiguation** - When multiple files have the same name, automatically shows minimal unique paths

## History Feature

Each group maintains its own history of recently accessed files. The current active group's history is displayed as a special group at the top of the sidebar.

### History Display
- **Current Group History**: Shows recent files from the currently active group at the top
- **Current file first**: The current file is shown first without a number (marked with ►)
- **Numbered history**: Following files are numbered 1, 2, 3... representing access order
- **Auto mode**: History is shown when active group has 3+ files and history isn't empty
- **Manual toggle**: Use `h` key in sidebar to cycle through yes/no/auto modes
- **Configurable display count**: Maximum number of history items shown (default: 5)

### History Quick Access
- `<leader>h1` to `<leader>h9` - Quick switch to recent files 1-9 from current group's history
- `<leader>h1` accesses the most recent file (2nd in history list, after current file)
- `<leader>h2` accesses the second most recent file (3rd in history list), etc.
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
    width = 25,              -- Minimum width
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
    width = 40,
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

### Lazy.nvim Setup

For lazy.nvim users, you can configure the plugin with custom options:

```lua
{
  "your-username/vertical-bufferline",
  opts = {
    -- UI settings
    width = 25,                     -- Minimum sidebar width (for adaptive sizing)
    max_width = 60,                 -- Maximum sidebar width (for adaptive sizing)
    adaptive_width = true,          -- Enable adaptive width based on content
    expand_all_groups = true,       -- Default to expand all groups mode
    show_inactive_groups = false,   -- Show buffer lists for inactive groups (default: only active group)
    show_icons = false,             -- Show file type emoji icons
    position = "left",              -- Sidebar position: "left" or "right"
    show_tree_lines = false,        -- Show tree-style connection lines
    
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
    history_auto_threshold = 3,     -- Minimum files needed for auto mode to show history
    history_display_count = 5,      -- Maximum number of history items to display
    
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
    { "<leader>vb", "<cmd>lua require('vertical-bufferline').toggle()<cr>", desc = "Toggle vertical bufferline" },
    { "<leader>ve", "<cmd>lua require('vertical-bufferline').toggle_expand_all()<cr>", desc = "Toggle expand all groups" },
    { "<leader>gc", "<cmd>lua require('vertical-bufferline').create_group()<cr>", desc = "Create new group" },
    { "<leader>gn", "<cmd>lua require('vertical-bufferline').switch_to_next_group()<cr>", desc = "Next group" },
    { "<leader>gp", "<cmd>lua require('vertical-bufferline').switch_to_prev_group()<cr>", desc = "Previous group" },
  }
}
```

### Advanced Configuration Examples

#### Minimal Setup
```lua
{
  "your-username/vertical-bufferline",
  config = function()
    require('vertical-bufferline').setup()
  end
}
```

#### Power User Setup
```lua
{
  "your-username/vertical-bufferline",
  opts = {
    width = 30,
    max_width = 70,
    adaptive_width = true,
    position = "right",
    show_icons = true,
    show_tree_lines = true,
    show_path = "yes",
    show_history = "yes",
    history_size = 15,
    history_display_count = 8,
    auto_save = true,
    auto_load = true,
    session = {
      mini_sessions_integration = true,
      auto_serialize = true,
      auto_restore_prompt = false,
    }
  },
  keys = {
    { "<leader>vb", "<cmd>lua require('vertical-bufferline').toggle()<cr>" },
    { "<leader>ve", "<cmd>lua require('vertical-bufferline').toggle_expand_all()<cr>" },
    { "<leader>vi", "<cmd>VBufferLineToggleInactiveGroups<cr>" },
    { "<leader>gc", "<cmd>lua require('vertical-bufferline').create_group()<cr>" },
    { "<leader>gd", "<cmd>VBufferLineDeleteCurrentGroup<cr>" },
    { "<leader>gt", "<cmd>VBufferLineToggleExpandAll<cr>" },
  }
}
```

#### IDE-Style Setup
```lua
{
  "your-username/vertical-bufferline",
  opts = {
    width = 25,
    max_width = 50,
    adaptive_width = true,
    position = "left",
    expand_all_groups = false,  -- Start with collapsed groups
    show_icons = true,
    show_tree_lines = true,
    show_path = "auto",
    show_history = "auto",
    history_display_count = 10,
    path_style = "smart",
    auto_create_groups = true,
    auto_add_new_buffers = true,
    session = {
      auto_serialize = true,
      serialize_interval = 1000,  -- More frequent saves
      mini_sessions_integration = true,
    }
  }
}
```

#### Fixed Width Setup (Disable Adaptive Width)
```lua
{
  "your-username/vertical-bufferline",
  opts = {
    width = 40,
    adaptive_width = false,  -- Use traditional fixed width
    position = "left",
    show_icons = true,
  }
}
```

### Manual Configuration

If you prefer manual setup, the plugin initializes automatically when the sidebar is first opened. Default settings:

```lua
{
    -- UI settings
    width = 25,                     -- Minimum sidebar width (for adaptive sizing)
    max_width = 60,                 -- Maximum sidebar width (for adaptive sizing)
    adaptive_width = true,          -- Enable adaptive width based on content
    expand_all_groups = true,       -- Default to expand all groups mode
    show_icons = false,             -- Show file type emoji icons
    position = "left",              -- Sidebar position: "left" or "right"
    
    -- Group management
    auto_create_groups = true,      -- Enable automatic group creation
    auto_add_new_buffers = true,    -- Auto-add new buffers to active group
    
    -- Path display settings
    show_path = "auto",             -- "yes", "no", "auto" 
    path_style = "relative",        -- "relative", "absolute", "smart"
    path_max_length = 50,           -- Maximum path display length
    
    -- History settings
    show_history = "auto",          -- "yes", "no", "auto" - show recent files history per group
    history_size = 10,              -- Maximum number of recent files to track per group
    history_auto_threshold = 3,     -- Minimum files needed for auto mode to show history
    history_display_count = 5,      -- Maximum number of history items to display
    
    -- Session persistence settings
    auto_save = false,              -- Auto-save session on Neovim exit
    auto_load = false,              -- Auto-load session on startup
    session_name_strategy = "cwd_hash", -- "cwd_hash", "cwd_path", "manual"
}
```

## Integration

### BufferLine.nvim
- Seamlessly filters buffers to show only current group
- Perfect picking mode integration with synchronized highlights
- All BufferLine commands work within the current group context

### Scope.nvim
- Compatible with tabpage-scoped buffer management
- Buffer deletion respects scope.nvim's buffer handling

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

## Technical Details

- **Event-driven architecture** - Responds to Neovim buffer events automatically
- **High performance** - Minimal overhead, only processes when needed
- **Memory efficient** - Smart cleanup of invalid buffers and groups
- **Extensible design** - Clean API for future enhancements

## Recent Improvements

### Path Highlighting Consistency (v1.1.0)
**Issue**: Path lines in inactive groups had inconsistent highlighting, with some paths missing visual effects entirely.

**Root Cause**: Component data mismatch where inactive groups' components weren't included in the main highlighting loop, causing component lookup failures.

**Solution**: 
- Introduced `all_components` hash table to collect components from all groups
- Improved component lookup efficiency from O(n) linear search to O(1) hash access
- Ensured data consistency between rendering and highlighting phases

**Result**: All path lines now display consistent highlighting based on buffer state and group activity, with significant performance improvements.

## Installation

### Using lazy.nvim (Recommended)

Add to your lazy.nvim configuration:

```lua
{
  "your-username/vertical-bufferline",
  opts = {
    width = 40,
    expand_all_groups = true,
    show_icons = false,
    position = "left",
  },
  keys = {
    { "<leader>vb", "<cmd>lua require('vertical-bufferline').toggle()<cr>", desc = "Toggle vertical bufferline" },
    { "<leader>ve", "<cmd>lua require('vertical-bufferline').toggle_expand_all()<cr>", desc = "Toggle expand all groups" },
    { "<leader>gc", "<cmd>lua require('vertical-bufferline').create_group()<cr>", desc = "Create new group" },
    { "<leader>gn", "<cmd>lua require('vertical-bufferline').switch_to_next_group()<cr>", desc = "Next group" },
    { "<leader>gp", "<cmd>lua require('vertical-bufferline').switch_to_prev_group()<cr>", desc = "Previous group" },
  }
}
```

### Using packer.nvim

```lua
use {
  'your-username/vertical-bufferline',
  config = function()
    require('vertical-bufferline').setup({
      width = 40,
      expand_all_groups = true,
      show_icons = false,
      position = "left",
    })
  end
}
```

### Using vim-plug

```vim
Plug 'your-username/vertical-bufferline'

" In your init.vim or init.lua
lua << EOF
require('vertical-bufferline').setup({
  width = 40,
  expand_all_groups = true,
  show_icons = false,
  position = "left",
})
EOF
```

### Using dein.vim

```vim
call dein#add('your-username/vertical-bufferline')

" Configuration in init.vim
lua << EOF
require('vertical-bufferline').setup()
EOF
```

### Manual Installation

1. Clone the repository:
```bash
git clone https://github.com/your-username/vertical-bufferline.git ~/.local/share/nvim/site/pack/plugins/start/vertical-bufferline
```

2. Add to your init.lua:
```lua
require('vertical-bufferline').setup()
```

### Requirements

- Neovim 0.8.0 or higher
- Optional: [bufferline.nvim](https://github.com/akinsho/bufferline.nvim) for enhanced integration

### Post-Installation Setup

Ensure the keymap setup is called after plugin loading:

```lua
-- In your init.lua, after plugin loading
vim.api.nvim_create_autocmd("VimEnter", {
  pattern = "*",
  callback = function()
    local vbl = require('vertical-bufferline')
    
    -- Setup keymaps
    vim.keymap.set('n', '<leader>vb', function()
      vbl.toggle()
    end, { noremap = true, silent = true, desc = "Toggle vertical bufferline" })
    
    -- Group management keymaps
    vim.keymap.set('n', '<leader>gc', function()
      vbl.create_group()
    end, { noremap = true, silent = true, desc = "Create new buffer group" })
    
    vim.keymap.set('n', '<leader>gr', function()
      vim.ui.input({ prompt = "Rename current group to: " }, function(name)
        if name and name ~= "" then
          vim.cmd("VBufferLineRenameGroup " .. name)
        end
      end)
    end, { noremap = true, silent = true, desc = "Rename current buffer group" })
    
    vim.keymap.set('n', '<leader>ve', function()
      vbl.toggle_expand_all()
    end, { noremap = true, silent = true, desc = "Toggle expand all groups mode" })
    
    -- Navigation keymaps
    vim.keymap.set('n', '<leader>gn', function()
      vbl.switch_to_next_group()
    end, { noremap = true, silent = true, desc = "Switch to next buffer group" })
    
    vim.keymap.set('n', '<leader>gp', function()
      vbl.switch_to_prev_group()
    end, { noremap = true, silent = true, desc = "Switch to previous buffer group" })
    
    -- Group reordering keymaps
    vim.keymap.set('n', '<leader>gU', function()
      vbl.move_group_up()
    end, { noremap = true, silent = true, desc = "Move current group up" })
    
    vim.keymap.set('n', '<leader>gD', function()
      vbl.move_group_down()
    end, { noremap = true, silent = true, desc = "Move current group down" })
    
    -- Quick group switching (by display number, not array index)
    for i = 1, 9 do
      vim.keymap.set('n', '<leader>g' .. i, function()
        vbl.groups.switch_to_group_by_display_number(i)
      end, { noremap = true, silent = true, desc = "Switch to group " .. i })
    end
  end,
})
```

This plugin transforms buffer management from a flat list into an organized, navigable workspace that scales with your project complexity.