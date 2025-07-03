# Vertical Bufferline

A Neovim plugin that provides a vertical sidebar displaying buffer groups with enhanced organization and navigation features.

## Features

### Core Features
- **Vertical sidebar** showing buffer groups and their contents
- **Dynamic buffer grouping** with automatic management
- **Seamless bufferline integration** - bufferline only shows current group's buffers
- **Perfect picking mode compatibility** with synchronized highlighting
- **Two display modes**: Expand all groups (default) or show only active group

### Group Management
- **Automatic buffer addition** - new buffers auto-join the active group
- **Smart group creation** - create unnamed groups instantly
- **Group numbering** - groups displayed as `[1] ● GroupName (5 buffers)`
- **Empty group names supported** for cleaner interface
- **Intelligent buffer cleanup** - deleted buffers automatically removed from groups

## Keymaps

### Sidebar Control
- `<leader>vb` - Toggle vertical bufferline sidebar
- `<leader>ve` - Toggle expand all groups mode

### Group Management
- `<leader>gc` - Create new unnamed group (instant creation)
- `<leader>gr` - Rename current group (with input prompt)
- `<leader>gn` - Switch to next group
- `<leader>gp` - Switch to previous group
- `<leader>g1` to `<leader>g9` - Switch directly to group 1-9

### Buffer Navigation (within sidebar)
- `<CR>` - Switch to selected buffer
- `d` - Close selected buffer (with modification check)
- `q` or `<Esc>` - Close sidebar
- `j/k` - Navigate up/down

### Buffer Quick Access
- `<leader>1` to `<leader>9` - Quick switch to buffers 1-9 in current group
- `<leader>0` - Switch to 10th buffer in current group
- `<leader>p` - BufferLine picking mode (shows only current group buffers)

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

### Utilities
- `:VBufferLineDebug` - Show debug information
- `:VBufferLineRefreshBuffers` - Manually refresh and add current buffers to active group

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
- `[1] ● GroupName (5 buffers)` - Active group with name
- `[2] ○ (3 buffers)` - Inactive unnamed group
- Numbers correspond to `<leader>g1`, `<leader>g2`, etc.

### Buffer Lines
- `► 1 🌙 filename.lua` - Current buffer with arrow marker
- `2 ● 📄 modified.js` - Modified buffer with dot indicator
- `└─ 3 📋 config.json` - Tree structure with file icons

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

## Automatic Features

1. **Auto-add new buffers** - Files opened are automatically added to the active group
2. **Auto-cleanup deleted buffers** - Deleted files are automatically removed from all groups
3. **Smart buffer filtering** - Only normal file buffers are managed (excludes terminals, quickfix, etc.)
4. **Instant refresh** - UI updates immediately on group operations
5. **BufferLine synchronization** - BufferLine automatically shows only current group's buffers

## Configuration

The plugin initializes automatically when the sidebar is first opened. Default settings:

```lua
{
    max_buffers_per_group = 10,     -- Recommended buffer limit per group
    auto_create_groups = true,      -- Enable automatic group creation
    auto_add_new_buffers = true,    -- Auto-add new buffers to active group
    expand_all_groups = true,       -- Default to expand all groups mode
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

## Technical Details

- **Event-driven architecture** - Responds to Neovim buffer events automatically
- **High performance** - Minimal overhead, only processes when needed
- **Memory efficient** - Smart cleanup of invalid buffers and groups
- **Extensible design** - Clean API for future enhancements

## Installation

Add to your Neovim configuration and ensure the keymap setup is called after plugin loading:

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
    
    -- Quick group switching
    for i = 1, 9 do
      vim.keymap.set('n', '<leader>g' .. i, function()
        local groups = vbl.groups.get_all_groups()
        if groups[i] then
          vbl.groups.set_active_group(groups[i].id)
        end
      end, { noremap = true, silent = true, desc = "Switch to group " .. i })
    end
  end,
})
```

This plugin transforms buffer management from a flat list into an organized, navigable workspace that scales with your project complexity.