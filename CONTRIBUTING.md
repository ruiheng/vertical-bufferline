# Contributing to Vertical Bufferline

Thank you for considering contributing to Vertical Bufferline! This document provides guidelines for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Coding Standards](#coding-standards)
- [Documentation](#documentation)

## Code of Conduct

This project follows a standard code of conduct. Be respectful, inclusive, and constructive in all interactions.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Create a new branch for your feature/fix
4. Make your changes
5. Test your changes thoroughly
6. Submit a pull request

## Development Setup

### Prerequisites

- Neovim 0.8+ (for development and testing)
- Git
- Basic knowledge of Lua and Neovim plugin development

### Local Development

1. Clone the repository:
```bash
git clone https://github.com/your-username/vertical-bufferline.git
cd vertical-bufferline
```

2. Create a test environment:
```bash
# Create a minimal init.lua for testing
mkdir -p test-config/lua
```

3. Set up your test configuration in `test-config/init.lua`:
```lua
-- Add the plugin to runtimepath
vim.opt.rtp:prepend(vim.fn.getcwd())

-- Basic setup
require('vertical-bufferline').setup({
  -- Your test configuration
})
```

4. Test with: `nvim --clean -u test-config/init.lua`

## Making Changes

### Branch Naming

Use descriptive branch names:
- `feature/history-enhancement` - for new features
- `fix/session-restore-bug` - for bug fixes
- `docs/update-readme` - for documentation updates
- `refactor/component-system` - for refactoring

### Commit Messages

Follow conventional commit format:
```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat`: New features
- `fix`: Bug fixes
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `test`: Test additions/changes
- `chore`: Maintenance tasks

Examples:
```
feat(history): add per-group history tracking
fix(session): resolve history restoration issue
docs(readme): update installation instructions
```

## Testing

### Manual Testing

1. Test core functionality:
   - Sidebar toggle and display
   - Group creation, deletion, and switching
   - Buffer management within groups
   - History feature functionality
   - Session save/restore

2. Test edge cases:
   - Empty groups
   - Large number of buffers
   - Special buffer types (terminals, quickfix, etc.)
   - Session corruption recovery

3. Test integrations:
   - BufferLine.nvim compatibility
   - Scope.nvim compatibility
   - Mini.sessions integration

### Automated Testing

Run the window-scope sanity check:

```bash
nvim --headless -u NONE -i NONE -n "+lua dofile('scripts/window_scope_check.lua')"
```

Run the window-scope session save/restore check:

```bash
nvim --headless -u NONE -i NONE -n "+lua dofile('scripts/window_scope_session_check.lua')"
```

## Submitting Changes

### Pull Request Process

1. Ensure your branch is up to date with main
2. Rebase your commits if necessary
3. Update documentation if needed
4. Submit a pull request with:
   - Clear title and description
   - List of changes made
   - Testing performed
   - Screenshots/examples if applicable

### Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Refactoring

## Testing
- [ ] Manual testing performed
- [ ] All existing functionality verified
- [ ] New functionality tested

## Checklist
- [ ] Code follows project standards
- [ ] Documentation updated
- [ ] CHANGELOG.md updated (if applicable)
```

## Coding Standards

### Lua Style Guide

1. **Indentation**: 4 spaces (no tabs)
2. **Naming**: 
   - Variables: `snake_case`
   - Functions: `snake_case`
   - Constants: `UPPER_CASE`
   - Modules: `lowercase`

3. **Comments**:
   - Use `--` for single-line comments
   - Document complex logic
   - Add module headers with purpose description

4. **Error Handling**:
   - Use `pcall` for potentially failing operations
   - Provide meaningful error messages
   - Graceful degradation when possible

### Code Organization

1. **Module Structure**:
   ```lua
   -- Module header comment
   local M = {}
   
   -- Dependencies
   local api = vim.api
   
   -- Local variables
   local state = {}
   
   -- Local functions
   local function helper_function()
   end
   
   -- Public functions
   function M.public_function()
   end
   
   return M
   ```

2. **File Organization**:
   - One main concept per file
   - Clear separation of concerns
   - Minimal inter-module dependencies

## Documentation

### Documentation Requirements

1. **Code Documentation**:
   - Function purpose and parameters
   - Complex algorithm explanations
   - API documentation for public functions

2. **User Documentation**:
   - README.md updates for new features
   - Help file updates (doc/vertical-bufferline.txt)
   - Configuration examples

3. **Developer Documentation**:
   - Architecture decisions
   - Performance considerations
   - Integration points

### Documentation Standards

- Use clear, concise language
- Include practical examples
- Keep documentation up to date with code changes
- Follow vim help file conventions for user documentation

## Issue Reporting

### Bug Reports

Include:
- Neovim version
- Plugin version/commit
- Minimal configuration to reproduce
- Step-by-step reproduction
- Expected vs actual behavior
- Error messages (if any)

### Feature Requests

Include:
- Use case description
- Proposed solution
- Alternative approaches considered
- Impact on existing functionality

## Development Guidelines

### Performance Considerations

- Minimize API calls in hot paths
- Use lazy loading where appropriate
- Cache computed values when possible
- Profile performance-critical code

### Compatibility

- Support Neovim 0.8+
- Avoid deprecated API usage
- Test with different configurations
- Consider plugin interaction impacts

### Security

- Validate user input
- Sanitize file paths
- Handle malformed session data gracefully
- No arbitrary code execution

## Community

### Getting Help

- Check existing issues and documentation first
- Ask questions in issues (use "question" label)
- Be specific about your problem
- Provide context and examples

### Helping Others

- Answer questions in issues
- Review pull requests
- Improve documentation
- Share usage examples

Thank you for contributing to Vertical Bufferline!
