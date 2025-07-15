# Changelog

All notable changes to the Vertical Bufferline project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- History feature with per-group tracking of recent files
- Sidebar hotkeys `h` and `p` for toggling display modes
- `:VBufferLineClearHistory` command for history management
- `<leader>h1` to `<leader>h9` hotkeys for quick history access
- Comprehensive vim help documentation
- Session save/restore functionality for history data

### Fixed
- Click handling precision issues in history display
- Session restoration for history data
- Function definition order issues in Lua modules

### Changed
- Removed debug code from production builds
- Improved keymap organization and reduced duplication

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
- Initial release of Vertical Bufferline
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
- **Unreleased**: History feature, improved session management, enhanced documentation

## Migration Guide

### From v1.0.0 to v1.1.0
- No breaking changes
- New features are opt-in through configuration
- Existing configurations continue to work

### From v1.1.0 to Unreleased
- No breaking changes
- History feature is enabled by default with "auto" mode
- Existing keymaps are preserved, new sidebar hotkeys added

## Support

For issues, feature requests, or contributions, please visit the project repository.