# Neovim Highlight Link + Attribute Issue

## Problem Summary

When using `vim.api.nvim_set_hl()` with both `link` and additional attributes like `bold` or `italic`, the additional attributes are not being applied or are being overridden by the linked highlight group.

## Environment

- **Neovim Version**: Recent version with `nvim_set_hl` API
- **Terminal**: tmux-256color (supports bold/italic - confirmed with manual escape sequences)
- **Context**: Vertical bufferline plugin development

## Expected Behavior

```lua
vim.api.nvim_set_hl(0, "MyHighlight", {
    link = "PmenuSel",
    bold = true
})
```

Should create a highlight group that:
1. Inherits background/foreground colors from `PmenuSel`
2. Adds bold text styling
3. Automatically updates when colorscheme changes

## Actual Behavior

- The highlight group gets the background/foreground colors from `PmenuSel`
- The `bold = true` attribute is ignored or overridden
- Text appears with normal weight, not bold

## Code Examples

### What Works (but doesn't auto-update with colorscheme)
```lua
local pmenusel_attrs = vim.api.nvim_get_hl(0, {name = 'PmenuSel'})
vim.api.nvim_set_hl(0, "MyHighlight", {
    bg = pmenusel_attrs.bg,
    fg = pmenusel_attrs.fg,
    bold = true
})
```

### What Doesn't Work (bold is ignored)
```lua
vim.api.nvim_set_hl(0, "MyHighlight", {
    link = "PmenuSel",
    bold = true
})
```

### What Works in Other Parts of the Same Codebase
```lua
-- These work fine and show bold text
vim.api.nvim_set_hl(0, "FILENAME_CURRENT", { link = "Title", bold = true })
vim.api.nvim_set_hl(0, "PREFIX_CURRENT", { link = "Directory", bold = true })
```

## Debugging Information

When debugging with `vim.api.nvim_get_hl()`, the problematic highlight shows:
```lua
{
  default = true,
  link = "PmenuSel"
}
```

The `bold = true` attribute is completely missing from the stored highlight definition.

## Terminal Capability Verification

Manual testing confirms terminal supports bold:
```bash
echo -e "\033[1mThis should be bold\033[0m normal text"
```
Shows bold text correctly.

## Key Questions

1. **Why does `link + bold` work for some highlight groups but not others?**
   - `FILENAME_CURRENT` with `link = "Title", bold = true` works
   - `GROUP_ACTIVE` with `link = "PmenuSel", bold = true` doesn't work

2. **Is there a difference between different linked highlight groups?**
   - Does `Title` handle additional attributes differently than `PmenuSel`?
   - Are there specific highlight groups that don't support attribute inheritance?

3. **Is there a proper way to combine link with additional attributes?**
   - Should attributes be set in a specific order?
   - Are there timing issues with when highlights are defined?

4. **Does `default = true` affect attribute inheritance?**
   - Could the `default` flag be preventing the bold attribute from being applied?

## Workaround Currently Used

```lua
-- Get colors from theme but set attributes explicitly
local pmenusel_attrs = vim.api.nvim_get_hl(0, {name = 'PmenuSel'})
local title_attrs = vim.api.nvim_get_hl(0, {name = 'Title'})

vim.api.nvim_set_hl(0, "GROUP_ACTIVE", {
    bg = pmenusel_attrs.bg,
    fg = title_attrs.fg or pmenusel_attrs.fg,
    bold = title_attrs.bold,
    italic = title_attrs.italic
})
```

This works but requires manual updates when colorscheme changes.

## Ideal Solution

A way to combine highlight linking with additional attributes that:
1. Inherits colors from the linked group
2. Adds the specified attributes (bold, italic, etc.)
3. Automatically updates when colorscheme changes
4. Works consistently across different base highlight groups

## Additional Context

This issue was discovered while developing a Neovim plugin where we need group headers to have:
- Background color matching the current theme's menu selection color
- Bold or italic text for visual emphasis
- Automatic updates when users switch colorschemes

The inconsistency between different highlight groups (`Title` vs `PmenuSel`) suggests there might be specific behaviors or limitations we're not aware of.