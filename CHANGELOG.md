# Changelog

All notable changes to the Buffer Nexus project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Adaptive width feature** - Sidebar automatically adjusts width based on content
  - `min_width` option sets minimum width (default: 15, changed from 40)
  - `max_width` option sets maximum sidebar width (default: 60)
  - `adaptive_width` option to enable/disable feature (default: true)
  - `:BNToggleAdaptiveWidth` command to toggle at runtime
  - Width state persists across sidebar open/close cycles
  - Works with both split and floating window modes
- **Comprehensive EmmyLua annotations** for full LSP autocompletion support
  - `@class VerticalBufferline` type definition for main module
  - All public API functions documented with `@param`, `@return`, and `@field` tags
  - Parameter descriptions with type constraints and default values
  - Compatible with lua-language-server for IDE integration
- **Enhanced vimdoc help file** with 39 help tags
  - New sections: Requirements, Adaptive Width, About
  - Multiple installation methods documented (lazy.nvim, packer, vim-plug, manual)
  - Individual help tags for all configuration options
  - Proper Neovim help file conventions with tag completion
  - Accessible via `:help buffer-nexus`
- History feature with per-group tracking of recent files
- Sidebar hotkeys `h` and `p` for toggling display modes
- `:BNClearHistory` command for history management
- `<leader>h1` to `<leader>h9` hotkeys for quick history access
- Session save/restore functionality for history data
- **Cursor alignment feature** - BN content automatically aligns with main window cursor position
- `align_with_cursor` configuration option (default: true)
- `:BNToggleCursorAlign` command to toggle cursor alignment
- Intelligent path compression with progressive abbreviation (3→2→1 chars)
- Path disambiguation to Recent Files display
- Debug logging system with file output and memory buffer
- Debug commands: `:BNDebugEnable`, `:BNDebugDisable`, `:BNDebugStatus`, `:BNDebugLogs`

### Fixed
- Click handling precision issues in history display
- Session restoration for history data
- Function definition order issues in Lua modules
- Cursor alignment impact on group header highlighting
- Recent Files synchronization with current group buffers
- Debug log display handling of newlines in log entries
- Cursor alignment viewport calculation preventing content overflow
- SessionLoadPost responding incorrectly to loadview commands
- Cursor alignment highlighting - adjusted all mappings for offset
- Unnamed buffer handling with improved code organization
- Smaller bullet characters for all indicators (improved visual consistency)
- Numbering highlights now sync with filename state (current/visible/inactive)

### Changed
- Removed debug code from production builds
- Improved keymap organization and reduced duplication
- Default minimum width changed from 40 to 25 (better space efficiency with adaptive width)
- Disabled BufEnter autocmd after review

### Removed
- **Manual session commands** (obsolete due to auto-serialization)
  - Removed `:BNSaveSession`, `:BNLoadSession`, `:BNDeleteSession`, `:BNListSessions`
  - Sessions now automatically managed via `auto_serialize` and Neovim's `:mksession`
  - Users simply use native `:mksession` and `:source` - BN state is included automatically
- JSON session persistence (`auto_save`, `auto_load`, `session_name_strategy`)

### Documentation Improvements
- **Clarified keymaps documentation** - separated built-in vs user-configured vs bufferline keymaps
- **Added comprehensive session management explanation** - how auto-serialization works
- **Clear BufferLine integration section** - shows recommended bufferline keymaps with examples
- **New help tag**: `*buffer-nexus-bufferline-keymaps*` for BufferLine integration
- **Updated all examples** to show correct usage of `:mksession` instead of manual commands

## [1.1.0] - 2024-XX-XX

### Added
- Smart numbering system with dual local|global format
- Configurable file type icons (emoji-based)
- Component-based rendering system for better performance
- Path highlighting consistency improvements

### Fixed
- Path highlighting inconsistency issue where inactive groups had missing visual effects
- Component data mismatch causing lookup failures
- Performance improvements with O(1) hash access instead of O(n) linear search

### Changed
- Improved component lookup efficiency
- Enhanced data consistency between rendering and highlighting phases

## [1.0.0] - 2024-XX-XX

### Added
- Initial release of Buffer Nexus
- Vertical sidebar with buffer group management
- Dynamic buffer grouping with automatic management
- Seamless bufferline integration
- Perfect picking mode compatibility
- Two display modes: Expand all groups and Active group only
- Smart filename disambiguation
- Group management commands and keymaps
- Session persistence
- BufferLine.nvim integration
- Scope.nvim compatibility

### Features
- Automatic buffer addition to active groups
- Smart group creation and management
- Group numbering and navigation
- Buffer quick access with numbered hotkeys
- Mouse support for buffer selection
- Intelligent buffer cleanup
- Tree-style visual representation
- Group reordering capabilities
- Manual and automatic session management

### Integration
- Works seamlessly with bufferline.nvim
- Compatible with scope.nvim for tabpage management
- Supports mini.sessions integration
- Event-driven architecture for automatic updates

---

## Version History Summary

- **v1.1.0**: Added smart numbering, configurable icons, component-based rendering
- **v1.0.0**: Initial release with core buffer group management features
- **Unreleased**: Adaptive width, EmmyLua annotations, enhanced documentation, history feature, cursor alignment, debug logging

## Migration Guide

### From v1.0.0 to v1.1.0
- No breaking changes
- New features are opt-in through configuration
- Existing configurations continue to work

### From v1.1.0 to Unreleased
- **Configuration change**: Default `min_width` changed from 40 to 15
  - If you want to keep the old width, explicitly set `min_width = 40` in your config
  - New adaptive width feature automatically adjusts between `min_width` (min) and `max_width` (max)
  - To disable adaptive width: set `adaptive_width = false`
- History feature is enabled by default with "auto" mode
- Existing keymaps are preserved, new sidebar hotkeys added (`h`, `p`)
- EmmyLua annotations provide LSP autocompletion (no action needed)
- Enhanced help file accessible via `:help buffer-nexus`

## Support

For issues, feature requests, or contributions, please visit the project repository.
